import 'dart:async';
import 'dart:convert';

import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'miru_protocol.dart';

class MiruSync extends ChangeNotifier with WidgetsBindingObserver {
  MiruSync._();
  @visibleForTesting
  MiruSync.testing({required Future<Map<String, dynamic>> Function() capture,
    required Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?) request,
    required Stream<void> changes, Duration timeout = const Duration(seconds: 12)}) {
    _testCapture = capture;
    _testRequest = request;
    _testChanges = changes;
    _localTimeout = timeout;
    enabled = true;
    _token = 'test';
  }
  Future<Map<String, dynamic>> Function()? _testCapture;
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)? _testRequest;
  Stream<void>? _testChanges;
  Duration _localTimeout = const Duration(seconds: 12);
  static final instance = MiruSync._();
  static const _keychain = MethodChannel('cashew/miru-keychain');
  bool get supported => _testCapture != null || (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);
  bool enabled = false;
  bool busy = false;
  String address = '';
  String _token = '';
  bool get paired => _token.isNotEmpty;
  String message = '尚未连接米汝';
  String? lastSynced;
  int? count;
  Timer? _timer, _debounce, _retry;
  bool _requested = false;
  bool _disposed = false;
  String _stage = '';
  StreamSubscription<dynamic>? _changes;
  FinanceDatabase? _watchedDb;
  Future<void>? _initialization;
  String? _lastHash, _pendingHash, _pendingId;
  int? _lastRevision;
  bool _restorePending = false;
  bool _restoring = false;
  Completer<void>? _syncDone;
  int _failures = 0;
  DateTime? _retryAfter;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!supported) return;
    try {
      final stored = _testCapture != null ? null : await _keychain.invokeMethod<String>('read').timeout(_localTimeout);
      if (stored != null) {
        final value = jsonDecode(stored) as Map;
        address = value['address'] as String;
        miruEndpoint(address);
        _token = value['token'] as String;
        enabled = value['enabled'] == true;
        _restorePending = value['restore_pending'] == true;
        _pendingId = value['pending_id'] as String?;
        _pendingHash = value['pending_hash'] as String?;
        _lastHash = value['last_hash'] as String?;
        _lastRevision = value['last_revision'] as int?;
        message = enabled ? '等待同步' : '同步已暂停';
      }
      if (isDatabaseImportedOnThisSession && _token.isNotEmpty) {
        _restorePending = true;
        await _save();
      }
    } catch (_) {
      message = '安全存储暂时不可用，正在自动重试';
      _initialization = null;
      _retry = Timer(const Duration(seconds: 5), () { if (!_disposed) initialize(); });
      notifyListeners();
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _watchDatabase();
    // Keep retry triggers available even if reading Keychain failed on startup.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => schedule());
    schedule();
    notifyListeners();
  }

  void _watchDatabase() {
    if (_testChanges != null) {
      _changes ??= _testChanges!.listen((_) => schedule());
      return;
    }
    if (identical(_watchedDb, database)) return;
    _changes?.cancel();
    _watchedDb = database;
    _lastHash = null;
    _changes = database.tableUpdates().listen((_) => schedule(), onError: (_) {
      message = '等待本地账本恢复';
      notifyListeners();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _retryAfter = null;
      schedule(immediate: true);
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Flush the last committed edit before iOS suspends this app.
      if (_requested) {
        _debounce?.cancel();
        unawaited(sync(allowBackground: true));
      }
    }
  }

  void schedule({bool immediate = false}) {
    if (!enabled || !supported || _restoring || _disposed) return;
    _requested = true;
    if (busy) return;
    _debounce?.cancel();
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 250), () => sync());
  }

  Future<void> _save() async {
    if (_testCapture != null) return;
    await _keychain.invokeMethod<void>('write', jsonEncode({
    'address': address, 'token': _token, 'enabled': enabled,
    'restore_pending': _restorePending, 'pending_id': _pendingId,
    'pending_hash': _pendingHash, 'last_hash': _lastHash, 'last_revision': _lastRevision,
    })).timeout(_localTimeout);
  }

  void _setStage(String value) {
    _stage = value;
    message = '$value…';
    notifyListeners();
  }

  Future<void> _backgroundLease(String method) async {
    if (_testCapture != null) return;
    try { await _keychain.invokeMethod<void>(method).timeout(const Duration(seconds: 2)); }
    catch (_) { /* Optional lease; foreground sync still works. */ }
  }

  // Called before replacing the native database file. Persist the guard across restarts.
  Future<void> pauseForRestore() async {
    if (!supported) return;
    await initialize();
    _restoring = true;
    _restorePending = true;
    _debounce?.cancel();
    _timer?.cancel();
    _retry?.cancel();
    await _syncDone?.future;
    _restorePending = true;
    _pendingId = null;
    _pendingHash = null;
    _lastHash = null;
    if (_token.isNotEmpty) await _save();
    message = '恢复备份期间暂停上传，重启 Cashew 后重新核对';
    notifyListeners();
  }

  Future<Map<String, dynamic>> _request(String path, {Map<String, dynamic>? body, bool pairing = false}) async {
    if (_testRequest != null) return _testRequest!(path, body).timeout(_localTimeout);
    final endpoint = miruEndpoint(address).replace(path: '/api/finance/sync/$path');
    final request = http.Request(body == null ? 'GET' : 'POST', endpoint)..followRedirects = false;
    if (!pairing) request.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      final encoded = miruJsonEncode(body);
      if (utf8.encode(encoded).length > 16 * 1024 * 1024) {
        throw const MiruSyncError('snapshot_too_large');
      }
      request.headers['Content-Type'] = 'application/json';
      request.headers['X-Content-SHA256'] = miruHash(encoded);
      request.bodyBytes = utf8.encode(encoded);
    }
    final client = http.Client();
    try {
      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(Duration(seconds: body == null ? 12 : 25));
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        final detail = decoded is Map ? decoded['detail'] : null;
        throw MiruSyncError(detail is Map ? detail['code'].toString() : 'connection_failed');
      }
      return Map<String, dynamic>.from(decoded as Map);
    } finally {
      client.close();
    }
  }

  Future<void> pair(String url, String code) async {
    await initialize();
    if (!supported || busy) return;
    final normalized = miruEndpoint(url).toString();
    if (code.trim().isEmpty) throw const FormatException('请填写米汝中的配对码');
    final oldAddress = address;
    final oldToken = _token;
    final oldEnabled = enabled;
    busy = true;
    address = normalized;
    notifyListeners();
    try {
      final result = await _request('pair', body: {'code': code.trim()}, pairing: true);
      _token = result['token'] as String;
      enabled = true;
      _lastHash = null;
      _pendingId = null;
      _pendingHash = null;
      _lastRevision = null;
      _restorePending = true;
      await _save();
      message = '连接成功，准备同步';
      _failures = 0;
      _retryAfter = null;
    } catch (_) {
      address = oldAddress;
      _token = oldToken;
      enabled = oldEnabled;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
    await sync(force: true);
  }

  Future<void> setEnabled(bool value) async {
    if (busy || _token.isEmpty) return;
    final previous = enabled;
    enabled = value;
    try { await _save(); } catch (_) { enabled = previous; rethrow; }
    message = value ? '等待同步' : '同步已暂停';
    notifyListeners();
    if (value) await sync(force: true);
  }

  Future<Map<String, dynamic>> _capture() async {
    if (_testCapture != null) return _testCapture!();
    if (isDatabaseCorrupted) throw const MiruSyncError('local_database_unavailable');
    final db = database;
    return db.transaction(() async {
      final wallets = await db.select(db.wallets).get();
      final categories = await db.select(db.categories).get();
      final budgets = await db.select(db.budgets).get();
      final objectives = await db.select(db.objectives).get();
      final transactions = await db.select(db.transactions).get();
      final precision = {for (final wallet in wallets) wallet.walletPk: wallet.decimals};
      final result = <String, dynamic>{
        'wallets': wallets.map((w) => {'id': w.walletPk, 'name': w.name,
          'currency': w.currency?.toUpperCase() ?? 'UNKNOWN', 'decimals': w.decimals, 'raw': w.toJson()}).toList(),
        'categories': categories.map((c) => {'id': c.categoryPk, 'name': c.name, 'raw': c.toJson()}).toList(),
        'budgets': budgets.map((b) => {'id': b.budgetPk, 'name': b.name, 'raw': b.toJson()}).toList(),
        'objectives': objectives.map((o) => {'id': o.objectivePk, 'name': o.name, 'raw': o.toJson()}).toList(),
        'transactions': transactions.map((t) => {
          'id': t.transactionPk, 'title': t.name, 'note': t.note,
          'amount': miruAmount(t.amount, precision[t.walletFk] ?? 2),
          'occurred_at': miruDateWithOffset(t.dateCreated), 'local_date': miruLocalDate(t.dateCreated.toLocal()),
          'income': t.income, 'paid': t.paid, 'skipped': t.skipPaid, 'kind': t.type?.name,
          'wallet_id': t.walletFk, 'category_id': t.categoryFk, 'subcategory_id': t.subCategoryFk,
          'paired_id': t.pairedTransactionFk, 'raw': t.toJson(),
        }).toList(),
      };
      for (final list in result.values) {
        (list as List).sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      }
      return result;
    });
  }

  Future<void> sync({bool force = false, bool allowBackground = false}) async {
    if (!supported || !enabled || _restoring || _disposed) return;
    if (busy) { _requested = true; return; }
    if (!allowBackground && WidgetsBinding.instance.lifecycleState != null && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (!force && _retryAfter != null && DateTime.now().isBefore(_retryAfter!)) {
      _retry?.cancel();
      _retry = Timer(_retryAfter!.difference(DateTime.now()), () => sync(force: true));
      return;
    }
    _retry?.cancel();
    _requested = false;
    busy = true;
    _syncDone = Completer<void>();
    message = '正在同步…';
    notifyListeners();
    try {
      await _backgroundLease('beginSync');
      _watchDatabase();
      _setStage('读取本地账本');
      final data = await _capture().timeout(_localTimeout);
      _setStage('连接米汝服务器');
      final status = await _request('status');
      final hash = miruHash(miruJsonEncode(data));
      if (_pendingId != null && status['snapshot_id'] == _pendingId) {
        _lastHash = _pendingHash;
        _lastRevision = status['revision'] as int;
        _restorePending = false;
        _pendingId = null;
        await _save();
      }
      final reconciliation = status['reconciliation'];
      if (reconciliation is Map && _pendingId == reconciliation['snapshot_id'] && _pendingHash == hash) {
        throw const MiruSyncError('reconciliation_required');
      }
      if (_restoring) return;
      if (_lastHash != hash || _lastRevision != status['revision'] || _restorePending) {
        final id = uuid.v4();
        _pendingId = id;
        _pendingHash = hash;
        _setStage('保存同步进度');
        await _save();
        if (_restoring) return;
        _setStage('上传账本');
        final result = await _request('snapshot', body: {
          'protocol': 1, 'schema_version': schemaVersionGlobal, 'snapshot_id': id,
          'base_revision': status['revision'],
          'app_version': '${packageInfoGlobal?.version ?? 'unknown'}+${packageInfoGlobal?.buildNumber ?? 'unknown'}',
          'generated_at': DateTime.now().toUtc().toIso8601String(), 'timezone': 'Asia/Shanghai',
          'restored_backup': _restorePending,
          ...data,
        });
        _lastRevision = result['revision'] as int;
        _lastHash = hash;
        _restorePending = false;
        _pendingId = null;
        await _save();
        lastSynced = DateTime.now().toLocal().toString().split('.').first;
      } else {
        lastSynced = DateTime.tryParse(status['synced_at']?.toString() ?? '')?.toLocal().toString().split('.').first;
      }
      count = (data['transactions'] as List).length;
      message = '已同步 $count 笔账单';
      _failures = 0;
      _retryAfter = null;
    } catch (e) {
      _failures = (_failures + 1).clamp(1, 6);
      _retryAfter = DateTime.now().add(Duration(seconds: 5 * (1 << _failures)));
      message = e is TimeoutException ? '$_stage超时；账单已保存在本机，将自动重试' : errorMessage(e);
      _requested = true;
      _retry?.cancel();
      _retry = Timer(Duration(seconds: 5 * (1 << _failures)), () => sync(force: true));
    } finally {
      await _backgroundLease('endSync');
      busy = false;
      _syncDone?.complete();
      _syncDone = null;
      notifyListeners();
      if (_requested && _retryAfter == null) schedule(immediate: true);
    }
  }

  static String errorMessage(Object error) {
    if (error is JsonUnsupportedObjectError) return '已配对，但账本字段转换失败；请更新 Cashew 后点击立即同步，无需重新配对';
    if (error is FormatException) return error.message;
    if (error is MiruSyncError) {
      switch (error.code) {
        case 'reconciliation_required': return '账本恢复或数量明显减少，请到米汝账本页核对并采用';
        case 'sync_token_invalid': return '上传凭据已失效，请重新配对';
        case 'pairing_invalid_or_expired': return '配对码无效、已过期或已使用。若显示已配对，请直接点立即同步；切换 App 不会使配对码失效';
        case 'snapshot_too_large': return '账本超过 16 MB，同步尚未完成，请联系维护者启用分块上传';
        case 'invalid_snapshot': return '账本格式未通过校验，云端保留上一版，请联系维护者';
        case 'revision_conflict': return '云端版本已变化，稍后重新对账';
        case 'local_database_unavailable': return '本地账本暂不可读，已暂停上传';
      }
    }
    return '同步暂未完成，正在自动重试；本地账单和配对信息已保留，无需手动同步';
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel(); _debounce?.cancel(); _retry?.cancel();
    _changes?.cancel();
    super.dispose();
  }
}

class MiruSyncError implements Exception {
  const MiruSyncError(this.code);
  final String code;
}

class MiruSyncHost extends StatefulWidget {
  const MiruSyncHost({super.key, required this.child});
  final Widget child;
  @override
  State<MiruSyncHost> createState() => _MiruSyncHostState();
}

class _MiruSyncHostState extends State<MiruSyncHost> {
  @override
  void initState() {
    super.initState();
    MiruSync.instance.initialize();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}

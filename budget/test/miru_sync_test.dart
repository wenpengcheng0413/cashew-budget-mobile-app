import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:budget/integrations/miru/miru_sync.dart';

Map<String, dynamic> ledger(int count) => {
  'wallets': [], 'categories': [], 'budgets': [], 'objectives': [],
  'transactions': List.generate(count, (i) => {'id': '$i'}),
};

class Cloud {
  int revision = 0;
  String? snapshot;
  final uploads = <Map<String, dynamic>>[];
  Completer<void>? hold;
  Future<Map<String, dynamic>> request(String path, Map<String, dynamic>? body) async {
    if (path == 'status') return {'revision': revision, 'snapshot_id': snapshot};
    uploads.add(body!);
    await hold?.future;
    snapshot = body['snapshot_id'];
    return {'revision': ++revision, 'snapshot_id': snapshot};
  }
}

void main() {
  testWidgets('edits during upload are automatically sent in a second snapshot', (tester) async {
    final changes = StreamController<void>.broadcast();
    final cloud = Cloud()..hold = Completer<void>();
    var count = 1;
    final sync = MiruSync.testing(capture: () async => ledger(count), request: cloud.request, changes: changes.stream);
    final first = sync.sync();
    await tester.pump();
    expect(cloud.uploads, hasLength(1));
    count = 2;
    changes.add(null);
    await tester.pump();
    cloud.hold!.complete();
    await first;
    await tester.pump(const Duration(milliseconds: 1));
    expect(cloud.uploads, hasLength(2));
    expect(cloud.uploads.last['transactions'], hasLength(2));
    expect(sync.busy, isFalse);
    sync.dispose(); await changes.close();
  });

  testWidgets('stalled capture times out and retries without a manual button', (tester) async {
    final changes = StreamController<void>.broadcast();
    final cloud = Cloud();
    final stalled = Completer<Map<String, dynamic>>();
    var attempts = 0;
    final sync = MiruSync.testing(capture: () => ++attempts == 1 ? stalled.future : Future.value(ledger(2)),
      request: cloud.request, changes: changes.stream, timeout: const Duration(seconds: 1));
    final first = sync.sync();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await first;
    expect(sync.busy, isFalse);
    expect(sync.message, contains('读取本地账本超时'));
    await tester.pump(const Duration(seconds: 10));
    expect(cloud.uploads, hasLength(1));
    stalled.complete(ledger(0));
    await tester.pump();
    expect(cloud.uploads, hasLength(1));
    expect(sync.message, '已同步 2 笔账单');
    sync.dispose(); await changes.close();
  });

  testWidgets('switching apps flushes a pending committed edit immediately', (tester) async {
    final changes = StreamController<void>.broadcast();
    final cloud = Cloud();
    var count = 1;
    final sync = MiruSync.testing(capture: () async => ledger(count), request: cloud.request, changes: changes.stream);
    await sync.sync();
    count = 2;
    changes.add(null);
    await tester.pump();
    sync.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pump();
    expect(cloud.uploads, hasLength(2));
    expect(sync.count, 2);
    sync.dispose(); await changes.close();
  });
}

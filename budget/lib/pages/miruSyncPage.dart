import 'package:budget/integrations/miru/miru_sync.dart';
import 'package:flutter/material.dart';

class MiruSyncPage extends StatefulWidget {
  const MiruSyncPage({super.key});
  @override
  State<MiruSyncPage> createState() => _MiruSyncPageState();
}

class _MiruSyncPageState extends State<MiruSyncPage> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  final sync = MiruSync.instance;
  String? _error;

  @override
  void initState() {
    super.initState();
    sync.initialize().then((_) { if (mounted) setState(() => _address.text = sync.address); });
  }

  @override
  void dispose() { _address.dispose(); _code.dispose(); super.dispose(); }

  Future<void> _pair() async {
    setState(() => _error = null);
    try { await sync.pair(_address.text, _code.text); _code.clear(); }
    catch (e) { if (mounted) setState(() => _error = MiruSync.errorMessage(e)); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('米汝同步')),
    body: AnimatedBuilder(animation: sync, builder: (context, _) => ListView(padding: const EdgeInsets.all(20), children: [
      const Text('将每笔账单、账户、分类、预算和目标同步到你的米汝服务器，在米汝查看收支或直接问账。Cashew 仍是记账和修改的地方。'),
      const SizedBox(height: 20),
      if (!sync.supported) const Text('当前接入支持 iPhone 侧载版。'),
      TextField(controller: _address, enabled: !sync.busy, autocorrect: false,
        keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: '米汝服务器地址', hintText: 'https://…')),
      const SizedBox(height: 12),
      TextField(controller: _code, enabled: !sync.busy, autocorrect: false, enableSuggestions: false,
        obscureText: true, decoration: const InputDecoration(labelText: '一次性配对码', helperText: '米汝 → 我的账本 → 连接 Cashew')),
      const SizedBox(height: 16),
      FilledButton(onPressed: sync.supported && !sync.busy ? _pair : null, child: const Text('配对并同步')),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('自动同步'), value: sync.enabled,
        onChanged: sync.supported && !sync.busy && sync.address.isNotEmpty ? (v) async {
          try { await sync.setEnabled(v); } catch (_) { if (mounted) setState(() => _error = '无法保存同步设置，请重试'); }
        } : null),
      if (sync.busy) const LinearProgressIndicator(),
      const SizedBox(height: 16), Text(sync.message),
      if (sync.lastSynced != null) Text('最近成功同步：${sync.lastSynced}'),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      TextButton.icon(onPressed: sync.enabled && !sync.busy ? () => sync.sync(force: true) : null,
        icon: const Icon(Icons.sync), label: const Text('立即同步')),
      const SizedBox(height: 24),
      const Text('无网也能继续记账。联网并打开 Cashew 后自动补同步；iOS 关闭 App 后不保证持续上传。配对信息只保存在本机安全存储，不进入账本导出。'),
    ])),
  );
}

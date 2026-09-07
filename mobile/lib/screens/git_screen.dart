import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';

class GitScreen extends StatefulWidget {
  const GitScreen({super.key});

  @override
  State<GitScreen> createState() => _GitScreenState();
}

class _GitScreenState extends State<GitScreen> {
  GitStatus? _status;
  String? _error;
  bool _busy = false;
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final status = await context.read<SessionController>().client.gitStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _run(Future<GitStatus> Function() action, {required String confirm}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认操作'),
        content: Text(confirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final status = await action();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status.output?.trim().isNotEmpty == true ? status.output! : '完成')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = context.read<SessionController>().client;
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Git'),
        actions: [
          IconButton(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: PilotColors.bad)),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: status == null
                  ? const Text('读取仓库状态…', style: TextStyle(color: PilotColors.muted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('分支 ${status.branch}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(status.lastCommit.isEmpty ? '还没有提交' : status.lastCommit),
                        const SizedBox(height: 6),
                        Text(
                          status.remote.isEmpty ? '未配置 origin' : status.remote,
                          style: const TextStyle(color: PilotColors.muted),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          status.dirty ? '有未提交改动 ${status.dirtyFiles.length} 个' : '工作区干净',
                          style: TextStyle(color: status.dirty ? PilotColors.accent : PilotColors.good),
                        ),
                        if (status.dirtyFiles.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(status.dirtyFiles.take(12).join('\n'), style: const TextStyle(fontFamily: 'monospace')),
                        ],
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _busy ? null : () => _run(client.gitPull, confirm: '将在服务器工作区执行 git pull --ff-only。'),
            child: const Text('从 GitHub 拉取'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _message,
            decoration: const InputDecoration(labelText: '提交说明', hintText: '例如：更新配置片段'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () => _run(
                      () => client.gitCommit(_message.text.trim()),
                      confirm: '将提交工作区里的全部已跟踪变更，不会 push。',
                    ),
            child: const Text('提交到本地仓库'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : () => _run(client.gitPush, confirm: '将把当前分支推到 origin。请确认你已经看过改动。'),
            child: const Text('推送到 GitHub'),
          ),
          const SizedBox(height: 16),
          const Text(
            '这些按钮走后端白名单命令，不会让模型随便拼 git 参数。推送前建议先看任务日志。',
            style: TextStyle(color: PilotColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

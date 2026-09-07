import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/status_chip.dart';
import 'compose_screen.dart';
import 'git_screen.dart';
import 'settings_screen.dart';
import 'task_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WorkspaceInfo? _workspace;
  List<RemoteTask> _tasks = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = context.read<SessionController>().client;
      final workspace = await client.workspace();
      final tasks = await client.tasks();
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _tasks = tasks;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uplink'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ComposeScreen()));
          if (mounted) _reload();
        },
        icon: const Icon(Icons.send),
        label: const Text('发任务'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: PilotColors.bad)),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _loading && workspace == null
                    ? const Text('正在读取工作区…', style: TextStyle(color: PilotColors.muted))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('服务器工作区', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text(workspace?.path ?? '-', style: const TextStyle(fontFamily: 'monospace')),
                          const SizedBox(height: 8),
                          Text(
                            workspace?.git == null
                                ? (workspace?.gitError ?? '不是 git 仓库，Git 按钮将不可用')
                                : '${workspace!.git!.branch} · ${workspace.git!.dirty ? '有未提交改动' : '干净'}',
                            style: const TextStyle(color: PilotColors.muted),
                          ),
                          if (workspace?.model.isNotEmpty == true) ...[
                            const SizedBox(height: 6),
                            Text('模型 ${workspace!.model}', style: const TextStyle(color: PilotColors.muted)),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const GitScreen()),
                                    );
                                    if (mounted) _reload();
                                  },
                                  child: const Text('Git 操作'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('最近任务', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (!_loading && _tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Text('还没有任务。点右下角发一句给 Agent。', style: TextStyle(color: PilotColors.muted)),
              ),
            for (final task in _tasks) _TaskTile(task: task, onChanged: _reload),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onChanged});

  final RemoteTask task;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(task.createdAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(task.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(time, style: const TextStyle(color: PilotColors.muted)),
        ),
        trailing: StatusChip(status: task.status),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TaskScreen(taskId: task.id)),
          );
          await onChanged();
        },
      ),
    );
  }

  String _formatTime(String raw) {
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    return DateFormat('MM-dd HH:mm').format(parsed);
  }
}

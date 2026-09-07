import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/log_view.dart';
import '../widgets/status_chip.dart';

class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key, required this.taskId});

  final String taskId;

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final _scroll = ScrollController();
  RemoteTask? _task;
  String? _error;
  Timer? _timer;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (_task?.isActive ?? true) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final task = await context.read<SessionController>().client.task(widget.taskId);
      if (!mounted) return;
      final shouldStick = !_scroll.hasClients ||
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 80;
      setState(() {
        _task = task;
        _error = null;
      });
      if (shouldStick) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await context.read<SessionController>().client.cancel(widget.taskId);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务进度'),
        actions: [
          if (task?.isActive == true)
            TextButton(
              onPressed: _cancelling ? null : _cancel,
              child: Text(_cancelling ? '停止中' : '停止', style: const TextStyle(color: PilotColors.bad)),
            ),
        ],
      ),
      body: task == null
          ? Center(child: Text(_error ?? '加载中…', style: const TextStyle(color: PilotColors.muted)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusChip(status: task.status),
                          const SizedBox(width: 10),
                          Text('#${task.id}', style: const TextStyle(color: PilotColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(task.prompt, maxLines: 4, overflow: TextOverflow.ellipsis),
                      if (task.error != null) ...[
                        const SizedBox(height: 8),
                        Text(task.error!, style: const TextStyle(color: PilotColors.bad)),
                      ],
                    ],
                  ),
                ),
                const Divider(color: PilotColors.line, height: 1),
                Expanded(child: LogView(logs: task.logs, controller: _scroll)),
              ],
            ),
    );
  }
}

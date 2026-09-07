import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import 'task_screen.dart';

class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _prompt = TextEditingController();
  final _uploads = <RemoteUpload>[];
  bool _resume = false;
  bool _busy = false;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result == null || !mounted) return;
    final client = context.read<SessionController>().client;
    setState(() => _busy = true);
    try {
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final uploaded = await client.upload(filename: file.name, bytes: bytes);
        _uploads.add(uploaded);
      }
      setState(() {});
    } on ApiException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      _toast('先写一句任务');
      return;
    }
    final client = context.read<SessionController>().client;
    setState(() => _busy = true);
    try {
      final task = await client.createTask(
            prompt: prompt,
            uploadIds: _uploads.map((e) => e.id).toList(),
            resume: _resume,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TaskScreen(taskId: task.id)),
      );
    } on ApiException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发任务')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _prompt,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: '例如：把刚上传的 nginx 片段合并进仓库，并说明改了哪里。不要 push。',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _resume,
            onChanged: (value) => setState(() => _resume = value),
            title: const Text('接着上次会话继续'),
            subtitle: const Text('适合追问或补改，不适合全新任务'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final file in _uploads)
                Chip(
                  label: Text(file.originalName),
                  onDeleted: () => setState(() => _uploads.remove(file)),
                ),
              ActionChip(
                avatar: const Icon(Icons.attach_file, size: 18),
                label: const Text('上传文件到服务器'),
                onPressed: _busy ? null : _pickFiles,
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: Text(_busy ? '处理中…' : '交给 Agent'),
          ),
          const SizedBox(height: 12),
          const Text(
            '文件会先落到工作区的 .remote-uploads/，再作为任务上下文发给 Agent。',
            style: TextStyle(color: PilotColors.muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

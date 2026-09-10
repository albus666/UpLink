import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';

class FileEditorScreen extends StatefulWidget {
  const FileEditorScreen({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  final _content = TextEditingController();
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await context.read<SessionController>().client.readFile(widget.path);
      if (!mounted) return;
      _content.text = file.content;
      _dirty = false;
      setState(() => _loading = false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    try {
      final bytes = await context.read<SessionController>().client.downloadFile(widget.path);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, widget.name));
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: widget.name);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：$error')));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<SessionController>().client.writeFile(widget.path, _content.text);
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已写回服务器')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '下载',
            onPressed: _loading || _saving ? null : _download,
            icon: const Icon(Icons.download_outlined),
          ),
          TextButton(
            onPressed: _loading || _saving || !_dirty ? null : _save,
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: PilotColors.bad)))
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: TextField(
                    controller: _content,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    onChanged: (_) {
                      if (!_dirty) setState(() => _dirty = true);
                    },
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45),
                    decoration: const InputDecoration(
                      hintText: '文件内容',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
    );
  }
}

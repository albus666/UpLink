import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/session.dart';
import '../theme.dart';
import 'file_editor_screen.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  RemoteFsListing? _listing;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  String _path = '';

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _path = path;
    });
    try {
      final listing = await context.read<SessionController>().client.listFiles(path: path);
      if (!mounted) return;
      setState(() {
        _listing = listing;
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

  Future<void> _open(RemoteFsEntry entry) async {
    if (entry.isDir) {
      await _load(entry.path);
      return;
    }
    if (entry.text) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FileEditorScreen(path: entry.path, name: entry.name)),
      );
      return;
    }
    await _download(entry);
  }

  Future<void> _download(RemoteFsEntry entry) async {
    setState(() => _busy = true);
    try {
      final bytes = await context.read<SessionController>().client.downloadFile(entry.path);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, entry.name));
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: entry.name);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sizeLabel(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    final crumbs = listing == null || listing.path.isEmpty ? const <String>[] : listing.path.split('/');
    return Scaffold(
      appBar: AppBar(
        title: const Text('工作区文件'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: Column(
        children: [
          if (listing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                listing.root + (listing.path.isEmpty ? '' : '/${listing.path}'),
                style: const TextStyle(color: PilotColors.muted, fontSize: 12),
              ),
            ),
          if (listing != null)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  TextButton(
                    onPressed: () => _load(''),
                    child: const Text('根目录'),
                  ),
                  for (var i = 0; i < crumbs.length; i++) ...[
                    const Center(child: Icon(Icons.chevron_right, size: 16, color: PilotColors.muted)),
                    TextButton(
                      onPressed: () => _load(crumbs.sublist(0, i + 1).join('/')),
                      child: Text(crumbs[i]),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(_path),
              child: _loading
                  ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))])
                  : _error != null
                      ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: const TextStyle(color: PilotColors.bad)))])
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: (listing?.items.length ?? 0) + ((listing != null && listing.path.isNotEmpty) ? 1 : 0) + ((listing != null && listing.items.isEmpty) ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (listing != null && listing.path.isNotEmpty && index == 0) {
                              return ListTile(
                                leading: const Icon(Icons.subdirectory_arrow_left),
                                title: const Text('上级目录'),
                                onTap: () => _load(listing.parent),
                              );
                            }
                            final offset = listing != null && listing.path.isNotEmpty ? 1 : 0;
                            if (listing != null && listing.items.isEmpty && index == offset) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('这个目录是空的', style: TextStyle(color: PilotColors.muted)),
                              );
                            }
                            final item = listing!.items[index - offset];
                            return ListTile(
                              leading: Icon(
                                item.isDir ? Icons.folder_outlined : (item.text ? Icons.description_outlined : Icons.insert_drive_file_outlined),
                                color: item.isDir ? PilotColors.accent : PilotColors.muted,
                              ),
                              title: Text(item.name),
                              subtitle: Text(
                                item.isDir ? '文件夹' : '${item.text ? '文本 · ' : ''}${_sizeLabel(item.size)}',
                                style: const TextStyle(color: PilotColors.muted, fontSize: 12),
                              ),
                              trailing: item.isDir
                                  ? const Icon(Icons.chevron_right, color: PilotColors.muted)
                                  : IconButton(
                                      tooltip: '下载',
                                      onPressed: _busy ? null : () => _download(item),
                                      icon: const Icon(Icons.download_outlined),
                                    ),
                              onTap: () => _open(item),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

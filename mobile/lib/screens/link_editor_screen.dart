import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';

class LinkEditorScreen extends StatefulWidget {
  const LinkEditorScreen({super.key, this.link});

  final ServerLink? link;

  @override
  State<LinkEditorScreen> createState() => _LinkEditorScreenState();
}

class _LinkEditorScreenState extends State<LinkEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.link != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.link?.name ?? '');
    _url = TextEditingController(text: widget.link?.baseUrl ?? 'http://');
    _token = TextEditingController(text: widget.link?.token ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().saveLink(
            id: widget.link?.id,
            name: _name.text,
            url: _url.text,
            token: _token.text,
          );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = '连不上服务器：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final link = widget.link;
    if (link == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除连接'),
        content: Text('删除「${link.name}」？口令只存在这台手机上。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<SessionController>().deleteLink(link.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑连接' : '新建连接'),
        actions: [
          if (_editing)
            IconButton(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '东京 / 家里的机器',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'http://18.179.84.3:8787',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '访问口令',
              hintText: '和 APP_TOKEN 相同',
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '正在验证…' : '保存并使用'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: PilotColors.bad)),
          ],
          const SizedBox(height: 18),
          const Text(
            '会先探测登录接口。通过后只存在本机，可随时改地址或口令。',
            style: TextStyle(color: PilotColors.muted, height: 1.5, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

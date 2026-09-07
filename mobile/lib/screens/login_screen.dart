import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/session.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController(text: 'http://192.168.1.10:8787');
  final _token = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<SessionController>().login(_url.text, _token.text);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = '连不上服务器：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 36, 22, 24),
          children: [
            const Text('Uplink', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              '手机只负责发任务、传文件、看进度。\n真正改代码和跑 git 的，是 Linux 上的 Cursor Agent。',
              style: TextStyle(color: PilotColors.muted, height: 1.5),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.10:8787',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _token,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '访问口令',
                hintText: '和服务器 APP_TOKEN 相同',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '正在连接…' : '连接服务器'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: PilotColors.bad)),
            ],
            const SizedBox(height: 28),
            const Text(
              '模拟器访问本机用 http://10.0.2.2:8787\n真机请填电脑或 Linux 的局域网 IP，并保证同一 Wi-Fi。',
              style: TextStyle(color: PilotColors.muted, height: 1.5, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

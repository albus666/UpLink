import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session.dart';
import '../theme.dart';
import 'aws_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('服务器'),
            subtitle: Text(session.baseUrl, style: const TextStyle(color: PilotColors.muted)),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('登录方式'),
            subtitle: Text('共享口令（APP_TOKEN）', style: TextStyle(color: PilotColors.muted)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('AWS 服务器'),
            subtitle: const Text('用 IAM 密钥直接管 EC2 和安全组', style: TextStyle(color: PilotColors.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AwsScreen())),
          ),
          const SizedBox(height: 12),
          const Text(
            '生产环境请走 HTTPS，并尽量只在 VPN 或内网使用。系统级配置不要直接交给 Agent，用仓库里的配置文件或白名单脚本。',
            style: TextStyle(color: PilotColors.muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => session.logout(),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}

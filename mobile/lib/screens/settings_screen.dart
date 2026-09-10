import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session.dart';
import '../theme.dart';
import 'aws_screen.dart';
import 'files_screen.dart';
import 'link_editor_screen.dart';

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
          const Text('连接', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          if (session.links.isEmpty)
            const Text('还没有保存的机器。', style: TextStyle(color: PilotColors.muted)),
          for (final link in session.links)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(link.name),
              subtitle: Text(link.baseUrl, style: const TextStyle(color: PilotColors.muted, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LinkEditorScreen(link: link))),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkEditorScreen())),
              icon: const Icon(Icons.add),
              label: const Text('新建连接'),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('工作区文件'),
            subtitle: const Text('浏览、编辑文本、下载', style: TextStyle(color: PilotColors.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesScreen())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('AWS'),
            subtitle: const Text('实例、安全组、开关机', style: TextStyle(color: PilotColors.muted)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AwsScreen())),
          ),
          const SizedBox(height: 16),
          const Text(
            '口令只存在本机。外网请尽快上 HTTPS。',
            style: TextStyle(color: PilotColors.muted, height: 1.5, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

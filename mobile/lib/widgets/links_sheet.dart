import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session.dart';
import '../theme.dart';
import '../screens/link_editor_screen.dart';

Future<void> showLinksSheet(BuildContext host) {
  return showModalBottomSheet<void>(
    context: host,
    backgroundColor: PilotColors.card,
    showDragHandle: true,
    builder: (sheetContext) {
      return _LinksSheet(
        onCreate: () {
          Navigator.pop(sheetContext);
          Navigator.push(host, MaterialPageRoute(builder: (_) => const LinkEditorScreen()));
        },
        onEdit: (link) {
          Navigator.pop(sheetContext);
          Navigator.push(host, MaterialPageRoute(builder: (_) => LinkEditorScreen(link: link)));
        },
        onSelect: () => Navigator.pop(sheetContext),
      );
    },
  );
}

class _LinksSheet extends StatelessWidget {
  const _LinksSheet({
    required this.onCreate,
    required this.onEdit,
    required this.onSelect,
  });

  final VoidCallback onCreate;
  final ValueChanged<ServerLink> onEdit;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('连接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('一台手机可以记住多台机器。', style: TextStyle(color: PilotColors.muted)),
            const SizedBox(height: 12),
            if (session.links.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('还没有连接。', style: TextStyle(color: PilotColors.muted)),
              ),
            for (final link in session.links)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  session.active?.id == link.id ? Icons.radar : Icons.circle_outlined,
                  color: session.active?.id == link.id ? PilotColors.accent : PilotColors.muted,
                  size: 22,
                ),
                title: Text(link.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(link.hostLabel, style: const TextStyle(color: PilotColors.muted, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: () => onEdit(link),
                ),
                onTap: () async {
                  await session.selectLink(link.id);
                  onSelect();
                },
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('新建连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

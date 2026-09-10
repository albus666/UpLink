import 'package:flutter/material.dart';

import '../state/conversation.dart';
import '../theme.dart';
import 'follow_menu.dart';

class HistoryDrawer extends StatefulWidget {
  const HistoryDrawer({
    super.key,
    required this.threads,
    required this.currentId,
    required this.linkName,
    required this.onOpen,
    required this.onNew,
    required this.onLinks,
    required this.onSettings,
    required this.onRename,
    required this.onPin,
    required this.onDelete,
  });

  final List<ConversationThread> threads;
  final String? currentId;
  final String linkName;
  final ValueChanged<ConversationThread> onOpen;
  final VoidCallback onNew;
  final VoidCallback onLinks;
  final VoidCallback onSettings;
  final Future<void> Function(ConversationThread thread, String title) onRename;
  final Future<void> Function(ConversationThread thread, bool pinned) onPin;
  final Future<void> Function(List<String> ids) onDelete;

  @override
  HistoryDrawerState createState() => HistoryDrawerState();
}

class HistoryDrawerState extends State<HistoryDrawer> {
  final _query = TextEditingController();
  final _rename = TextEditingController();
  final _picked = <String>{};
  String? _editingId;
  bool _selecting = false;

  @override
  void dispose() {
    _query.dispose();
    _rename.dispose();
    super.dispose();
  }

  List<ConversationThread> get _visible {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.threads;
    return widget.threads.where((thread) => thread.searchText.contains(q)).toList();
  }

  List<_DrawerRow> get _rows {
    final visible = _visible;
    final rows = <_DrawerRow>[];
    final pinned = visible.where((thread) => thread.pinned).toList();
    final rest = visible.where((thread) => !thread.pinned).toList();
    if (pinned.isNotEmpty) {
      rows.add(const _DrawerRow.header('置顶'));
      for (final thread in pinned) {
        rows.add(_DrawerRow.thread(thread));
      }
    }
    String? lastLabel;
    final now = DateTime.now();
    for (final thread in rest) {
      final label = threadDateLabel(thread.updatedAt, now);
      if (label != lastLabel) {
        rows.add(_DrawerRow.header(label));
        lastLabel = label;
      }
      rows.add(_DrawerRow.thread(thread));
    }
    return rows;
  }

  void _startRename(ConversationThread thread) {
    _rename.text = thread.title;
    _rename.selection = TextSelection(baseOffset: 0, extentOffset: _rename.text.length);
    setState(() {
      _selecting = false;
      _picked.clear();
      _editingId = thread.id;
    });
  }

  Future<void> _finishRename() async {
    final id = _editingId;
    if (id == null) return;
    ConversationThread? thread;
    for (final item in widget.threads) {
      if (item.id == id) thread = item;
    }
    final next = _rename.text.trim();
    setState(() => _editingId = null);
    if (thread == null || next == thread.title) return;
    await widget.onRename(thread, next);
  }

  void _enterSelect(ConversationThread thread) {
    setState(() {
      _editingId = null;
      _selecting = true;
      _picked
        ..clear()
        ..add(thread.id);
    });
  }

  bool handleBack() {
    if (_editingId != null) {
      _finishRename();
      return true;
    }
    if (_selecting) {
      setState(() {
        _selecting = false;
        _picked.clear();
      });
      return true;
    }
    return false;
  }

  Future<void> _confirmDelete(List<String> ids) async {
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: PilotColors.surface,
        title: Text(ids.length == 1 ? '删除对话' : '删除 ${ids.length} 个对话'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: PilotColors.bad)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.onDelete(ids);
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _picked.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Drawer(
      backgroundColor: PilotColors.bg,
      width: 280,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: _fadeSlide,
                child: KeyedSubtree(
                  key: ValueKey(_selecting ? 'select' : 'search'),
                  child: _selecting ? _selectHeader() : _searchHeader(),
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('还没有对话', style: TextStyle(color: PilotColors.muted)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row.header != null) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
                            child: Text(
                              row.header!,
                              style: const TextStyle(color: PilotColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          );
                        }
                        return _threadTile(row.thread!);
                      },
                    ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: _fadeSlide,
              child: KeyedSubtree(
                key: ValueKey(_selecting ? 'delete' : 'profile'),
                child: _selecting ? _deleteBar() : _profileBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fadeSlide(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(animation),
        child: child,
      ),
    );
  }

  Widget _searchHeader() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索对话内容...',
              isDense: true,
              filled: true,
              fillColor: PilotColors.card,
              prefixIcon: const Icon(Icons.search, size: 18, color: PilotColors.muted),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        IconButton(
          tooltip: '新对话',
          onPressed: widget.onNew,
          icon: const Icon(Icons.edit_square, size: 20),
        ),
      ],
    );
  }

  Widget _deleteBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _picked.isEmpty ? null : () => _confirmDelete(_picked.toList()),
          style: FilledButton.styleFrom(backgroundColor: PilotColors.bad, foregroundColor: Colors.white),
          child: Text(_picked.isEmpty ? '删除' : '删除 ${_picked.length} 个对话'),
        ),
      ),
    );
  }

  Widget _selectHeader() {
    return Row(
      children: [
        Text('已选 ${_picked.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() {
            _selecting = false;
            _picked.clear();
          }),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _threadTile(ConversationThread thread) {
    final selected = thread.id == widget.currentId;
    final checked = _picked.contains(thread.id);
    final editing = _editingId == thread.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Builder(
        builder: (context) => Material(
          color: selected && !_selecting ? PilotColors.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (_selecting) {
                setState(() {
                  if (checked) {
                    _picked.remove(thread.id);
                  } else {
                    _picked.add(thread.id);
                  }
                });
                return;
              }
              if (editing) return;
              widget.onOpen(thread);
            },
            onLongPress: () {
              if (_selecting) return;
              _showActions(context, thread);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
              child: Row(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _selecting
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              checked ? Icons.check_circle : Icons.circle_outlined,
                              size: 18,
                              color: checked ? PilotColors.info : PilotColors.muted,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (thread.isActive)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(color: PilotColors.good, shape: BoxShape.circle),
                    ),
                  Expanded(
                    child: editing
                        ? TextField(
                            controller: _rename,
                            autofocus: true,
                            maxLength: 80,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(
                              isDense: true,
                              counterText: '',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => _finishRename(),
                            onTapOutside: (_) => _finishRename(),
                          )
                        : Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2),
                          ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: thread.pinned && !_selecting && !editing
                        ? const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.push_pin, size: 14, color: PilotColors.muted),
                          )
                        : const SizedBox.shrink(),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: !_selecting && (selected || editing)
                        ? IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                            icon: const Icon(Icons.more_horiz, size: 16, color: PilotColors.muted),
                            onPressed: () => _showActions(context, thread),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext anchor, ConversationThread thread) async {
    final action = await showFollowPopup<String>(
      context: anchor,
      width: 132,
      align: FollowAlign.end,
      gap: 8,
      builder: (dismiss) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FollowMenuTile(label: '重命名', onTap: () => dismiss('rename')),
            FollowMenuTile(label: thread.pinned ? '取消置顶' : '置顶', onTap: () => dismiss('pin')),
            FollowMenuTile(label: '多选', onTap: () => dismiss('select')),
            FollowMenuTile(
              label: '删除',
              color: PilotColors.bad,
              onTap: () => dismiss('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        _startRename(thread);
      case 'pin':
        await widget.onPin(thread, !thread.pinned);
      case 'select':
        _enterSelect(thread);
      case 'delete':
        await _confirmDelete([thread.id]);
    }
  }

  Widget _profileBar() {
    final name = widget.linkName.trim().isEmpty ? '未连接' : widget.linkName.trim();
    final letter = String.fromCharCodes(name.runes.take(1)).toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: PilotColors.card,
            child: Text(letter, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.more_horiz, size: 20, color: PilotColors.muted),
                onPressed: () async {
                  final value = await showFollowPopup<String>(
                    context: context,
                    width: 148,
                    align: FollowAlign.end,
                    gap: 8,
                    builder: (dismiss) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FollowMenuTile(label: '切换连接', onTap: () => dismiss('links')),
                          FollowMenuTile(label: '设置', onTap: () => dismiss('settings')),
                        ],
                      ),
                    ),
                  );
                  if (value == 'links') widget.onLinks();
                  if (value == 'settings') widget.onSettings();
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DrawerRow {
  const _DrawerRow.header(this.header) : thread = null;
  const _DrawerRow.thread(this.thread) : header = null;

  final String? header;
  final ConversationThread? thread;
}

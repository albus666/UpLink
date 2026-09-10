import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/conversation.dart';
import '../state/conversation_cache.dart';
import '../state/model_variant.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/chat_turn.dart';
import '../widgets/follow_menu.dart';
import '../widgets/history_drawer.dart';
import '../widgets/links_sheet.dart';
import 'aws_screen.dart';
import 'files_screen.dart';
import 'git_screen.dart';
import 'link_editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _prompt = TextEditingController();
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _drawerKey = GlobalKey<HistoryDrawerState>();
  bool _drawerOpen = false;
  final _uploads = <RemoteUpload>[];
  Timer? _timer;
  WorkspaceInfo? _workspace;
  List<ConversationThread> _threads = const [];
  ConversationThread? _current;
  String? _error;
  String? _boundId;
  String? _threadId;
  bool _wantNew = false;
  bool _loading = false;
  bool _busy = false;
  bool _online = false;
  bool _stopping = false;
  bool _hydrating = false;
  int _ticks = 0;
  final _details = <String, RemoteTask>{};

  bool get _anyActive =>
      _current?.isActive == true || _threads.any((thread) => thread.isActive);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      _ticks += 1;
      if (_anyActive) {
        _hydrateCurrent();
      }
      if (_ticks % 7 == 1) {
        _ping();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionController>();
    final id = session.active?.id;
    if (_boundId == id) return;
    _boundId = id;
    _details.clear();
    _wantNew = false;
    _threadId = session.lastThreadId;
    _reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final session = context.read<SessionController>();
    if (!session.hasLink) {
      setState(() {
        _workspace = null;
        _threads = const [];
        _current = null;
        _error = null;
        _loading = false;
        _online = false;
        _details.clear();
      });
      return;
    }

    final linkId = session.active!.id;
    final cached = await ConversationCache.load(linkId);
    if (!mounted) return;
    if (cached != null && cached.threads.isNotEmpty) {
      _details
        ..clear()
        ..addAll(cached.details);
      final localCurrent = _pickThread(cached.threads, session.lastThreadId);
      setState(() {
        _threads = cached.threads;
        _current = localCurrent;
        _threadId = localCurrent?.id;
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final client = session.client;
      final workspace = await client.workspace();
      final tasks = await client.tasks();
      var threads = groupConversations(tasks).map((thread) {
        return thread.copyWith(
          turns: [for (final turn in thread.turns) _mergeCachedTask(turn)],
        );
      }).toList();
      final alive = {for (final task in tasks) task.id};
      _details.removeWhere((id, _) => !alive.contains(id));
      if (!mounted) return;
      var current = _pickThread(threads, session.lastThreadId);
      if (current != null) {
        current = await _withLogs(client, current);
      }
      if (!mounted) return;
      threads = [
        for (final thread in threads)
          if (thread.id == current?.id) current! else thread,
      ];
      setState(() {
        _workspace = workspace;
        _threads = threads;
        _current = current;
        _threadId = current?.id;
        _loading = false;
        _online = true;
        _error = null;
      });
      _stickBottom(force: true);
      unawaited(_persistCache());
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _online = false;
        _error = _threads.isEmpty ? error.message : '服务器离线，显示本地记录';
      });
    }
  }

  RemoteTask _mergeCachedTask(RemoteTask remote) {
    final local = _details[remote.id];
    if (local == null) return remote;
    final remoteReply = (remote.resultText ?? '').trim();
    final localReply = (local.resultText ?? '').trim();
    final useLocalLogs = local.logs.isNotEmpty && remote.logs.isEmpty;
    final resultText = remoteReply.isNotEmpty ? remote.resultText : (localReply.isEmpty ? remote.resultText : local.resultText);
    if (!useLocalLogs && resultText == remote.resultText) return remote;
    return RemoteTask(
      id: remote.id,
      prompt: remote.prompt,
      status: remote.status,
      createdAt: remote.createdAt,
      startedAt: remote.startedAt,
      finishedAt: remote.finishedAt,
      sessionId: remote.sessionId ?? local.sessionId,
      resumeOf: remote.resumeOf ?? local.resumeOf,
      resultText: resultText,
      error: remote.error ?? local.error,
      mode: remote.mode,
      title: remote.title ?? local.title,
      pinned: remote.pinned,
      logs: useLocalLogs ? local.logs : remote.logs,
      logCount: useLocalLogs ? local.logs.length : remote.logCount,
    );
  }

  Future<void> _persistCache() async {
    final linkId = context.read<SessionController>().active?.id;
    if (linkId == null) return;
    await ConversationCache.save(
      linkId: linkId,
      threads: _threads,
      details: _details,
    );
  }

  ConversationThread? _pickThread(List<ConversationThread> threads, String? remembered) {
    if (_wantNew || threads.isEmpty) return null;
    if (_threadId != null) {
      for (final thread in threads) {
        if (thread.id == _threadId) return thread;
      }
    }
    if (remembered != null) {
      for (final thread in threads) {
        if (thread.id == remembered) return thread;
      }
    }
    return threads.first;
  }

  Future<ConversationThread> _withLogs(ApiClient client, ConversationThread thread) async {
    final detailed = await Future.wait(thread.turns.map((turn) async {
      final cached = _details[turn.id];
      if (cached != null && !cached.isActive && !turn.isActive && cached.logs.isNotEmpty) {
        return cached;
      }
      try {
        final full = await client.task(turn.id);
        _details[turn.id] = full;
        return full;
      } catch (_) {
        return cached ?? turn;
      }
    }));
    return thread.copyWith(turns: detailed);
  }

  Future<void> _hydrateCurrent() async {
    if (_hydrating) return;
    final session = context.read<SessionController>();
    final current = _current;
    if (!session.hasLink || current == null || current.turns.isEmpty) return;
    _hydrating = true;
    try {
      final latest = current.turns.last;
      final detailed = await session.client.task(latest.id);
      if (!mounted) return;
      final turns = [...current.turns];
      turns[turns.length - 1] = detailed;
      _details[detailed.id] = detailed;
      setState(() {
        _current = current.copyWith(turns: turns);
        _threads = [
          for (final thread in _threads)
            if (thread.id == current.id) current.copyWith(turns: turns) else thread,
        ];
      });
      _stickBottom();
      unawaited(_persistCache());
    } on ApiException {
      // keep last frame
    } finally {
      _hydrating = false;
    }
  }

  Future<void> _ping() async {
    if (!mounted) return;
    final session = context.read<SessionController>();
    if (!session.hasLink) {
      if (_online) setState(() => _online = false);
      return;
    }
    try {
      await ApiClient.ping(session.baseUrl);
      if (mounted && !_online) setState(() => _online = true);
    } catch (_) {
      if (mounted && _online) setState(() => _online = false);
    }
  }

  void _stickBottom({bool force = false}) {
    void jump() {
      if (!_scroll.hasClients) return;
      if (!force && _scroll.position.maxScrollExtent - _scroll.position.pixels > 120) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      if (force) {
        WidgetsBinding.instance.addPostFrameCallback((_) => jump());
      }
    });
  }

  Future<void> _ensureLink() async {
    if (context.read<SessionController>().hasLink) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkEditorScreen()));
  }

  Future<void> _openThread(ConversationThread thread) async {
    setState(() {
      _wantNew = false;
      _threadId = thread.id;
      _current = thread;
      _error = null;
    });
    await context.read<SessionController>().rememberThread(thread.id);
    if (!mounted) return;
    _scaffold.currentState?.closeDrawer();
    final session = context.read<SessionController>();
    if (!session.hasLink) return;
    try {
      final detailed = await _withLogs(session.client, thread);
      if (!mounted) return;
      setState(() {
        _current = detailed;
        _threads = [
          for (final item in _threads)
            if (item.id == detailed.id) detailed else item,
        ];
      });
      _stickBottom(force: true);
      unawaited(_persistCache());
    } on ApiException catch (error) {
      if (mounted) _toast(error.message);
    }
  }

  Future<void> _newChat() async {
    setState(() {
      _wantNew = true;
      _threadId = null;
      _current = null;
    });
    await context.read<SessionController>().rememberThread(null);
    _scaffold.currentState?.closeDrawer();
  }

  void _replaceThread(ConversationThread updated) {
    setState(() {
      _threads = [
        for (final item in _threads)
          if (item.id == updated.id) updated else item,
      ]..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
      if (_current?.id == updated.id) _current = updated;
    });
    unawaited(_persistCache());
  }

  Future<void> _renameThread(ConversationThread thread, String title) async {
    try {
      await context.read<SessionController>().client.patchThread(thread.id, title: title);
      if (!mounted) return;
      final cleaned = title.trim();
      _replaceThread(thread.copyWith(customTitle: cleaned, clearTitle: cleaned.isEmpty));
    } on ApiException catch (error) {
      _toast(error.message);
    }
  }

  Future<void> _pinThread(ConversationThread thread, bool pinned) async {
    try {
      await context.read<SessionController>().client.patchThread(thread.id, pinned: pinned);
      if (!mounted) return;
      _replaceThread(thread.copyWith(pinned: pinned));
    } on ApiException catch (error) {
      _toast(error.message);
    }
  }

  Future<void> _deleteThreads(List<String> ids) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      ConversationThread? thread;
      for (final item in _threads) {
        if (item.id == id) thread = item;
      }
      if (thread?.isActive == true) {
        _toast('先停止进行中的对话再删除');
        return;
      }
    }
    try {
      final client = context.read<SessionController>().client;
      for (final id in ids) {
        await client.deleteThread(id);
      }
      if (!mounted) return;
      final removing = ids.toSet();
      final currentGone = _current != null && removing.contains(_current!.id);
      setState(() {
        _threads = _threads.where((item) => !removing.contains(item.id)).toList();
        if (currentGone) {
          _current = null;
          _wantNew = true;
          _threadId = null;
        }
      });
      unawaited(_persistCache());
      if (currentGone) {
        await context.read<SessionController>().rememberThread(null);
      }
    } on ApiException catch (error) {
      _toast(error.message);
    }
  }

  Future<void> _pickFiles() async {
    await _ensureLink();
    if (!mounted || !context.read<SessionController>().hasLink) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final client = context.read<SessionController>().client;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        _uploads.add(await client.upload(filename: file.name, bytes: bytes));
      }
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    await _ensureLink();
    if (!mounted || !context.read<SessionController>().hasLink) return;
    if (_busy || _stopping) return;
    if (_anyActive) {
      _toast('上一轮还在执行，先点停止');
      return;
    }
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      _toast('先写一句');
      return;
    }
    final session = context.read<SessionController>();
    final resumeId = (!_wantNew) ? _current?.latestSessionId : null;
    setState(() => _busy = true);
    try {
      final task = await session.client.createTask(
        prompt: prompt,
        uploadIds: _uploads.map((item) => item.id).toList(),
        resume: resumeId != null,
        sessionId: resumeId,
        model: _workspace?.model,
        mode: session.chatMode,
      );
      if (!mounted) return;
      _prompt.clear();
      _uploads.clear();
      _wantNew = false;
      final thread = _current == null
          ? ConversationThread(id: task.id, turns: [task])
          : _current!.copyWith(turns: [..._current!.turns, task]);
      setState(() {
        _busy = false;
        _current = thread;
        _threadId = thread.id;
        _threads = [thread, ..._threads.where((item) => item.id != thread.id)];
      });
      _stickBottom(force: true);
      await session.rememberThread(thread.id);
      unawaited(_persistCache());
      unawaited(_hydrateCurrent());
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(error.message);
        if (error.statusCode == 409) unawaited(_reload());
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('发送失败：$error');
        unawaited(_reload());
      }
    }
  }

  Future<void> _stop() async {
    if (_stopping) return;
    final session = context.read<SessionController>();
    final seen = <String>{};
    final actives = <RemoteTask>[
      ...?_current?.turns.where((turn) => turn.isActive),
      for (final thread in _threads) ...thread.turns.where((turn) => turn.isActive),
    ].where((turn) => seen.add(turn.id)).toList();
    if (actives.isEmpty) return;
    setState(() => _stopping = true);
    try {
      for (final turn in actives) {
        await session.client.cancel(turn.id);
      }
      await _hydrateCurrent();
    } on ApiException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  Future<void> _applyVariant({String? effort, required bool fast}) async {
    final workspace = _workspace;
    if (workspace == null) return;
    final id = resolveVariantId(
      currentId: workspace.model,
      catalog: workspace.models,
      effort: effort,
      fast: fast,
    );
    if (id == null || id == workspace.model) return;
    try {
      final updated = await context.read<SessionController>().client.setModel(id);
      if (mounted) setState(() => _workspace = updated);
    } on ApiException catch (error) {
      _toast(error.message);
    }
  }

  Future<void> _pickModel(BuildContext anchor) async {
    final workspace = _workspace;
    if (workspace == null) return;
    final selected = await showFollowPopup<String>(
      context: anchor,
      width: 248,
      maxHeight: 380,
      builder: (popup) => _ModelMenu(workspace: workspace),
    );
    if (selected == null || !mounted || selected == workspace.model) return;
    try {
      final updated = await context.read<SessionController>().client.setModel(selected);
      if (mounted) setState(() => _workspace = updated);
    } on ApiException catch (error) {
      _toast(error.message);
    }
  }

  Future<void> _openAppMenu(BuildContext anchor) async {
    final link = context.read<SessionController>().active;
    final value = await showFollowPopup<String>(
      context: anchor,
      width: 132,
      builder: (popup) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FollowMenuTile(label: '连接', onTap: () => Navigator.pop(popup, 'link')),
            FollowMenuTile(label: '文件', onTap: () => Navigator.pop(popup, 'files')),
            FollowMenuTile(label: 'Git', onTap: () => Navigator.pop(popup, 'git')),
            FollowMenuTile(label: 'AWS', onTap: () => Navigator.pop(popup, 'aws')),
            FollowMenuTile(label: '设置', onTap: () => Navigator.pop(popup, 'settings')),
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    switch (value) {
      case 'files':
        if (link == null) {
          await _ensureLink();
          return;
        }
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesScreen()));
      case 'git':
        if (link == null) {
          await _ensureLink();
          return;
        }
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const GitScreen()));
        if (mounted) _reload();
      case 'aws':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const AwsScreen()));
      case 'settings':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      case 'link':
        await showLinksSheet(context);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final link = session.active;
    final title = _wantNew || _current == null ? '新对话' : _current!.title;
    return PopScope(
      canPop: !_drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_drawerKey.currentState?.handleBack() ?? false) return;
        _scaffold.currentState?.closeDrawer();
      },
      child: Scaffold(
      key: _scaffold,
      onDrawerChanged: (open) => setState(() => _drawerOpen = open),
      drawer: HistoryDrawer(
        key: _drawerKey,
        threads: _threads,
        currentId: _current?.id,
        linkName: link?.name ?? '未连接',
        onOpen: _openThread,
        onNew: _newChat,
        onLinks: () {
          _scaffold.currentState?.closeDrawer();
          showLinksSheet(context);
        },
        onSettings: () {
          _scaffold.currentState?.closeDrawer();
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
        onRename: _renameThread,
        onPin: _pinThread,
        onDelete: _deleteThreads,
      ),
      appBar: AppBar(
        backgroundColor: PilotColors.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: link == null ? kToolbarHeight : 64,
        leading: IconButton(
          tooltip: '对话列表',
          onPressed: () => _scaffold.currentState?.openDrawer(),
          icon: const Icon(CupertinoIcons.bars, size: 22),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (link != null)
              Builder(
                builder: (context) => _MachineLine(
                  online: _online,
                  host: link.hostLabel.isEmpty ? link.name : link.hostLabel,
                  model: _workspace?.displayModel ?? '模型',
                  onTap: _workspace == null ? null : () => _pickModel(context),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '新对话',
            onPressed: _newChat,
            icon: const _ThinAddIcon(),
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz, size: 22),
              onPressed: () => _openAppMenu(context),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: session.hasLink ? _reload : () async {},
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (!session.hasLink) const _EmptyLink(),
                  if (session.hasLink && _error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: PilotColors.bad)),
                    ),
                  if (session.hasLink && _current == null && !_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Text(
                        '直接在下面说话。需要看历史时点左上角。',
                        style: TextStyle(color: PilotColors.muted, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_current != null)
                    for (final turn in _current!.turns) ChatTurn(key: ValueKey(turn.id), task: turn),
                ],
              ),
            ),
          ),
          _ComposerBar(
            prompt: _prompt,
            uploads: _uploads,
            busy: _busy,
            running: _anyActive,
            stopping: _stopping,
            mode: session.chatMode,
            workspace: _workspace,
            onMode: (value) => session.setChatMode(value),
            onRemoveUpload: (item) => setState(() => _uploads.remove(item)),
            onAttach: _pickFiles,
            onSend: _send,
            onStop: _stop,
            onVariant: _applyVariant,
          ),
        ],
      ),
    ),
    );
  }
}

class _EmptyLink extends StatelessWidget {
  const _EmptyLink();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: BoxDecoration(
        color: PilotColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PilotColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('还没有连接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            '先加一台机器的地址和口令。之后打开 App 会回到上次对话。',
            style: TextStyle(color: PilotColors.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkEditorScreen())),
            child: const Text('创建连接'),
          ),
        ],
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.prompt,
    required this.uploads,
    required this.busy,
    required this.running,
    required this.stopping,
    required this.mode,
    required this.workspace,
    required this.onMode,
    required this.onRemoveUpload,
    required this.onAttach,
    required this.onSend,
    required this.onStop,
    required this.onVariant,
  });

  final TextEditingController prompt;
  final List<RemoteUpload> uploads;
  final bool busy;
  final bool running;
  final bool stopping;
  final String mode;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onMode;
  final ValueChanged<RemoteUpload> onRemoveUpload;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final Future<void> Function({String? effort, required bool fast}) onVariant;

  @override
  Widget build(BuildContext context) {
    final ask = mode == 'ask';
    final modeColor = ask ? PilotColors.good : PilotColors.accent;
    final variant = workspace == null ? null : parseModelVariant(workspace!.model, workspace!.models);
    return Material(
      color: PilotColors.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: PilotColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: PilotColors.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (uploads.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final file in uploads)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(file.originalName, style: const TextStyle(fontSize: 12)),
                            onDeleted: () => onRemoveUpload(file),
                          ),
                      ],
                    ),
                  ),
                TextField(
                  controller: prompt,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: '发消息',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  ),
                ),
                Row(
                  children: [
                    Builder(
                      builder: (context) => _ToolbarButton(
                        label: ask ? 'Ask' : 'Agent',
                        color: modeColor,
                        fill: ask ? PilotColors.goodDim : PilotColors.accentDim,
                        onTap: () => _pickMode(context, mode, onMode),
                      ),
                    ),
                    if (variant != null && (variant.canFast || variant.efforts.isNotEmpty)) ...[
                      const SizedBox(width: 6),
                      Builder(
                        builder: (context) => _ToolbarButton(
                          label: variant.label,
                          color: PilotColors.muted,
                          fill: PilotColors.card,
                          onTap: () => _pickVariant(context, variant),
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      tooltip: '附件',
                      onPressed: busy ? null : onAttach,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      icon: const Icon(Icons.attach_file, size: 20),
                      color: PilotColors.muted,
                    ),
                    running
                        ? IconButton.filled(
                            onPressed: stopping ? null : onStop,
                            style: IconButton.styleFrom(
                              backgroundColor: PilotColors.card,
                              foregroundColor: PilotColors.text,
                              minimumSize: const Size(36, 36),
                            ),
                            icon: stopping
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.stop, size: 18),
                          )
                        : IconButton.filled(
                            onPressed: busy ? null : onSend,
                            style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
                            icon: busy
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.arrow_upward, size: 18),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickMode(BuildContext context, String mode, ValueChanged<String> onMode) async {
    final picked = await showFollowPopup<String>(
      context: context,
      width: 148,
      builder: (popup) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FollowMenuTile(
              label: 'Agent',
              color: PilotColors.accent,
              selected: mode == 'agent',
              onTap: () => Navigator.pop(popup, 'agent'),
            ),
            FollowMenuTile(
              label: 'Ask',
              color: PilotColors.good,
              selected: mode == 'ask',
              onTap: () => Navigator.pop(popup, 'ask'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) onMode(picked);
  }

  Future<void> _pickVariant(BuildContext context, ModelVariant variant) async {
    await showFollowPopup<void>(
      context: context,
      width: 188,
      builder: (popup) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (variant.canFast)
              FollowMenuTile(
                label: 'Fast',
                selected: variant.fast,
                onTap: () {
                  Navigator.pop(popup);
                  onVariant(effort: variant.effort, fast: !variant.fast);
                },
              ),
            if (variant.canFast && variant.efforts.isNotEmpty)
              const Divider(height: 8, color: PilotColors.line),
            for (final effort in variant.efforts)
              FollowMenuTile(
                label: effortLabels[effort] ?? effort,
                selected: variant.effort == effort,
                onTap: () {
                  Navigator.pop(popup);
                  onVariant(effort: effort, fast: variant.fast);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.color,
    this.fill,
    this.onTap,
  });

  final String label;
  final Color color;
  final Color? fill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fill ?? color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(width: 2),
          Icon(Icons.keyboard_arrow_down, size: 16, color: color),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: child);
  }
}

class _ThinAddIcon extends StatelessWidget {
  const _ThinAddIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: PilotColors.text.withValues(alpha: 0.82), width: 1.15),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.add, size: 14),
    );
  }
}

class _MachineLine extends StatelessWidget {
  const _MachineLine({
    required this.online,
    required this.host,
    required this.model,
    required this.onTap,
  });

  final bool online;
  final String host;
  final String model;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? PilotColors.good : PilotColors.muted,
            ),
          ),
          Flexible(
            child: Text(
              host,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PilotColors.muted, fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ),
          const Text('  ·  ', style: TextStyle(color: PilotColors.muted, fontSize: 12)),
          Flexible(
            child: Text(
              model,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF8BB0FF), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down, size: 14, color: Color(0xFF8BB0FF)),
        ],
      ),
    );
  }
}

class _ModelMenu extends StatefulWidget {
  const _ModelMenu({required this.workspace});

  final WorkspaceInfo workspace;

  @override
  State<_ModelMenu> createState() => _ModelMenuState();
}

class _ModelMenuState extends State<_ModelMenu> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = widget.workspace.models.where((item) {
      if (q.isEmpty) return true;
      return item.label.toLowerCase().contains(q) || item.id.toLowerCase().contains(q);
    }).toList();
    final searchable = widget.workspace.models.length > 6;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '搜索',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 16),
                prefixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
        for (final item in items)
          FollowMenuTile(
            label: item.label,
            selected: item.id == widget.workspace.model,
            color: PilotColors.info,
            onTap: () => Navigator.pop(context, item.id),
          ),
      ],
    );
  }
}

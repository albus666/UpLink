import '../api/models.dart';

class ConversationThread {
  ConversationThread({
    required this.id,
    required this.turns,
    this.customTitle,
    this.pinned = false,
  });

  final String id;
  final List<RemoteTask> turns;
  final String? customTitle;
  final bool pinned;

  String get title {
    final custom = customTitle?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final raw = displayPrompt(turns.first.prompt);
    if (raw.isEmpty) return '新对话';
    return raw;
  }

  String get searchText {
    final parts = <String>[
      title,
      for (final turn in turns) displayPrompt(turn.prompt),
      for (final turn in turns)
        if ((turn.resultText ?? '').trim().isNotEmpty) turn.resultText!.trim(),
    ];
    return parts.join('\n').toLowerCase();
  }

  DateTime get updatedAt {
    return DateTime.tryParse(turns.last.createdAt)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String? get latestSessionId {
    for (final turn in turns.reversed) {
      final id = turn.sessionId;
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  bool get isActive => turns.any((turn) => turn.isActive);

  ConversationThread copyWith({
    List<RemoteTask>? turns,
    String? customTitle,
    bool? pinned,
    bool clearTitle = false,
  }) {
    return ConversationThread(
      id: id,
      turns: turns ?? this.turns,
      customTitle: clearTitle ? null : (customTitle ?? this.customTitle),
      pinned: pinned ?? this.pinned,
    );
  }
}

final _modeSwitchHint = RegExp(
  r'^【系统：已切换到 (Ask|Agent) 模式[^】]*】\n\n',
);

String modeSwitchHint(String mode) {
  return mode == 'ask'
      ? '【系统：用户已从 Agent 切换到 Ask 模式。本轮起只读分析，不要修改、创建、删除任何文件，不要运行会改动系统的命令。】'
      : '【系统：用户已从 Ask 切换到 Agent 模式。本轮起可以修改文件、运行命令并完成任务，不要仍按 Ask 只读方式回答。】';
}

String displayPrompt(String prompt) {
  var text = prompt.replaceFirst(_modeSwitchHint, '');
  const marker = '\n\n刚上传到工作区的文件：';
  final index = text.indexOf(marker);
  return (index >= 0 ? text.substring(0, index) : text).trim();
}

String stripAnsi(String text) {
  return text.replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '').trim();
}

List<ConversationThread> groupConversations(List<RemoteTask> tasks) {
  final bySession = <String, RemoteTask>{};
  for (final task in tasks) {
    final sessionId = task.sessionId;
    if (sessionId != null && sessionId.isNotEmpty) {
      bySession[sessionId] = task;
    }
  }

  String rootId(RemoteTask task) {
    var current = task;
    final seen = <String>{};
    while (current.resumeOf != null && current.resumeOf!.isNotEmpty) {
      if (!seen.add(current.id)) break;
      final previous = bySession[current.resumeOf!];
      if (previous == null) break;
      current = previous;
    }
    return current.id;
  }

  final buckets = <String, List<RemoteTask>>{};
  final chronological = [...tasks]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  for (final task in chronological) {
    buckets.putIfAbsent(rootId(task), () => []).add(task);
  }

  final threads = buckets.entries.map((entry) {
    final root = entry.value.firstWhere((turn) => turn.id == entry.key, orElse: () => entry.value.first);
    return ConversationThread(
      id: entry.key,
      turns: entry.value,
      customTitle: root.title,
      pinned: root.pinned,
    );
  }).toList();
  threads.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  });
  return threads;
}

String assistantReply(RemoteTask task) {
  final result = (task.resultText ?? '').trim();
  if (result.isNotEmpty) return result;
  final bits = task.logs.where((line) => line.kind == 'assistant').map((line) => stripAnsi(line.text)).where((text) => text.isNotEmpty);
  return bits.join('\n').trim();
}

List<LogLine> processLogs(RemoteTask task) {
  return task.logs.where((line) {
    if (line.kind == 'assistant' || line.kind == 'user' || line.kind == 'raw' || line.kind == 'stderr') {
      return false;
    }
    final text = stripAnsi(line.text);
    if (text.isEmpty) return false;
    if (text.startsWith('{') || text.contains('"session_id"')) return false;
    return true;
  }).toList();
}

String formatDuration(RemoteTask task) {
  final start = DateTime.tryParse(task.startedAt ?? task.createdAt)?.toLocal();
  final end = DateTime.tryParse(task.finishedAt ?? '')?.toLocal() ?? (task.isActive ? DateTime.now() : start);
  if (start == null || end == null) return '';
  final seconds = end.difference(start).inSeconds;
  if (seconds < 0) return '';
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return rest == 0 ? '$minutes 分' : '$minutes 分 $rest 秒';
}

String threadDateLabel(DateTime time, DateTime now) {
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff < 7) return '最近 7 天';
  if (diff < 30) return '最近 30 天';
  return '更早';
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/models.dart';
import '../state/conversation.dart';
import '../theme.dart';
import 'markdown_text.dart';

class ChatTurn extends StatelessWidget {
  const ChatTurn({super.key, required this.task});

  final RemoteTask task;

  @override
  Widget build(BuildContext context) {
    final process = processLogs(task);
    final reply = assistantReply(task);
    final time = _shortTime(task.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: PilotColors.userBubble,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(displayPrompt(task.prompt), style: const TextStyle(height: 1.45)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${task.mode == 'ask' ? 'Ask · ' : ''}${_statusLabel(task.status)} · $time',
              style: const TextStyle(color: PilotColors.muted, fontSize: 11),
            ),
          ),
          if (process.isNotEmpty || task.isActive) ...[
            const SizedBox(height: 12),
            ExecutionCard(task: task, logs: process),
          ],
          if (reply.isNotEmpty) ...[
            const SizedBox(height: 12),
            MarkdownText(reply),
          ],
          if (task.error != null && task.error!.trim().isNotEmpty && reply.isEmpty) ...[
            const SizedBox(height: 10),
            Text(stripAnsi(task.error!), style: const TextStyle(color: PilotColors.bad, height: 1.45)),
          ],
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'queued' => '排队中',
      'running' => '执行中',
      'succeeded' => '已完成',
      'failed' => '失败',
      'cancelled' => '已取消',
      _ => status,
    };
  }

  String _shortTime(String raw) {
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return '';
    return DateFormat('M/d HH:mm').format(parsed);
  }
}

class ExecutionCard extends StatefulWidget {
  const ExecutionCard({super.key, required this.task, required this.logs});

  final RemoteTask task;
  final List<LogLine> logs;

  @override
  State<ExecutionCard> createState() => _ExecutionCardState();
}

class _ExecutionCardState extends State<ExecutionCard> {
  late bool _open = widget.task.isActive;

  @override
  void didUpdateWidget(covariant ExecutionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.isActive && !oldWidget.task.isActive) {
      _open = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = formatDuration(widget.task);
    final running = widget.task.isActive;
    final title = running ? '正在执行' : '已思考';
    final subtitle = running
        ? (duration.isEmpty ? '进行中' : '已用时 $duration')
        : (duration.isEmpty ? '已完成' : '用时 $duration');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  running ? Icons.auto_awesome : Icons.check_circle_outline,
                  size: 16,
                  color: running ? PilotColors.accent : PilotColors.good,
                ),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '($subtitle)',
                    style: const TextStyle(color: PilotColors.muted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: PilotColors.muted),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 6),
            child: widget.logs.isEmpty
                ? Text(running ? '正在调用 Agent…' : '没有更多细节', style: const TextStyle(color: PilotColors.muted, height: 1.4))
                : Column(
                    children: [
                      for (var i = 0; i < widget.logs.length; i++)
                        _ActionLine(line: widget.logs[i], last: i == widget.logs.length - 1),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _ActionLine extends StatelessWidget {
  const _ActionLine({required this.line, required this.last});

  final LogLine line;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final look = actionLook(line);
    final text = stripAnsi(line.text);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Icon(look.icon, size: 14, color: look.color),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: PilotColors.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 10),
              child: Text(
                displayAction(text),
                style: TextStyle(color: look.color, height: 1.4, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ActionLook {
  const ActionLook(this.icon, this.color);

  final IconData icon;
  final Color color;
}

ActionLook actionLook(LogLine line) {
  final text = stripAnsi(line.text);
  if (line.kind == 'error' || line.kind == 'stderr') {
    return const ActionLook(Icons.error_outline, PilotColors.bad);
  }
  if (line.kind == 'tool') {
    if (text.contains('读取') || text.contains('列出')) {
      return const ActionLook(Icons.menu_book_outlined, PilotColors.info);
    }
    if (text.contains('写入') || text.contains('编辑') || text.contains('打补丁')) {
      return const ActionLook(Icons.edit_outlined, PilotColors.accent);
    }
    if (text.contains('删除')) {
      return const ActionLook(Icons.delete_outline, PilotColors.bad);
    }
    if (text.contains('命令')) {
      return const ActionLook(Icons.terminal, Color(0xFFC084FC));
    }
    if (text.contains('搜索') || text.contains('匹配') || text.contains('网页') || text.contains('webSearch')) {
      return const ActionLook(Icons.search, PilotColors.good);
    }
    return const ActionLook(Icons.build_outlined, PilotColors.info);
  }
  if (text.contains('启动') || text.contains('结束') || text.contains('完成') || text.contains('停止')) {
    return const ActionLook(Icons.bolt, PilotColors.info);
  }
  return const ActionLook(Icons.circle, PilotColors.muted);
}

String displayAction(String text) {
  return text
      .replaceAll('webSearchToolCall', '搜索网页')
      .replaceAll('webFetchToolCall', '打开网页');
}

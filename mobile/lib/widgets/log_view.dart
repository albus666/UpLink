import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme.dart';

class LogView extends StatelessWidget {
  const LogView({super.key, required this.logs, required this.controller});

  final List<LogLine> logs;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Text('还没有日志', style: TextStyle(color: PilotColors.muted)),
      );
    }
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final line = logs[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '[${_kindLabel(line.kind)}] ',
                  style: TextStyle(
                    color: _kindColor(line.kind),
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
                TextSpan(
                  text: line.text,
                  style: TextStyle(
                    color: line.kind == 'error' ? PilotColors.bad : PilotColors.text,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _kindLabel(String kind) {
    return switch (kind) {
      'system' => '系统',
      'assistant' => 'Agent',
      'tool' => '工具',
      'error' => '错误',
      'stderr' => '输出',
      _ => kind,
    };
  }

  Color _kindColor(String kind) {
    return switch (kind) {
      'system' => PilotColors.info,
      'assistant' => PilotColors.accent,
      'tool' => PilotColors.good,
      'error' => PilotColors.bad,
      'stderr' => PilotColors.muted,
      _ => PilotColors.muted,
    };
  }
}

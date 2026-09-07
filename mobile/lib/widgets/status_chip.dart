import 'package:flutter/material.dart';

import '../theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'queued' => ('排队中', PilotColors.muted),
      'running' => ('执行中', PilotColors.accent),
      'succeeded' => ('已完成', PilotColors.good),
      'failed' => ('失败', PilotColors.bad),
      'cancelled' => ('已取消', PilotColors.muted),
      _ => (status, PilotColors.info),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

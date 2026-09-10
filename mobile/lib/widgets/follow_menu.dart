import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

enum FollowAlign { start, end }

typedef FollowPopupBuilder<T> = Widget Function(void Function([T? result]) dismiss);

/// Anchor popup to a widget without stealing focus (keeps keyboard open).
Future<T?> showFollowPopup<T>({
  required BuildContext context,
  required FollowPopupBuilder<T> builder,
  double width = 176,
  double maxHeight = 360,
  FollowAlign align = FollowAlign.start,
  double gap = 8,
}) {
  final box = context.findRenderObject() as RenderBox?;
  final overlayState = Overlay.of(context);
  if (box == null || !box.hasSize) {
    return Future<T?>.value(null);
  }

  final media = MediaQuery.of(context);
  final keyboardInset = media.viewInsets.bottom;
  final screen = media.size;
  final origin = box.localToGlobal(Offset.zero);
  final anchorTop = origin.dy;
  final anchorBottom = origin.dy + box.size.height;
  final usableBottom = screen.height - keyboardInset;
  final spaceBelow = usableBottom - anchorBottom;
  final spaceAbove = anchorTop - media.padding.top;
  final placeBelow = spaceBelow >= 88 && spaceBelow >= spaceAbove;

  var left = align == FollowAlign.end ? origin.dx + box.size.width - width : origin.dx;
  if (left + width > screen.width - 8) left = screen.width - width - 8;
  if (left < 8) left = 8;

  final heightCap = math.min(
    maxHeight,
    (placeBelow ? spaceBelow : spaceAbove) - gap - 8,
  ).clamp(96.0, maxHeight);

  final top = placeBelow ? anchorBottom + gap : null;
  final bottom = placeBelow ? null : screen.height - anchorTop + gap;

  final completer = Completer<T?>();
  late OverlayEntry entry;

  void dismiss([T? value]) {
    if (!completer.isCompleted) completer.complete(value);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => dismiss(),
            ),
          ),
          Positioned(
            left: left,
            width: width,
            top: top,
            bottom: bottom,
            child: Material(
              color: PilotColors.card,
              elevation: 12,
              shadowColor: Colors.black54,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: PilotColors.line),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: heightCap),
                child: builder(dismiss),
              ),
            ),
          ),
        ],
      );
    },
  );

  overlayState.insert(entry);
  return completer.future;
}

class FollowMenuTile extends StatelessWidget {
  const FollowMenuTile({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.color,
    this.trailing,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? PilotColors.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? tint : (color ?? PilotColors.text),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null)
              trailing!
            else if (selected)
              Icon(Icons.check, size: 15, color: tint),
          ],
        ),
      ),
    );
  }
}

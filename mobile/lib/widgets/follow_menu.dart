import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

enum FollowAlign { start, end }

Future<T?> showFollowPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double width = 176,
  double maxHeight = 360,
  FollowAlign align = FollowAlign.start,
  double gap = 8,
}) {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null || !box.hasSize) {
    return Future<T?>.value(null);
  }

  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final screen = overlay.size;
  final media = MediaQuery.of(context);
  final usableBottom = screen.height - media.viewInsets.bottom;
  final anchorTop = origin.dy;
  final anchorBottom = origin.dy + box.size.height;
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

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dismiss',
    barrierColor: const Color(0x33000000),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, _, _) {
      return SizedBox.expand(
        child: Stack(
          children: [
            Positioned(
              left: left,
              width: width,
              top: placeBelow ? anchorBottom + gap : null,
              bottom: placeBelow ? null : screen.height - anchorTop + gap,
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
                  child: builder(dialogContext),
                ),
              ),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
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

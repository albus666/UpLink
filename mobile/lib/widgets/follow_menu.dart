import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

enum FollowAlign { start, end }

typedef FollowPopupBuilder<T> = Widget Function(void Function([T? result]) dismiss);

/// Anchor popup to a widget without stealing focus (keeps keyboard open).
/// Pass [anchorLink] when the anchor may move (e.g. composer lifts with keyboard).
Future<T?> showFollowPopup<T>({
  required BuildContext context,
  LayerLink? anchorLink,
  required FollowPopupBuilder<T> builder,
  double width = 176,
  double maxHeight = 360,
  FollowAlign align = FollowAlign.start,
  double gap = 8,
}) {
  final overlayState = Overlay.of(context);
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    return Future<T?>.value(null);
  }

  final completer = Completer<T?>();
  late OverlayEntry entry;

  void dismiss([T? value]) {
    if (!completer.isCompleted) completer.complete(value);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (overlayContext) {
      return _FollowPopupOverlay<T>(
        anchorContext: context,
        anchorLink: anchorLink,
        width: width,
        maxHeight: maxHeight,
        align: align,
        gap: gap,
        onDismiss: dismiss,
        builder: builder,
      );
    },
  );

  overlayState.insert(entry);
  return completer.future;
}

class _FollowPopupOverlay<T> extends StatelessWidget {
  const _FollowPopupOverlay({
    required this.anchorContext,
    required this.anchorLink,
    required this.width,
    required this.maxHeight,
    required this.align,
    required this.gap,
    required this.onDismiss,
    required this.builder,
  });

  final BuildContext anchorContext;
  final LayerLink? anchorLink;
  final double width;
  final double maxHeight;
  final FollowAlign align;
  final double gap;
  final void Function([T? result]) onDismiss;
  final FollowPopupBuilder<T> builder;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final keyboardInset = media.viewInsets.bottom;
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const SizedBox.shrink();
    }

    final origin = box.localToGlobal(Offset.zero);
    final anchorTop = origin.dy;
    final anchorBottom = origin.dy + box.size.height;
    final usableBottom = screen.height - keyboardInset;
    final spaceBelow = usableBottom - anchorBottom;
    final spaceAbove = anchorTop - media.padding.top;
    final placeBelow = spaceBelow >= 88 && spaceBelow >= spaceAbove;

    final heightCap = math
        .min(
          maxHeight,
          (placeBelow ? spaceBelow : spaceAbove) - gap - 8,
        )
        .clamp(96.0, maxHeight);

    final popup = Material(
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
        child: builder(onDismiss),
      ),
    );

    final backdrop = Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => onDismiss(),
      ),
    );

    if (anchorLink != null) {
      final targetAnchor = _anchorAlignment(align, placeBelow, target: true);
      final followerAnchor = _anchorAlignment(align, placeBelow, target: false);
      return Stack(
        children: [
          backdrop,
          CompositedTransformFollower(
            link: anchorLink!,
            showWhenUnlinked: false,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: Offset(0, placeBelow ? gap : -gap),
            child: SizedBox(width: width, child: popup),
          ),
        ],
      );
    }

    var left = align == FollowAlign.end ? origin.dx + box.size.width - width : origin.dx;
    if (left + width > screen.width - 8) left = screen.width - width - 8;
    if (left < 8) left = 8;

    final top = placeBelow ? anchorBottom + gap : null;
    final bottom = placeBelow ? null : screen.height - anchorTop + gap;

    return Stack(
      children: [
        backdrop,
        Positioned(
          left: left,
          width: width,
          top: top,
          bottom: bottom,
          child: popup,
        ),
      ],
    );
  }

  Alignment _anchorAlignment(FollowAlign align, bool placeBelow, {required bool target}) {
    if (placeBelow) {
      if (target) {
        return align == FollowAlign.end ? Alignment.bottomRight : Alignment.bottomLeft;
      }
      return align == FollowAlign.end ? Alignment.topRight : Alignment.topLeft;
    }
    if (target) {
      return align == FollowAlign.end ? Alignment.topRight : Alignment.topLeft;
    }
    return align == FollowAlign.end ? Alignment.bottomRight : Alignment.bottomLeft;
  }
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

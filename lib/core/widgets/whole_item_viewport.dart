import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps a fixed-extent scrolling list from exposing a clipped final row.
///
/// Snapping controls the scroll offset; this widget controls the viewport
/// height. Both are needed to guarantee that every visible item is complete.
class WholeItemViewport extends StatelessWidget {
  const WholeItemViewport({
    super.key,
    required this.itemExtent,
    required this.child,
  });

  final double itemExtent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxHeight.isFinite || constraints.maxHeight <= 0) {
          return child;
        }
        final completeItems = math.max(
          1,
          (constraints.maxHeight / itemExtent).floor(),
        );
        final viewportHeight = math.min(
          constraints.maxHeight,
          completeItems * itemExtent,
        );
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: double.infinity,
            height: viewportHeight,
            child: ClipRect(child: child),
          ),
        );
      },
    );
  }
}

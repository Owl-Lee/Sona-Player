import 'package:flutter/widgets.dart';

/// Snaps a fixed-height list to complete rows after a fling or drag.
///
/// [itemExtent] includes any separator that follows an item.
class ItemSnapScrollPhysics extends ScrollPhysics {
  const ItemSnapScrollPhysics({required this.itemExtent, super.parent});

  final double itemExtent;

  @override
  ItemSnapScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ItemSnapScrollPhysics(
      itemExtent: itemExtent,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    var row = position.pixels / itemExtent;
    if (velocity > tolerance.velocity) {
      row = row.ceilToDouble();
    } else if (velocity < -tolerance.velocity) {
      row = row.floorToDouble();
    } else {
      row = row.roundToDouble();
    }
    final target = (row * itemExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

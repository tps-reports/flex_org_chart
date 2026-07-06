import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../model/chart_state.dart';
import 'path_builder.dart';

/// Visual style for the parent-child connector lines drawn by [EdgePainter].
class LinkStyle {
  const LinkStyle({this.color = const Color(0xFFCCCCCC), this.width = 1.5});
  final Color color;
  final double width;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkStyle &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          width == other.width;

  @override
  int get hashCode => Object.hash(color, width);
}

/// Paints every [LinkLayout] in [links] as a stroked path, translated by
/// [origin] so the chart's layout-space bounds line up with the widget's
/// (0,0)-origin canvas. Links whose child id is in [highlightedChildIds]
/// are painted with [highlightedStyle] in a second pass.
class EdgePainter extends CustomPainter {
  EdgePainter({
    required this.links,
    required this.style,
    required this.origin,
    this.highlightedChildIds = const {},
    this.highlightedStyle = const LinkStyle(),
  });

  final List<LinkLayout> links;
  final LinkStyle style;
  final Offset origin;
  final Set<String> highlightedChildIds;
  final LinkStyle highlightedStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(origin.dx, origin.dy);

    // Paint regular links first
    for (final link in links) {
      if (!highlightedChildIds.contains(link.childId)) {
        canvas.drawPath(buildPath(link.commands), paint);
      }
    }

    // Paint highlighted links second (on top)
    if (highlightedChildIds.isNotEmpty) {
      final highlightedPaint = Paint()
        ..color = highlightedStyle.color
        ..strokeWidth = highlightedStyle.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (final link in links) {
        if (highlightedChildIds.contains(link.childId)) {
          canvas.drawPath(buildPath(link.commands), highlightedPaint);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(EdgePainter oldDelegate) =>
      !identical(oldDelegate.links, links) ||
      oldDelegate.style != style ||
      oldDelegate.origin != origin ||
      !setEquals(oldDelegate.highlightedChildIds, highlightedChildIds) ||
      oldDelegate.highlightedStyle != highlightedStyle;
}

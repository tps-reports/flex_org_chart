import 'package:flutter/widgets.dart';

import '../model/chart_state.dart';
import 'path_builder.dart';

/// Visual style for the parent-child connector lines drawn by [EdgePainter].
class LinkStyle {
  const LinkStyle({this.color = const Color(0xFFCCCCCC), this.width = 1.5});
  final Color color;
  final double width;
}

/// Paints every [LinkLayout] in [links] as a stroked path, translated by
/// [origin] so the chart's layout-space bounds line up with the widget's
/// (0,0)-origin canvas.
class EdgePainter extends CustomPainter {
  EdgePainter({
    required this.links,
    required this.style,
    required this.origin,
  });

  final List<LinkLayout> links;
  final LinkStyle style;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    for (final link in links) {
      canvas.drawPath(buildPath(link.commands), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(EdgePainter oldDelegate) =>
      !identical(oldDelegate.links, links) ||
      oldDelegate.style != style ||
      oldDelegate.origin != origin;
}

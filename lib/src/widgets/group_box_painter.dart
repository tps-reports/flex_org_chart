import 'package:flutter/widgets.dart';

import '../model/chart_group.dart';
import '../model/geometry.dart';
import 'group_hulls.dart';
import 'path_builder.dart';

/// Paints department bounding boxes — one rounded, optionally dashed,
/// labeled box per [GroupHull] — beneath the chart's links and nodes.
/// [hulls] arrive sorted outer-first (see [computeGroupHulls]), so nested
/// boxes naturally paint inner-on-top-of-outer.
///
/// Uses the same [origin] translation convention as `EdgePainter` and
/// `ConnectionPainter`: hull rects come in raw layout-bounds space and are
/// shifted here onto the widget's (0,0)-origin canvas.
class GroupBoxPainter extends CustomPainter {
  /// Creates a painter for [hulls], each resolved against [defaultStyle]
  /// unless it declares its own override, translated onto the canvas by
  /// [origin].
  GroupBoxPainter({
    required this.hulls,
    required this.defaultStyle,
    required this.origin,
  });

  /// The resolved hulls to paint, outer-first.
  final List<GroupHull> hulls;

  /// Style used for any hull whose group has no [ChartGroup.style] override.
  final GroupBoxStyle defaultStyle;

  /// Canvas translation applied before painting, matching `EdgePainter` and
  /// `ConnectionPainter`.
  final Offset origin;

  /// The effective style for [hull]: its group's override or [defaultStyle].
  @visibleForTesting
  GroupBoxStyle styleFor(GroupHull hull) => hull.group.style ?? defaultStyle;

  /// Label inset from the hull's top-left corner.
  static const _labelInset = Offset(10, 6);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    for (final hull in hulls) {
      final style = styleFor(hull);
      final r = hull.rect;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left, r.top, r.width, r.height),
        Radius.circular(style.borderRadius),
      );
      canvas.drawRRect(rrect, Paint()..color = style.fill);
      final border = Paint()
        ..color = style.borderColor
        ..strokeWidth = style.borderWidth
        ..style = PaintingStyle.stroke;
      final dash = style.dash;
      if (dash == null) {
        canvas.drawRRect(rrect, border);
      } else {
        // Invalid patterns fall back to the source path (solid) inside
        // dashedPath — same contract as ConnectionStyle.dash.
        canvas.drawPath(dashedPath(Path()..addRRect(rrect), dash), border);
      }
      final label = hull.group.label;
      if (label != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style:
                style.labelStyle ??
                TextStyle(color: style.borderColor, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(r.left + _labelInset.dx, r.top + _labelInset.dy),
        );
        tp.dispose();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GroupBoxPainter oldDelegate) {
    if (oldDelegate.defaultStyle != defaultStyle ||
        oldDelegate.origin != origin) {
      return true;
    }
    final a = oldDelegate.hulls;
    final b = hulls;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      // Group instances are stable across rebuilds (the controller never
      // recreates its ChartGroup list entries), so identity is a cheap,
      // correct proxy — same reasoning as ConnectionPainter.shouldRepaint.
      if (!identical(a[i].group, b[i].group) ||
          !_rectEquals(a[i].rect, b[i].rect)) {
        return true;
      }
    }
    return false;
  }
}

bool _rectEquals(LayoutRect x, LayoutRect y) =>
    x.left == y.left &&
    x.top == y.top &&
    x.width == y.width &&
    x.height == y.height;

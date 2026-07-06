import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../model/chart_state.dart';
import '../model/connection.dart';
import '../model/geometry.dart';

/// Visual style for the [ConnectionPainter] overlay: dashed arcs drawn
/// between arbitrary (non-hierarchical) node pairs declared via
/// [Connection], independent of the parent/child tree painted by
/// [EdgePainter].
class ConnectionStyle {
  const ConnectionStyle({
    this.color = const Color(0xFFE27396),
    this.width = 3,
    this.dash = const [7, 7],
    this.labelStyle,
  });
  final Color color;
  final double width;

  /// On/off segment lengths of the dash pattern, in logical pixels.
  /// Entries must be positive; a pattern that is empty or contains a
  /// zero/negative entry cannot be validated here (const constructor) and
  /// falls back to a solid line at paint time instead of dashing.
  final List<double> dash;
  final TextStyle? labelStyle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionStyle &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          width == other.width &&
          _listEquals(dash, other.dash) &&
          labelStyle == other.labelStyle;

  @override
  int get hashCode => Object.hash(color, width, Object.hashAll(dash), labelStyle);
}

bool _listEquals(List<double> a, List<double> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A [Connection] resolved against a [ChartState]: both endpoints are
/// currently visible (present in [ChartState.byId]), with their laid-out
/// [LayoutRect]s attached so [ConnectionPainter] doesn't need to look them
/// up again during paint.
class VisibleConnection {
  VisibleConnection(this.connection, this.source, this.target);
  final Connection connection;
  final LayoutRect source;
  final LayoutRect target;
}

/// Paints dashed, labeled, arrow-headed arcs between arbitrary visible node
/// pairs declared via [OrgChartController.connections] — independent of the
/// hierarchical parent/child links [EdgePainter] draws. Connections whose
/// `from` or `to` node is currently hidden (collapsed ancestor, etc.) are
/// silently dropped; see [visibleConnections].
///
/// Uses the same [origin] translation convention as [EdgePainter]: rects
/// come in raw layout-bounds space and are shifted here so they land on the
/// widget's (0,0)-origin canvas.
class ConnectionPainter extends CustomPainter {
  ConnectionPainter({
    required List<Connection> connections,
    required ChartState state,
    required this.style,
    required this.origin,
  }) : visibleConnections = [
          for (final c in connections)
            if (state.byId(c.from) != null && state.byId(c.to) != null)
              VisibleConnection(
                  c, state.byId(c.from)!.rect, state.byId(c.to)!.rect),
        ];

  final List<VisibleConnection> visibleConnections;
  final ConnectionStyle style;
  final Offset origin;

  /// Rebuilds [source] as a dashed path: walks each contour's metrics and
  /// alternately keeps/drops [style.dash]-length segments. A contour with
  /// zero length (degenerate/coincident endpoints) contributes nothing —
  /// `metric.length == 0` short-circuits the `while (d < metric.length)`
  /// loop immediately, so this never spins or divides by zero.
  ///
  /// Invalid dash patterns ([ConnectionStyle.dash] empty, or containing a
  /// zero/negative entry) fall back to returning [source] unchanged — a
  /// solid line. ConnectionStyle's const constructor can't validate, and
  /// without this guard a zero entry makes `d += len` a no-op so the loop
  /// below never terminates, hanging the render thread on first paint
  /// (regression tests: 'invalid dash patterns' group in
  /// connections_test.dart).
  @visibleForTesting
  Path dashPath(Path source) {
    if (style.dash.isEmpty || style.dash.any((len) => len <= 0)) {
      return source;
    }
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var d = 0.0;
      var draw = true;
      var i = 0;
      while (d < metric.length) {
        final len = style.dash[i % style.dash.length];
        final end = math.min(d + len, metric.length);
        if (draw) out.addPath(metric.extractPath(d, end), Offset.zero);
        d += len;
        draw = !draw;
        i++;
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = style.width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    for (final v in visibleConnections) {
      final s = Offset(v.source.centerX, v.source.centerY);
      final t = Offset(v.target.centerX, v.target.centerY);
      final mid = Offset((s.dx + t.dx) / 2, (s.dy + t.dy) / 2);
      final arc = Path()
        ..moveTo(s.dx, s.dy)
        ..cubicTo(mid.dx, s.dy, mid.dx, t.dy, t.dx, t.dy);
      canvas.drawPath(dashPath(arc), paint);
      _arrowHead(canvas, arc, paint);
      final label = v.connection.label;
      if (label != null) {
        final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: style.labelStyle ??
                  TextStyle(color: style.color, fontSize: 11)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(s.dx, s.dy - tp.height - 4));
        tp.dispose();
      }
    }
    canvas.restore();
  }

  /// Draws a simple two-barb arrowhead at the end of [arc], pointing back
  /// along the path's end tangent. Each barb is ~10px long, splayed ±30°
  /// off the reversed tangent direction (i.e. off the direction *back*
  /// toward the source), so the two barbs form a "<" shape opening toward
  /// the incoming line — the conventional arrow look.
  ///
  /// If the path has no metrics (shouldn't happen: `arc` always has a
  /// moveTo+cubicTo) or the end tangent can't be resolved (only for a
  /// zero-length path), this is a no-op rather than throwing — an arrow
  /// isn't worth crashing the whole paint pass over.
  void _arrowHead(Canvas canvas, Path arc, Paint base) {
    final metrics = arc.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final m = metrics.last;
    final tan = m.getTangentForOffset(m.length);
    if (tan == null) return;
    final tip = tan.position;
    // Angle of the direction pointing back from the tip toward the source,
    // i.e. the reverse of the path's forward tangent at its end.
    final backAngle = math.atan2(-tan.vector.dy, -tan.vector.dx);
    const barbLength = 10.0;
    const barbSpread = 30 * math.pi / 180;
    Offset barb(double deltaAngle) {
      final a = backAngle + deltaAngle;
      return Offset(
          tip.dx + barbLength * math.cos(a), tip.dy + barbLength * math.sin(a));
    }

    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(barb(-barbSpread).dx, barb(-barbSpread).dy)
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(barb(barbSpread).dx, barb(barbSpread).dy);
    canvas.drawPath(head, base);
  }

  @override
  bool shouldRepaint(ConnectionPainter oldDelegate) {
    if (oldDelegate.style != style || oldDelegate.origin != origin) {
      return true;
    }
    final a = oldDelegate.visibleConnections;
    final b = visibleConnections;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      // `connection` instances are stable across rebuilds (the controller
      // never mutates or recreates its `Connection` list entries), so
      // `identical` is a cheap, correct proxy for "same declared
      // connection" here; only the resolved rects can actually change
      // frame to frame (nodes moving/entering/leaving).
      if (!identical(a[i].connection, b[i].connection) ||
          !_rectEquals(a[i].source, b[i].source) ||
          !_rectEquals(a[i].target, b[i].target)) {
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

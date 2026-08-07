import 'dart:math' as math;
import 'dart:ui';

import '../layout/link_geometry.dart';

/// Converts the layout layer's [PathCommand] list into a `dart:ui` [Path]
/// suitable for [Canvas.drawPath]. Kept in the widgets layer (not layout)
/// because it is the first point at which we touch `dart:ui`.
Path buildPath(List<PathCommand> commands) {
  final path = Path();
  for (final c in commands) {
    switch (c) {
      case MoveTo(:final x, :final y):
        path.moveTo(x, y);
      case LineTo(:final x, :final y):
        path.lineTo(x, y);
      case CubicTo(
        :final x1,
        :final y1,
        :final x2,
        :final y2,
        :final x,
        :final y,
      ):
        path.cubicTo(x1, y1, x2, y2, x, y);
    }
  }
  return path;
}

/// Rebuilds [source] as a dashed path: walks each contour's metrics and
/// alternately keeps/drops [dash]-length segments. A contour with zero
/// length contributes nothing — `metric.length == 0` short-circuits the
/// walk immediately, so this never spins or divides by zero.
///
/// Invalid dash patterns ([dash] empty, or containing a zero/negative
/// entry) return [source] unchanged — a solid line. Style constructors
/// are const and cannot validate; without this guard a zero entry makes
/// the walk a no-op that never terminates, hanging the render thread on
/// first paint (regression tests: 'invalid dash patterns' in
/// connections_test.dart, 'dashedPath' in group_boxes_test.dart).
Path dashedPath(Path source, List<double> dash) {
  if (dash.isEmpty || dash.any((len) => len <= 0)) {
    return source;
  }
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    var draw = true;
    var i = 0;
    while (d < metric.length) {
      final len = dash[i % dash.length];
      final end = math.min(d + len, metric.length);
      if (draw) out.addPath(metric.extractPath(d, end), Offset.zero);
      d += len;
      draw = !draw;
      i++;
    }
  }
  return out;
}

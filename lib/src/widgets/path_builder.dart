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
          :final y
        ):
        path.cubicTo(x1, y1, x2, y2, x, y);
    }
  }
  return path;
}

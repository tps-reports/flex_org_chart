import '../model/geometry.dart';

/// A single SVG-style path command, emitted by [verticalDiagonal] and
/// [horizontalDiagonal] instead of being serialized to a `d` attribute
/// string (as the original d3-org-chart JS does).
sealed class PathCommand {
  const PathCommand();
}

class MoveTo extends PathCommand {
  const MoveTo(this.x, this.y);
  final double x, y;
  @override
  bool operator ==(Object other) =>
      other is MoveTo && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash('M', x, y);
  @override
  String toString() => 'MoveTo($x, $y)';
}

class LineTo extends PathCommand {
  const LineTo(this.x, this.y);
  final double x, y;
  @override
  bool operator ==(Object other) =>
      other is LineTo && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash('L', x, y);
  @override
  String toString() => 'LineTo($x, $y)';
}

class CubicTo extends PathCommand {
  const CubicTo(this.x1, this.y1, this.x2, this.y2, this.x, this.y);
  final double x1, y1, x2, y2, x, y;
  @override
  bool operator ==(Object other) =>
      other is CubicTo &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2 &&
      other.x == x &&
      other.y == y;
  @override
  int get hashCode => Object.hash('C', x1, y1, x2, y2, x, y);
  @override
  String toString() => 'CubicTo($x1,$y1 $x2,$y2 $x,$y)';
}

/// Port of d3-org-chart `diagonal` (REF src/d3-org-chart.js:225-262).
///
/// Generates the curved-edge path commands for a vertical (top-to-bottom)
/// org chart orientation, connecting a source point [s] (child) to a
/// target point [t] (parent), optionally routed through a via-point [m]
/// and offset vertically by [sy].
List<PathCommand> verticalDiagonal({
  required Pt s,
  required Pt t,
  Pt? m,
  double sy = 0,
}) {
  final x = s.x;
  var y = s.y;
  final ex = t.x;
  final ey = t.y;
  final mx = m?.x ?? x;
  final my = m?.y ?? y;
  final xrvs = ex - x < 0 ? -1.0 : 1.0;
  final yrvs = ey - y < 0 ? -1.0 : 1.0;
  y += sy;
  const rdef = 35.0;
  var r = (ex - x).abs() / 2 < rdef ? (ex - x).abs() / 2 : rdef;
  r = (ey - y).abs() / 2 < r ? (ey - y).abs() / 2 : r;
  final h = (ey - y).abs() / 2 - r;
  final w = (ex - x).abs() - r * 2;
  return [
    MoveTo(mx, my),
    LineTo(x, my),
    LineTo(x, y),
    LineTo(x, y + h * yrvs),
    CubicTo(x, y + h * yrvs + r * yrvs, x, y + h * yrvs + r * yrvs,
        x + r * xrvs, y + h * yrvs + r * yrvs),
    LineTo(x + w * xrvs + r * xrvs, y + h * yrvs + r * yrvs),
    CubicTo(ex, y + h * yrvs + r * yrvs, ex, y + h * yrvs + r * yrvs, ex,
        ey - h * yrvs),
    LineTo(ex, ey),
  ];
}

/// Port of d3-org-chart `hdiagonal` (REF src/d3-org-chart.js:181-223).
///
/// Generates the curved-edge path commands for a horizontal (left-to-right)
/// org chart orientation, connecting a source point [s] (child) to a
/// target point [t] (parent), optionally routed through a via-point [m].
List<PathCommand> horizontalDiagonal({required Pt s, required Pt t, Pt? m}) {
  final x = s.x;
  final y = s.y;
  final ex = t.x;
  final ey = t.y;
  final mx = m?.x ?? x;
  final my = m?.y ?? y;
  final xrvs = ex - x < 0 ? -1.0 : 1.0;
  final yrvs = ey - y < 0 ? -1.0 : 1.0;
  const rdef = 35.0;
  var r = (ex - x).abs() / 2 < rdef ? (ex - x).abs() / 2 : rdef;
  r = (ey - y).abs() / 2 < r ? (ey - y).abs() / 2 : r;
  final w = (ex - x).abs() / 2 - r;
  return [
    MoveTo(mx, my),
    LineTo(mx, y),
    LineTo(x, y),
    LineTo(x + w * xrvs, y),
    CubicTo(x + w * xrvs + r * xrvs, y, x + w * xrvs + r * xrvs, y,
        x + w * xrvs + r * xrvs, y + r * yrvs),
    LineTo(x + w * xrvs + r * xrvs, ey - r * yrvs),
    CubicTo(x + w * xrvs + r * xrvs, ey, x + w * xrvs + r * xrvs, ey,
        ex - w * xrvs, ey),
    LineTo(ex, ey),
  ];
}

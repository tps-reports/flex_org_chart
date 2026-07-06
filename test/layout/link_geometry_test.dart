import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/src/layout/link_geometry.dart';

void main() {
  test('verticalDiagonal, child directly below parent', () {
    // s=(0,300) child top-center joins t=(0,150) parent bottom.
    // JS diagonal with these inputs: r = min(35, |ex-x|/2=0, ...) = 0,
    // so the path degenerates to straight segments.
    final cmds = verticalDiagonal(s: (x: 0, y: 300), t: (x: 0, y: 150));
    expect(cmds.first, const MoveTo(0, 300));
    expect(cmds.last, const LineTo(0, 150));
    // no curvature when horizontally aligned:
    expect(cmds.whereType<CubicTo>().every((c) => c.x1 == 0 && c.x2 == 0),
        isTrue);
  });

  test('verticalDiagonal, offset child produces symmetric S-curve', () {
    final cmds = verticalDiagonal(s: (x: 200, y: 300), t: (x: 0, y: 150));
    // r = min(35, |ex-x|/2=100, |ey-y|/2=75) = 35
    // h = |ey-y|/2 - r = 40; w = |ex-x| - 2r = 130; xrvs=-1, yrvs=-1
    expect(cmds, const [
      MoveTo(200, 300),
      LineTo(200, 300),
      LineTo(200, 300),
      LineTo(200, 260), // y + h*yrvs = 300 - 40
      CubicTo(200, 225, 200, 225, 165, 225), // y+h*yrvs+r*yrvs=225; x+r*xrvs=165
      LineTo(35, 225), // x + w*xrvs + r*xrvs = 200 -130 -35
      CubicTo(0, 225, 0, 225, 0, 190), // ex; ey - h*yrvs = 150 + 40
      LineTo(0, 150),
    ]);
  });

  test('horizontalDiagonal endpoints', () {
    final cmds = horizontalDiagonal(s: (x: 0, y: 0), t: (x: 300, y: 200));
    expect(cmds.first, const MoveTo(0, 0));
    expect(cmds.last, const LineTo(300, 200));
  });
}

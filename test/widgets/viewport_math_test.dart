import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/viewport_math.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('fitTransform scales bounds to fit viewport with padding', () {
    final m = fitTransform(
        bounds: const LayoutRect(0, 0, 2000, 1000),
        viewport: const Size(500, 500),
        padding: 50);
    final scale = m.getMaxScaleOnAxis();
    expect(scale, closeTo(400 / 2000, 1e-9)); // limited by width
    // bounds center maps to viewport center
    final v = m.transform3(Vector3(1000, 500, 0));
    expect(v.x, closeTo(250, 1e-6));
    expect(v.y, closeTo(250, 1e-6));
  });

  test('fitTransform clamps to maxScale for tiny content', () {
    final m = fitTransform(
        bounds: const LayoutRect(0, 0, 1, 1),
        viewport: const Size(500, 500),
        maxScale: 20);
    expect(m.getMaxScaleOnAxis(), closeTo(20, 1e-9));
  });

  test('centerTransform maps rect center to viewport center at given scale',
      () {
    final m = centerTransform(
        rect: const LayoutRect(100, 200, 50, 50),
        viewport: const Size(800, 600),
        scale: 2);
    final v = m.transform3(Vector3(125, 225, 0));
    expect(v.x, closeTo(400, 1e-6));
    expect(v.y, closeTo(300, 1e-6));
  });
}

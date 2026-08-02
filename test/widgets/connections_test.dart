import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/connection_painter.dart';

typedef Row = ({String id, String? parentId});

/// A minimal two-node [ChartState] with one connection a→b, for exercising
/// [ConnectionPainter] directly (no widget tree needed).
ConnectionPainter _twoNodePainter({required ConnectionStyle style}) {
  final a = OrgNode<int>.internal(id: 'a', data: 0);
  final b = OrgNode<int>.internal(id: 'b', data: 1);
  final state = ChartState<int>(
    nodes: [
      NodeLayout(a, const LayoutRect(0, 0, 100, 50)),
      NodeLayout(b, const LayoutRect(200, 200, 100, 50)),
    ],
    links: const [],
    bounds: const LayoutRect(0, 0, 300, 250),
  );
  return ConnectionPainter(
    connections: const [Connection(from: 'a', to: 'b')],
    state: state,
    style: style,
    origin: Offset.zero,
  );
}

Path _line() => Path()
  ..moveTo(0, 0)
  ..lineTo(100, 0);

double _totalLength(Path p) =>
    p.computeMetrics().fold(0.0, (sum, m) => sum + m.length);

void main() {
  testWidgets('paints only connections whose endpoints are both visible', (
    tester,
  ) async {
    final c = OrgChartController<Row>(
      data: const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'b'),
      ],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
      connections: const [
        Connection(from: 'a', to: 'b', label: 'works with'),
        Connection(from: 'a', to: 'c'), // c hidden at initialExpandLevel 1
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OrgChart<Row>(
          controller: c,
          compact: false,
          nodeBuilder: (_, n) => Text('node-${n.id}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is ConnectionPainter,
                  ),
                )
                .painter
            as ConnectionPainter;
    expect(painter.visibleConnections.map((v) => v.connection.to), ['b']);
  });

  group('invalid dash patterns (regression: render-thread hang)', () {
    // Before the guard in dashPath, `dash: [0, 0]` made the dash loop's
    // `d += len` a no-op — `while (d < metric.length)` never terminated and
    // the first paint hung the render thread forever. These tests execute
    // that exact code path directly; with the guard they must complete
    // (falling back to a solid, undashed line) instead of hanging/throwing.

    test('dash [0, 0] falls back to a solid line instead of hanging', () {
      final painter = _twoNodePainter(
        style: const ConnectionStyle(dash: [0, 0]),
      );
      final result = painter.dashPath(_line());
      // Solid fallback: the output covers the full source length (a real
      // dashed output would cover roughly half of it for a 50/50 pattern).
      expect(_totalLength(result), moreOrLessEquals(100.0, epsilon: 0.01));
    });

    test('negative dash entry falls back to a solid line', () {
      final painter = _twoNodePainter(
        style: const ConnectionStyle(dash: [7, -7]),
      );
      final result = painter.dashPath(_line());
      expect(_totalLength(result), moreOrLessEquals(100.0, epsilon: 0.01));
    });

    test('empty dash list does not throw and falls back to a solid line', () {
      final painter = _twoNodePainter(style: const ConnectionStyle(dash: []));
      // Pre-guard this threw UnsupportedError (`i % style.dash.length` with
      // length 0). Post-guard: solid line, no exception.
      final result = painter.dashPath(_line());
      expect(_totalLength(result), moreOrLessEquals(100.0, epsilon: 0.01));
    });

    test('a valid dash pattern still actually dashes', () {
      final painter = _twoNodePainter(
        style: const ConnectionStyle(dash: [7, 7]),
      );
      final result = painter.dashPath(_line());
      final len = _totalLength(result);
      // A 7-on/7-off pattern over a 100px line keeps roughly half of it —
      // strictly less than solid, strictly more than nothing.
      expect(len, greaterThan(0));
      expect(len, lessThan(100));
    });

    test('full paint with dash [0, 0] completes on a real canvas', () {
      final painter = _twoNodePainter(
        style: const ConnectionStyle(dash: [0, 0]),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      // This is the exact call that previously never returned.
      painter.paint(canvas, const Size(300, 250));
      recorder.endRecording().dispose();
    });
  });
}

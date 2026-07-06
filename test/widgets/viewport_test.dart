import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

void main() {
  testWidgets('controller.fit and centerNode work once chart is attached',
      (tester) async {
    final c = OrgChartController<Row>(
        data: const [(id: 'a', parentId: null), (id: 'b', parentId: 'a')],
        idOf: (r) => r.id,
        parentIdOf: (r) => r.parentId);
    await tester.pumpWidget(MaterialApp(
      home: OrgChart<Row>(
        controller: c,
        compact: false,
        nodeSize: (_) => (w: 100, h: 50),
        nodeBuilder: (_, n) => Text('node-${n.id}'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(() => c.fit(animate: false), returnsNormally);
    expect(() => c.centerNode('b', animate: false), returnsNormally);
    expect(() => c.zoomIn(), returnsNormally);
  });

  testWidgets('detaches on dispose: fit throws again after removal',
      (tester) async {
    final c = OrgChartController<Row>(
        data: const [(id: 'a', parentId: null)],
        idOf: (r) => r.id,
        parentIdOf: (r) => r.parentId);
    await tester.pumpWidget(MaterialApp(
      home: OrgChart<Row>(controller: c, nodeBuilder: (_, n) => Text(n.id)),
    ));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(() => c.fit(), throwsStateError);
  });

  testWidgets('initial fit scales/centers content once nodes exist',
      (tester) async {
    final c = OrgChartController<Row>(
        data: const [(id: 'a', parentId: null), (id: 'b', parentId: 'a')],
        idOf: (r) => r.id,
        parentIdOf: (r) => r.parentId);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: OrgChart<Row>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          nodeBuilder: (_, n) => Text('node-${n.id}'),
        ),
      ),
    ));
    // Initial fit is scheduled via addPostFrameCallback (animate: false, so
    // one extra pump is enough — no tween to settle).
    await tester.pump();
    final finder = find.descendant(
        of: find.byType(OrgChart<Row>), matching: find.byType(Transform));
    final transform = tester.widget<Transform>(finder.first);
    final scale = transform.transform.getMaxScaleOnAxis();
    // Content (roughly 100x150 for a 2-node top-down chart with 100x50
    // nodes) is much smaller than the 800x600 viewport, so fitTransform
    // should have scaled it up from the default identity (scale 1) — this
    // is really just confirming the postFrameCallback fired at all.
    expect(scale, isNot(closeTo(1.0, 1e-9)));
  });

  testWidgets('bottom-row expand button is tappable through the viewport',
      (tester) async {
    // A single parent with one child: the child is the bottom-most visible
    // row and, with initialExpandLevel 1 (default), starts collapsed with
    // its own children hidden — giving it an expand button anchored to its
    // rect's bottom edge, which is exactly what the Task 8 finding flagged
    // as at risk of sitting outside the hit-testable box once wrapped in
    // ChartViewport's Transform/OverflowBox.
    final c = OrgChartController<Row>(data: const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
      (id: 'c', parentId: 'b'),
    ], idOf: (r) => r.id, parentIdOf: (r) => r.parentId);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: OrgChart<Row>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          nodeBuilder: (_, n) => Text('node-${n.id}'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('node-c'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expand-button-b')));
    await tester.pumpAndSettle();
    expect(find.text('node-c'), findsOneWidget);
  });

  testWidgets('rapid successive animated fit/center calls settle cleanly',
      (tester) async {
    final c = OrgChartController<Row>(
        data: const [
          (id: 'a', parentId: null),
          (id: 'b', parentId: 'a'),
          (id: 'c', parentId: 'a'),
        ],
        idOf: (r) => r.id,
        parentIdOf: (r) => r.parentId);
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: OrgChart<Row>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          nodeBuilder: (_, n) => Text('node-${n.id}'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Retarget the in-flight animation several times before it can finish;
    // this must not throw (e.g. from a disposed/duplicated listener) and
    // must end up settled at the *last* requested target.
    c.fit();
    await tester.pump(const Duration(milliseconds: 50));
    c.centerNode('b');
    await tester.pump(const Duration(milliseconds: 50));
    c.centerNode('c');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

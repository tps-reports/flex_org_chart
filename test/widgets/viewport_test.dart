import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/chart_viewport.dart';

typedef Row = ({String id, String? parentId});

void main() {
  testWidgets('controller.fit and centerNode work once chart is attached', (
    tester,
  ) async {
    final c = OrgChartController<Row>(
      data: const [(id: 'a', parentId: null), (id: 'b', parentId: 'a')],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OrgChart<Row>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          nodeBuilder: (_, n) => Text('node-${n.id}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(() => c.fit(animate: false), returnsNormally);
    expect(() => c.centerNode('b', animate: false), returnsNormally);
    expect(() => c.zoomIn(), returnsNormally);
  });

  testWidgets('detaches on dispose: fit throws again after removal', (
    tester,
  ) async {
    final c = OrgChartController<Row>(
      data: const [(id: 'a', parentId: null)],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OrgChart<Row>(controller: c, nodeBuilder: (_, n) => Text(n.id)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(() => c.fit(), throwsStateError);
  });

  testWidgets('initial fit scales/centers content once nodes exist', (
    tester,
  ) async {
    final c = OrgChartController<Row>(
      data: const [(id: 'a', parentId: null), (id: 'b', parentId: 'a')],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    // Initial fit is scheduled via addPostFrameCallback (animate: false, so
    // one extra pump is enough — no tween to settle).
    await tester.pump();
    final finder = find.descendant(
      of: find.byType(OrgChart<Row>),
      matching: find.byType(Transform),
    );
    final transform = tester.widget<Transform>(finder.first);
    final scale = transform.transform.getMaxScaleOnAxis();
    // Content (roughly 100x150 for a 2-node top-down chart with 100x50
    // nodes) is much smaller than the 800x600 viewport, so fitTransform
    // should have scaled it up from the default identity (scale 1) — this
    // is really just confirming the postFrameCallback fired at all.
    expect(scale, isNot(closeTo(1.0, 1e-9)));
  });

  testWidgets('bottom-row expand button is tappable through the viewport', (
    tester,
  ) async {
    // A single parent with one child: the child is the bottom-most visible
    // row and, with initialExpandLevel 1 (default), starts collapsed with
    // its own children hidden — giving it an expand button anchored to its
    // rect's bottom edge, which is exactly what the Task 8 finding flagged
    // as at risk of sitting outside the hit-testable box once wrapped in
    // ChartViewport's Transform/OverflowBox.
    final c = OrgChartController<Row>(
      data: const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'b'),
      ],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('node-c'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expand-button-b')));
    await tester.pumpAndSettle();
    expect(find.text('node-c'), findsOneWidget);
  });

  testWidgets('rapid successive animated fit/center calls settle cleanly', (
    tester,
  ) async {
    final c = OrgChartController<Row>(
      data: const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'a'),
      ],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
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

  testWidgets('instant jump mid-animation cancels the in-flight tween', (
    tester,
  ) async {
    final c = OrgChartController<Row>(
      data: const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'a'),
      ],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
    final tc = tester
        .widget<ChartViewport>(find.byType(ChartViewport))
        .transformationController;
    // Start an animated pan/zoom, interrupt it mid-flight with an instant
    // jump, then pump one more frame: the transform must stay pinned at the
    // instant target — the old tween's tick listener must not keep firing
    // and drag it back onto the abandoned trajectory.
    c.centerNode('b'); // animate: true (default), 400ms
    await tester.pump(const Duration(milliseconds: 50)); // mid-flight
    c.centerNode('c', animate: false); // instant jump
    final target = tc.value.clone();
    await tester.pump(const Duration(milliseconds: 16)); // one frame later
    expect(
      tc.value,
      equals(target),
      reason:
          'the in-flight animated tween must be stopped by an '
          'animate: false jump; its tick listener must not overwrite '
          'the instant target on subsequent frames',
    );
    await tester.pumpAndSettle();
    expect(tc.value, equals(target));
  });

  testWidgets('user drag gesture mid-animation cancels the in-flight tween', (
    tester,
  ) async {
    final c = OrgChartController<Row>(
      data: const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'a'),
      ],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
    final tc = tester
        .widget<ChartViewport>(find.byType(ChartViewport))
        .transformationController;
    // Start an animated fit, then begin dragging mid-flight. Once the drag
    // has applied, further frames (with the finger held still) must not
    // change the transform — with the bug, the still-running tween keeps
    // ticking and overwrites the gesture's matrix every frame.
    c.centerNode('c'); // animate: true, 400ms
    await tester.pump(const Duration(milliseconds: 50)); // mid-flight
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ChartViewport)),
    );
    await gesture.moveBy(const Offset(60, 40)); // past touch slop -> pan
    await tester.pump();
    final afterDrag = tc.value.clone();
    await tester.pump(const Duration(milliseconds: 16)); // finger held still
    expect(
      tc.value,
      equals(afterDrag),
      reason:
          'starting a user gesture must stop the in-flight viewport '
          'animation; the old tween must not fight the drag',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('zoomIn mid-animation cancels the in-flight tween', (
    tester,
  ) async {
    final c = OrgChartController<Row>(
      data: const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'a'),
      ],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );
    await tester.pumpWidget(
      MaterialApp(
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
      ),
    );
    await tester.pumpAndSettle();
    final tc = tester
        .widget<ChartViewport>(find.byType(ChartViewport))
        .transformationController;
    // Start an animated pan/zoom, then zoomIn() mid-flight: the zoom must
    // stick — with the bug, zoomBy writes _tc.value but leaves the tween
    // running, and its tick listener wipes the zoom back onto the old
    // trajectory on the very next frame.
    c.centerNode('b'); // animate: true (default), 400ms
    await tester.pump(const Duration(milliseconds: 50)); // mid-flight
    c.zoomIn(); // zoomBy(1.3), applied instantly
    final target = tc.value.clone();
    await tester.pump(const Duration(milliseconds: 16)); // one frame later
    expect(
      tc.value,
      equals(target),
      reason:
          'zoomBy must stop the in-flight viewport animation; the '
          'old tween must not wipe out the zoom on subsequent frames',
    );
    await tester.pumpAndSettle();
    expect(tc.value, equals(target));
  });
}

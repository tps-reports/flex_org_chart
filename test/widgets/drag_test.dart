import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

// a -> (b, c); c -> d. initialExpandLevel: 2 so d is visible from the start.
const rows = <Row>[
  (id: 'a', parentId: null),
  (id: 'b', parentId: 'a'),
  (id: 'c', parentId: 'a'),
  (id: 'd', parentId: 'c'),
];

OrgChartController<Row> makeController([List<Row> data = rows]) =>
    OrgChartController<Row>(
      data: data,
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
      initialExpandLevel: 2,
    );

Widget app(
  OrgChartController<Row> c, {
  void Function(OrgNode<Row>, OrgNode<Row>)? onReparent,
  bool Function(OrgNode<Row>, OrgNode<Row>)? canReparent,
}) => MaterialApp(
  home: Scaffold(
    body: OrgChart<Row>(
      controller: c,
      compact: false,
      nodeSize: (_) => (w: 100, h: 50),
      onReparent: onReparent,
      canReparent: canReparent,
      nodeBuilder: (context, node) =>
          Text('node-${node.id}', key: ValueKey('node-${node.id}')),
    ),
  ),
);

/// Long-presses the center of [key] and returns the still-down gesture.
Future<TestGesture> lift(WidgetTester tester, String key) async {
  final g = await tester.startGesture(
    tester.getCenter(find.byKey(ValueKey(key))),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return g;
}

void main() {
  testWidgets('long-press lifts: ghost appears, original dims', (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c, onReparent: (_, __) {}));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    // The original node's opacity drops to 0.4 (its Positioned wrapper key
    // is 'node-position-d'; the Opacity widget sits inside it).
    final opacity = tester.widget<Opacity>(
      find
          .descendant(
            of: find.byKey(const ValueKey('node-position-d')),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(opacity.opacity, closeTo(0.4, 0.01));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('ghost follows the pointer', (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c, onReparent: (_, __) {}));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    final before = tester.getTopLeft(find.byKey(const ValueKey('drag-ghost')));
    await g.moveBy(const Offset(60, -30));
    await tester.pump();
    final after = tester.getTopLeft(find.byKey(const ValueKey('drag-ghost')));
    // Screen-space delta equals pointer delta (scale is uniform; the fitted
    // chart in an 800x600 test surface renders at scale ~1 or below — accept
    // direction and monotonicity rather than exact pixels).
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('onReparent null: long-press produces no ghost (off is off)', (
    tester,
  ) async {
    final c = makeController();
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('quick drag on a node still pans the viewport', (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c, onReparent: (_, __) {}));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const ValueKey('node-a')));
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('node-d'))),
    );
    // Move immediately — long-press never wins the arena.
    await g.moveBy(const Offset(50, 50));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byKey(const ValueKey('node-a')));
    expect(after, isNot(equals(before)));
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
  });

  testWidgets(
    'a pan started during the post-drop snap-back window still works',
    (tester) async {
      final c = makeController();
      await tester.pumpWidget(app(c, onReparent: (_, __) {}));
      await tester.pumpAndSettle();

      // Lift node-d and drop it far off any node, so the drop is invalid
      // and kicks off the ~150ms ghost snap-back (_drag stays non-null
      // for that whole window, even though the pointer is already gone).
      final g = await lift(tester, 'node-d');
      await g.moveBy(const Offset(-2000, -2000));
      await tester.pump();
      await g.up();
      // Applies _endDrag()'s setState (which flips _dragPointerActive to
      // false) without waiting out the snap-back animation itself — a
      // bare pump(), not pumpAndSettle(), so the snap-back is still
      // in-flight (_drag != null) for the rest of this test.
      await tester.pump();
      expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);

      // A brand new pan, started on empty space while the snap-back is
      // still playing, must take effect immediately — not be silently
      // eaten for the whole remaining snap-back duration.
      final before = tester.getTopLeft(find.byKey(const ValueKey('node-a')));
      final g2 = await tester.startGesture(const Offset(2, 2));
      await g2.moveBy(const Offset(40, 30));
      await tester.pump();
      final after = tester.getTopLeft(find.byKey(const ValueKey('node-a')));
      expect(after, isNot(equals(before)));

      await g2.up();
      await tester.pumpAndSettle();
    },
  );
}

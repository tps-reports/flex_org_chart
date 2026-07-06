import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

void main() {
  testWidgets('expanding animates the new child in from its parent',
      (tester) async {
    final c = OrgChartController<Row>(data: const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
    ], idOf: (r) => r.id, parentIdOf: (r) => r.parentId, initialExpandLevel: 0);
    await tester.pumpWidget(MaterialApp(
      home: OrgChart<Row>(
        controller: c,
        compact: false,
        nodeSize: (_) => (w: 100, h: 50),
        animationDuration: const Duration(milliseconds: 400),
        nodeBuilder: (_, n) =>
            Text('node-${n.id}', key: ValueKey('node-${n.id}')),
      ),
    ));
    await tester.pumpAndSettle();
    c.expand('a');
    await tester.pump(); // start animation
    final earlyY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;
    await tester.pump(const Duration(milliseconds: 200));
    final midY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;
    await tester.pumpAndSettle();
    final endY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;
    // b enters at parent position and travels to its final spot
    expect(earlyY, lessThan(midY));
    expect(midY, lessThan(endY));
  });

  testWidgets('collapsing removes the child after the animation completes',
      (tester) async {
    final c = OrgChartController<Row>(data: const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
    ], idOf: (r) => r.id, parentIdOf: (r) => r.parentId);
    await tester.pumpWidget(MaterialApp(
      home: OrgChart<Row>(
        controller: c,
        compact: false,
        nodeBuilder: (_, n) =>
            Text('node-${n.id}', key: ValueKey('node-${n.id}')),
      ),
    ));
    await tester.pumpAndSettle();
    c.collapse('a');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('node-b')), findsOneWidget); // mid-exit
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('node-b')), findsNothing);
  });
}

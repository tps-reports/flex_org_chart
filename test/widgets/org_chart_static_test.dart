import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

const rows = <Row>[
  (id: 'a', parentId: null),
  (id: 'b', parentId: 'a'),
  (id: 'c', parentId: 'a'),
];

OrgChartController<Row> makeController([List<Row> data = rows]) =>
    OrgChartController<Row>(
        data: data, idOf: (r) => r.id, parentIdOf: (r) => r.parentId);

Widget app(OrgChartController<Row> c) => MaterialApp(
      home: Scaffold(
        body: OrgChart<Row>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          nodeBuilder: (context, node) =>
              Text('node-${node.id}', key: ValueKey('node-${node.id}')),
        ),
      ),
    );

void main() {
  testWidgets('renders visible nodes as widgets', (tester) async {
    await tester.pumpWidget(app(makeController()));
    await tester.pumpAndSettle();
    expect(find.text('node-a'), findsOneWidget);
    expect(find.text('node-b'), findsOneWidget);
    expect(find.text('node-c'), findsOneWidget);
  });

  testWidgets('children are positioned below parent in top layout',
      (tester) async {
    await tester.pumpWidget(app(makeController()));
    await tester.pumpAndSettle();
    final aY = tester.getTopLeft(find.byKey(const ValueKey('node-a'))).dy;
    final bY = tester.getTopLeft(find.byKey(const ValueKey('node-b'))).dy;
    expect(bY, greaterThan(aY));
  });

  testWidgets('default expand button toggles subtree', (tester) async {
    final c = makeController(const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
      (id: 'c', parentId: 'b'),
    ]);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    expect(find.text('node-c'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expand-button-b')));
    await tester.pumpAndSettle();
    expect(find.text('node-c'), findsOneWidget);
  });

  testWidgets('data error renders error state, not blank canvas',
      (tester) async {
    final c = makeController(const [
      (id: 'x', parentId: 'ghost'),
      (id: 'r', parentId: null),
    ]);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    expect(find.textContaining('missing parent'), findsOneWidget);
    expect(find.textContaining('x'), findsWidgets);
  });

  testWidgets('empty data renders the default empty state, not the error view',
      (tester) async {
    final c = makeController(const []);
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    expect(find.text('No data to display'), findsOneWidget);
    expect(find.textContaining('Could not build org chart'), findsNothing);
  });

  testWidgets('empty data renders a custom emptyBuilder when provided',
      (tester) async {
    final c = makeController(const []);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrgChart<Row>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          nodeBuilder: (context, node) => Text('node-${node.id}'),
          emptyBuilder: (context) => const Text('Nothing to show yet'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to show yet'), findsOneWidget);
    expect(find.text('No data to display'), findsNothing);
  });

  testWidgets(
      'setData([]) after non-empty data shows the empty state, and a '
      'later non-empty setData brings the chart back', (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    expect(find.text('node-a'), findsOneWidget);

    c.setData(const []);
    await tester.pumpAndSettle();
    expect(find.text('No data to display'), findsOneWidget);
    expect(find.textContaining('Could not build org chart'), findsNothing);
    expect(find.text('node-a'), findsNothing);

    c.setData(rows);
    await tester.pumpAndSettle();
    expect(find.text('node-a'), findsOneWidget);
    expect(find.text('No data to display'), findsNothing);
  });
}

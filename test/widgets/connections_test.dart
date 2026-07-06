import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/connection_painter.dart';

typedef Row = ({String id, String? parentId});

void main() {
  testWidgets('paints only connections whose endpoints are both visible',
      (tester) async {
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
    await tester.pumpWidget(MaterialApp(
      home: OrgChart<Row>(
        controller: c,
        compact: false,
        nodeBuilder: (_, n) => Text('node-${n.id}'),
      ),
    ));
    await tester.pumpAndSettle();
    final painter = tester
        .widget<CustomPaint>(find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ConnectionPainter))
        .painter as ConnectionPainter;
    expect(painter.visibleConnections.map((v) => v.connection.to), ['b']);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/edge_painter.dart';

typedef Row = ({String id, String? parentId});

void main() {
  testWidgets('highlightPathToRoot marks link child ids for painter', (
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
    c.expandAll();
    c.highlightPathToRoot('c');
    await tester.pumpAndSettle();
    final painter =
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is EdgePainter,
                  ),
                )
                .painter
            as EdgePainter;
    // links a->b and b->c are on the highlighted path
    expect(painter.highlightedChildIds, unorderedEquals({'b', 'c'}));
  });
}

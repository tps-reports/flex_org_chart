import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

OrgChartController<Row> make(List<Row> data, {int initialExpandLevel = 1}) =>
    OrgChartController<Row>(
      data: data,
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
      initialExpandLevel: initialExpandLevel,
    );

void configure(OrgChartController<Row> c) => c.configure(
  OrgChartConfig<Row>(
    layout: ChartLayout.top,
    compact: false,
    spacing: const ChartSpacing(),
    nodeSize: (_) => (w: 100, h: 50),
  ),
);

const tree = <Row>[
  (id: 'a', parentId: null),
  (id: 'b', parentId: 'a'),
  (id: 'c', parentId: 'a'),
  (id: 'd', parentId: 'c'),
];

void main() {
  group('data getter', () {
    test('returns the current list and is unmodifiable', () {
      final c = make(tree);
      configure(c);
      expect(c.data.map((r) => r.id), ['a', 'b', 'c', 'd']);
      expect(
        () => c.data.add((id: 'x', parentId: null)),
        throwsUnsupportedError,
      );
    });

    test('reflects setData', () {
      final c = make(tree);
      configure(c);
      c.setData(const [(id: 'a', parentId: null)]);
      expect(c.data.map((r) => r.id), ['a']);
    });
  });
}

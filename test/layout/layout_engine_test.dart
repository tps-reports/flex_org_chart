import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

ChartState<Row> compute(List<Row> rows,
    {ChartLayout layout = ChartLayout.top,
    bool compact = false,
    bool Function(OrgNode<Row>)? isVisible}) {
  final tree = stratify<Row>(
      data: rows, idOf: (r) => r.id, parentIdOf: (r) => r.parentId);
  return LayoutEngine.compute<Row>(
    tree: tree,
    isVisible: isVisible ?? (_) => true,
    layout: layout,
    compact: compact,
    spacing: const ChartSpacing(),
    nodeSize: (_) => (w: 250, h: 150),
  );
}

void main() {
  final rows = <Row>[
    (id: 'a', parentId: null),
    (id: 'b', parentId: 'a'),
    (id: 'c', parentId: 'a'),
  ];

  test('top layout: children below parent, one link per child', () {
    final st = compute(rows);
    final a = st.byId('a')!, b = st.byId('b')!, c = st.byId('c')!;
    expect(b.rect.top, greaterThan(a.rect.bottom - 1));
    expect(b.rect.left, lessThan(c.rect.left));
    expect(st.links.map((l) => l.childId), unorderedEquals(['b', 'c']));
    expect(st.bounds.width, greaterThan(0));
  });

  test('left layout: children to the right of parent', () {
    final st = compute(rows, layout: ChartLayout.left);
    expect(st.byId('b')!.rect.left, greaterThan(st.byId('a')!.rect.right - 1));
  });

  test('bottom layout mirrors top vertically', () {
    final top = compute(rows);
    final bottom = compute(rows, layout: ChartLayout.bottom);
    expect(bottom.byId('b')!.rect.bottom, lessThan(bottom.byId('a')!.rect.top + 1));
    expect(bottom.byId('b')!.rect.left, closeTo(top.byId('b')!.rect.left, 1e-6));
  });

  test('collapsed subtree is excluded from nodes and links', () {
    final st = compute(rows, isVisible: (n) => n.id != 'c');
    expect(st.byId('c'), isNull);
    expect(st.links.map((l) => l.childId), ['b']);
  });

  test('multi-root lays out side by side', () {
    final st = compute([(id: 'a', parentId: null), (id: 'x', parentId: null)]);
    expect(st.byId('a')!.rect.top, closeTo(st.byId('x')!.rect.top, 1e-6));
    expect(st.byId('a')!.rect.right, lessThanOrEqualTo(st.byId('x')!.rect.left));
    expect(st.links, isEmpty);
  });
}

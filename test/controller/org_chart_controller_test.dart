import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

OrgChartController<Row> make(List<Row> rows, {int initialExpandLevel = 1}) {
  final c = OrgChartController<Row>(
    data: rows,
    idOf: (r) => r.id,
    parentIdOf: (r) => r.parentId,
    initialExpandLevel: initialExpandLevel,
  );
  c.configure(OrgChartConfig<Row>(
    layout: ChartLayout.top,
    compact: false,
    spacing: const ChartSpacing(),
    nodeSize: (_) => (w: 250, h: 150),
  ));
  return c;
}

const rows = <Row>[
  (id: 'a', parentId: null),
  (id: 'b', parentId: 'a'),
  (id: 'c', parentId: 'b'),
  (id: 'd', parentId: 'c'),
];

void main() {
  test('initialExpandLevel=1 shows root and its children only', () {
    final c = make(rows);
    expect(c.visibleNodes.map((n) => n.id), unorderedEquals(['a', 'b']));
    expect(c.state.byId('c'), isNull);
  });

  test('expand walks deeper one level; collapse hides subtree', () {
    final c = make(rows);
    var notifications = 0;
    c.addListener(() => notifications++);
    c.expand('b');
    expect(c.state.byId('c'), isNotNull);
    expect(c.state.byId('d'), isNull);
    c.collapse('a');
    expect(c.visibleNodes.map((n) => n.id), ['a']);
    expect(notifications, 2);
  });

  test('expandAll / collapseAll', () {
    final c = make(rows);
    c.expandAll();
    expect(c.visibleNodes, hasLength(4));
    c.collapseAll();
    expect(c.visibleNodes.map((n) => n.id), ['a']);
  });

  test('setExpanded with expandAncestors makes a deep node visible', () {
    final c = make(rows);
    c.setExpanded('c');
    expect(c.state.byId('d'), isNotNull);
  });

  test('highlightPathToRoot flags node and ancestors', () {
    final c = make(rows)..expandAll();
    c.highlightPathToRoot('d');
    expect(c.nodeById('d')!.isHighlighted, isTrue);
    expect(c.nodeById('b')!.isOnHighlightedPath, isTrue);
    c.clearHighlights();
    expect(c.nodeById('d')!.isHighlighted, isFalse);
  });

  test('previousState holds the state before the last change', () {
    final c = make(rows);
    final before = c.state;
    c.expand('b');
    expect(c.previousState, same(before));
  });

  test('bad data surfaces as dataError, not a throw, on setData', () {
    final c = make(rows);
    c.setData(const [(id: 'x', parentId: 'ghost'), (id: 'y', parentId: null)]);
    expect(c.dataError, isA<OrgChartDataException>());
    expect(c.state.nodes, isEmpty);
  });

  test('viewport methods throw StateError when no chart attached', () {
    final c = make(rows);
    expect(() => c.fit(), throwsStateError);
    expect(() => c.centerNode('a'), throwsStateError);
  });
}

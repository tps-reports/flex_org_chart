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
  c.configure(
    OrgChartConfig<Row>(
      layout: ChartLayout.top,
      compact: false,
      spacing: const ChartSpacing(),
      nodeSize: (_) => (w: 250, h: 150),
    ),
  );
  return c;
}

const rows = <Row>[
  (id: 'a', parentId: null),
  (id: 'b', parentId: 'a'),
  (id: 'c', parentId: 'b'),
  (id: 'd', parentId: 'c'),
];

class FakeViewportHandle implements ChartViewportHandle {
  final List<LayoutRect> fitBoundsCalls = [];
  final List<LayoutRect> centerOnCalls = [];
  final List<double> zoomByCalls = [];

  @override
  void fitBounds(LayoutRect bounds, {bool animate = true}) =>
      fitBoundsCalls.add(bounds);

  @override
  void centerOn(LayoutRect rect, {bool animate = true}) =>
      centerOnCalls.add(rect);

  @override
  void zoomBy(double factor) => zoomByCalls.add(factor);
}

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

  test('empty data is an empty state, not a dataError', () {
    final c = make(const []);
    expect(c.dataError, isNull);
    expect(c.state.nodes, isEmpty);
  });

  test('setData([]) clears a previous chart to an empty state with no '
      'dataError, and a later non-empty setData brings the chart back', () {
    final c = make(rows);
    expect(c.state.nodes, isNotEmpty);

    c.setData(const []);
    expect(c.dataError, isNull);
    expect(c.state.nodes, isEmpty);

    c.setData(rows);
    expect(c.dataError, isNull);
    expect(c.state.nodes, isNotEmpty);
    expect(c.visibleNodes.map((n) => n.id), unorderedEquals(['a', 'b']));
  });

  test('viewport methods throw StateError when no chart attached', () {
    final c = make(rows);
    expect(() => c.fit(), throwsStateError);
    expect(() => c.centerNode('a'), throwsStateError);
  });

  test('centerNode reveals a hidden node by expanding its ancestors', () {
    final c = make(rows); // initialExpandLevel 1: only a, b visible
    final handle = FakeViewportHandle();
    c.attachViewport(handle);
    expect(c.state.byId('d'), isNull); // hidden before the call

    c.centerNode('d', animate: false);

    expect(c.state.byId('d'), isNotNull); // revealed, not a silent no-op
    expect(handle.centerOnCalls, hasLength(1));
    expect(handle.fitBoundsCalls, isEmpty);
    // Reveal != expand: the target's own expanded flag stays false.
    expect(c.nodeById('d')!.isExpanded, isFalse);

    c.centerNode('d', withDescendants: true, animate: false);
    expect(handle.fitBoundsCalls, hasLength(1));
  });

  group('setData preserveState', () {
    test('surviving ids keep expansion state by default', () {
      final c = make(const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'b'),
      ]);
      c.expand('b'); // deeper than initialExpandLevel=1
      expect(c.state.byId('c'), isNotNull);
      // Same tree plus one new leaf under c.
      c.setData(const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'b'),
        (id: 'd', parentId: 'c'),
      ]);
      // b's expansion survived: c still visible.
      expect(c.state.byId('c'), isNotNull);
      // New node d follows the initial-expand rule for its parent (c was
      // never expanded, so d is hidden).
      expect(c.state.byId('d'), isNull);
    });

    test('surviving ids keep highlight flags by default', () {
      final c = make(const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
      ]);
      c.highlightPathToRoot('b');
      c.setData(const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'x', parentId: 'a'),
      ]);
      expect(c.nodeById('b')!.isHighlighted, isTrue);
      expect(c.nodeById('a')!.isOnHighlightedPath, isTrue);
      expect(c.nodeById('x')!.isHighlighted, isFalse);
    });

    test('preserveState: false reproduces the full reset', () {
      final c = make(const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'b'),
      ]);
      c.expand('b');
      c.highlight('b');
      c.setData(const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'b'),
      ], preserveState: false);
      expect(c.state.byId('c'), isNull); // b back to collapsed (depth 1)
      expect(c.nodeById('b')!.isHighlighted, isFalse);
    });
  });
}

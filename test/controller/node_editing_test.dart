import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

OrgChartController<Row> make(
  List<Row> data, {
  int initialExpandLevel = 1,
  void Function(List<Row> data)? onDataChanged,
  Row Function(Row item, String? newParentId)? withParent,
}) => OrgChartController<Row>(
  data: data,
  idOf: (r) => r.id,
  parentIdOf: (r) => r.parentId,
  initialExpandLevel: initialExpandLevel,
  onDataChanged: onDataChanged,
  withParent: withParent,
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

Row rowWithParent(Row r, String? p) => (id: r.id, parentId: p);

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

  group('addNode', () {
    test('adds a child under an existing parent and relayouts', () {
      List<Row>? changed;
      final c = make(tree, onDataChanged: (d) => changed = d);
      configure(c);
      c.addNode((id: 'e', parentId: 'b'));
      expect(c.nodeById('e')!.parent!.id, 'b');
      expect(c.data.length, 5);
      expect(changed, isNotNull);
      expect(changed!.map((r) => r.id), contains('e'));
    });

    test('null parent id adds a new root', () {
      final c = make(tree);
      configure(c);
      c.addNode((id: 'r2', parentId: null));
      expect(c.nodeById('r2')!.parent, isNull);
    });

    test('does not auto-expand a collapsed parent', () {
      // initialExpandLevel 1: c (depth 1) starts collapsed, d hidden.
      final c = make(tree);
      configure(c);
      c.addNode((id: 'e', parentId: 'c'));
      expect(c.nodeById('e'), isNotNull); // in the tree
      expect(c.state.byId('e'), isNull); // but not visible
    });

    test('preserves expansion state of existing nodes', () {
      final c = make(tree);
      configure(c);
      c.expand('c'); // d becomes visible
      c.addNode((id: 'e', parentId: 'b'));
      expect(c.state.byId('d'), isNotNull);
    });

    test('duplicate id throws ArgumentError and changes nothing', () {
      var notified = 0;
      List<Row>? changed;
      final c = make(tree, onDataChanged: (d) => changed = d);
      configure(c);
      c.addListener(() => notified++);
      expect(() => c.addNode((id: 'b', parentId: 'a')), throwsArgumentError);
      expect(c.data.length, 4);
      expect(notified, 0);
      expect(changed, isNull);
    });

    test('unknown parent id throws ArgumentError and changes nothing', () {
      final c = make(tree);
      configure(c);
      expect(
        () => c.addNode((id: 'e', parentId: 'ghost')),
        throwsArgumentError,
      );
      expect(c.data.length, 4);
    });

    test('setData does NOT fire onDataChanged', () {
      List<Row>? changed;
      final c = make(tree, onDataChanged: (d) => changed = d);
      configure(c);
      c.setData(const [(id: 'a', parentId: null)]);
      expect(changed, isNull);
    });

    test('editing a controller in data-error state throws StateError', () {
      final c = make(const [(id: 'x', parentId: 'ghost')]);
      configure(c);
      expect(c.dataError, isNotNull);
      expect(() => c.addNode((id: 'e', parentId: null)), throwsStateError);
    });
  });

  group('reparent', () {
    test('moves a subtree and preserves its expansion', () {
      List<Row>? changed;
      final c = make(
        tree,
        withParent: rowWithParent,
        onDataChanged: (d) => changed = d,
      );
      configure(c);
      c.expand('c'); // d visible
      c.reparent('c', 'b');
      expect(c.nodeById('c')!.parent!.id, 'b');
      expect(c.nodeById('c')!.isExpanded, isTrue);
      expect(changed!.firstWhere((r) => r.id == 'c').parentId, 'b');
    });

    test('null newParentId makes the node a root', () {
      final c = make(tree, withParent: rowWithParent);
      configure(c);
      c.reparent('c', null);
      expect(c.nodeById('c')!.parent, isNull);
    });

    test('reparent to current parent is a silent no-op', () {
      var notified = 0;
      List<Row>? changed;
      final c = make(
        tree,
        withParent: rowWithParent,
        onDataChanged: (d) => changed = d,
      );
      configure(c);
      c.addListener(() => notified++);
      c.reparent('b', 'a');
      expect(notified, 0);
      expect(changed, isNull);
    });

    test('throws StateError without withParent', () {
      final c = make(tree);
      configure(c);
      expect(() => c.reparent('b', 'c'), throwsStateError);
    });

    test('unknown id / unknown parent / self / descendant all throw', () {
      final c = make(tree, withParent: rowWithParent);
      configure(c);
      expect(() => c.reparent('ghost', 'a'), throwsArgumentError);
      expect(() => c.reparent('b', 'ghost'), throwsArgumentError);
      expect(() => c.reparent('b', 'b'), throwsArgumentError);
      expect(() => c.reparent('c', 'd'), throwsArgumentError); // d under c
    });

    test('a throw leaves the controller unchanged', () {
      var notified = 0;
      final c = make(tree, withParent: rowWithParent);
      configure(c);
      c.addListener(() => notified++);
      expect(() => c.reparent('c', 'd'), throwsArgumentError);
      expect(c.nodeById('c')!.parent!.id, 'a');
      expect(notified, 0);
    });

    test('withParent changing the id throws StateError, nothing mutates', () {
      final c = make(
        tree,
        withParent: (r, p) => (id: '${r.id}-oops', parentId: p),
      );
      configure(c);
      expect(() => c.reparent('b', 'c'), throwsStateError);
      expect(c.nodeById('b'), isNotNull);
      expect(c.nodeById('b-oops'), isNull);
    });
  });
}

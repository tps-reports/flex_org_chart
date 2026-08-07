import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/drag_reparent.dart';

typedef Row = ({String id, String? parentId});

// Tree: a -> (b, c); c -> d. Rects laid out manually, non-overlapping,
// 100x50 each, so hits are unambiguous.
ChartState<Row> makeState(OrgTree<Row> tree) {
  LayoutRect r(double left, double top) => LayoutRect(left, top, 100, 50);
  final rects = {
    'a': r(0, 0),
    'b': r(-120, 100),
    'c': r(120, 100),
    'd': r(120, 200),
  };
  final nodes = [
    for (final e in rects.entries) NodeLayout(tree.nodeById(e.key)!, e.value),
  ];
  return ChartState<Row>(
    nodes: nodes,
    links: const [],
    bounds: const LayoutRect(-120, 0, 340, 250),
  );
}

OrgTree<Row> makeTree() => stratify<Row>(
  data: const [
    (id: 'a', parentId: null),
    (id: 'b', parentId: 'a'),
    (id: 'c', parentId: 'a'),
    (id: 'd', parentId: 'c'),
  ],
  idOf: (r) => r.id,
  parentIdOf: (r) => r.parentId,
);

void main() {
  group('resolveDropTarget', () {
    test('returns the node whose rect contains the point', () {
      final tree = makeTree();
      final t = resolveDropTarget<Row>(
        state: makeState(tree),
        dragged: tree.nodeById('d')!,
        point: (x: -70.0, y: 125.0), // inside b
      );
      expect(t?.id, 'b');
    });

    test('returns null on empty space', () {
      final tree = makeTree();
      final t = resolveDropTarget<Row>(
        state: makeState(tree),
        dragged: tree.nodeById('d')!,
        point: (x: 500.0, y: 500.0),
      );
      expect(t, isNull);
    });

    test('self is never a target', () {
      final tree = makeTree();
      final t = resolveDropTarget<Row>(
        state: makeState(tree),
        dragged: tree.nodeById('d')!,
        point: (x: 170.0, y: 225.0), // inside d itself
      );
      expect(t, isNull);
    });

    test('descendants are never targets (cycle rule)', () {
      final tree = makeTree();
      final t = resolveDropTarget<Row>(
        state: makeState(tree),
        dragged: tree.nodeById('c')!,
        point: (x: 170.0, y: 225.0), // inside d, a descendant of c
      );
      expect(t, isNull);
    });

    test('canReparent veto blocks a geometric hit', () {
      final tree = makeTree();
      final t = resolveDropTarget<Row>(
        state: makeState(tree),
        dragged: tree.nodeById('d')!,
        point: (x: -70.0, y: 125.0), // inside b
        canReparent: (node, candidate) => candidate.id != 'b',
      );
      expect(t, isNull);
    });

    test('overlapping rects: topmost (last in state order) wins', () {
      final tree = makeTree();
      // b and c forced to the same rect; state list order is a,b,c,d so c
      // paints later and must win.
      LayoutRect r(double left, double top) => LayoutRect(left, top, 100, 50);
      final state = ChartState<Row>(
        nodes: [
          NodeLayout(tree.nodeById('a')!, r(0, 0)),
          NodeLayout(tree.nodeById('b')!, r(0, 100)),
          NodeLayout(tree.nodeById('c')!, r(0, 100)),
          NodeLayout(tree.nodeById('d')!, r(0, 200)),
        ],
        links: const [],
        bounds: const LayoutRect(0, 0, 100, 250),
      );
      final t = resolveDropTarget<Row>(
        state: state,
        dragged: tree.nodeById('d')!,
        point: (x: 50.0, y: 125.0),
      );
      expect(t?.id, 'c');
    });

    test('invalid topmost hit does not fall through to a node beneath', () {
      final tree = makeTree();
      // d (the dragged node) sits on top of b at the same rect: pointer is
      // visually over d, so there is NO target — not b underneath.
      LayoutRect r(double left, double top) => LayoutRect(left, top, 100, 50);
      final state = ChartState<Row>(
        nodes: [
          NodeLayout(tree.nodeById('a')!, r(0, 0)),
          NodeLayout(tree.nodeById('b')!, r(0, 100)),
          NodeLayout(tree.nodeById('d')!, r(0, 100)),
        ],
        links: const [],
        bounds: const LayoutRect(0, 0, 100, 150),
      );
      final t = resolveDropTarget<Row>(
        state: state,
        dragged: tree.nodeById('d')!,
        point: (x: 50.0, y: 125.0),
      );
      expect(t, isNull);
    });
  });

  group('DragState', () {
    OrgNode<Row> node() => makeTree().nodeById('d')!;

    test('ghostTopLeft is position minus grabOffset', () {
      final s = DragState<Row>(
        node: node(),
        sourceRect: const LayoutRect(120, 200, 100, 50),
        grabOffset: const Offset(30, 10),
        position: const Offset(200, 300),
      );
      expect(s.ghostTopLeft, const Offset(170, 290));
    });

    test('copyWith clearTarget can null a set targetId', () {
      final s = DragState<Row>(
        node: node(),
        sourceRect: const LayoutRect(120, 200, 100, 50),
        grabOffset: Offset.zero,
        position: Offset.zero,
        targetId: 'b',
      );
      expect(s.copyWith(clearTarget: true).targetId, isNull);
      expect(s.copyWith().targetId, 'b');
      expect(s.copyWith(targetId: 'a').targetId, 'a');
    });
  });
}

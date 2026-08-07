# Drag-and-Drop Re-parenting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Long-press a node, drag it, drop it onto another node; the chart fires `onReparent(node, newParent)` and the app applies the change via `setData`, which now preserves expansion/highlight state.

**Architecture:** All drop-target math is pure Dart in a new `drag_reparent.dart` (unit-tested without widgets). The `OrgChart` widget owns the gesture lifecycle: a long-press recognizer per node lifts, chart-space coordinates come from Flutter's transform-aware gesture `localPosition` (see refinement note below), the ghost renders inside the already-transformed Stack, and `ChartViewport` gains an `enabled` flag so pan/zoom is suppressed mid-drag. Spec: `docs/superpowers/specs/2026-08-06-drag-reparent-design.md`.

**Tech Stack:** Flutter (no new dependencies). Tests: `flutter_test` unit + widget tests.

**Refinement over the spec (coordinate conversion):** The spec called for inverting the `TransformationController` matrix per pointer update. Flutter already delivers transform-aware coordinates: gesture callbacks' `localPosition` is un-transformed through the ancestor `Transform` (via `PointerEvent.transformed`), and it is relative to the node wrapper whose layout-space top-left is exactly `node.rect.left/top`. So the chart-space pointer is `nodeRect.topLeft + localPosition` — same zoom-correctness, no matrix code. This is safe because the transform is frozen for the duration of a drag: viewport gestures are disabled (`ChartViewport.enabled = false`) and any programmatic viewport call or relayout cancels the drag.

## Global Constraints

- No TODOs, stubs, or placeholder handlers in committed code (user CLAUDE.md).
- `copyWith` with a nullable field must support clearing it via an explicit flag (user CLAUDE.md rule 9) — `DragState.copyWith` does this for `targetId`.
- Every task: `dart format .` and `flutter analyze` must be clean before commit; run from the repo root `/Users/michael/code/flex_org_chart`.
- Tests must fail when production code is broken — each task writes the failing test first (TDD).
- Commit messages: conventional-commit style matching the repo's history (`feat:`, `fix:`, `docs:`, `test:`), each ending with the trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- No new public exports from `lib/flex_org_chart.dart` — `DragState`/`resolveDropTarget` stay internal; the public API is only the three new `OrgChart` params and the new `setData` named param.
- New `OrgChart` params must be dartdoc'd in the style of the existing params (every exported symbol in this package has dartdoc).

---

### Task 1: `setData` preserves expansion/highlight state

**Files:**
- Modify: `lib/src/controller/org_chart_controller.dart:169-174` (the `setData` method)
- Test: `test/controller/org_chart_controller_test.dart` (append tests)

**Interfaces:**
- Consumes: existing `OrgChartController` internals (`_tree`, `_rebuildTreeIfNeeded`, `_relayout`).
- Produces: `void setData(List<T> data, {bool preserveState = true})` — Task 5's drop flow and the Task 6 example rely on the default preserving expansion for surviving ids.

- [ ] **Step 1: Write the failing tests**

Append to `test/controller/org_chart_controller_test.dart`, inside `main()`, following the file's existing helper conventions (it builds controllers from `(id, parentId)` records; reuse its existing `makeController`-style helper if present, otherwise define locally in the new group):

```dart
// Top level of the test file (Dart forbids typedefs inside functions);
// reuse the file's existing record typedef instead if it has one.
typedef R = ({String id, String? parentId});

group('setData preserveState', () {
  OrgChartController<R> make(List<R> data) => OrgChartController<R>(
    data: data,
    idOf: (r) => r.id,
    parentIdOf: (r) => r.parentId,
  );
  // Attach a config so the controller lays out (mirrors what OrgChart does).
  void configure(OrgChartController<R> c) => c.configure(OrgChartConfig<R>(
    layout: ChartLayout.top,
    compact: false,
    spacing: const ChartSpacing(),
    nodeSize: (_) => (w: 100, h: 50),
  ));

  test('surviving ids keep expansion state by default', () {
    final c = make(const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
      (id: 'c', parentId: 'b'),
    ]);
    configure(c);
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
    configure(c);
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
    configure(c);
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/controller/org_chart_controller_test.dart`
Expected: FAIL — first two new tests fail (state reset / named param missing compiles only after Step 3; if it doesn't compile, that counts as the failing state).

- [ ] **Step 3: Implement**

Replace `setData` in `lib/src/controller/org_chart_controller.dart` (keep the dartdoc, extend it):

```dart
  /// Replaces the backing data and re-stratifies the tree. If the new data
  /// is malformed, [dataError] is set and [state] becomes an empty
  /// [ChartState] — this method never throws.
  ///
  /// With [preserveState] true (the default), nodes whose ids survive into
  /// the new data keep their expansion and highlight flags; only new ids
  /// get the [initialExpandLevel] rule. Pass false to reset every node's
  /// state exactly as the constructor does — the pre-0.2 behavior.
  void setData(List<T> data, {bool preserveState = true}) {
    Map<String, ({bool expanded, bool highlighted, bool onPath})>? saved;
    final oldTree = _tree;
    if (preserveState && oldTree != null) {
      saved = {
        for (final n in oldTree.allNodes)
          n.id: (
            expanded: n.isExpanded,
            highlighted: n.isHighlighted,
            onPath: n.isOnHighlightedPath,
          ),
      };
    }
    _data = List.of(data);
    _tree = null;
    _rebuildTreeIfNeeded();
    final newTree = _tree;
    if (saved != null && newTree != null) {
      for (final n in newTree.allNodes) {
        final s = saved[n.id];
        if (s == null) continue;
        n.isExpanded = s.expanded;
        n.isHighlighted = s.highlighted;
        n.isOnHighlightedPath = s.onPath;
      }
    }
    _relayout();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/controller/org_chart_controller_test.dart`
Expected: PASS (all, including pre-existing tests — none of them pass `preserveState`, and identical-data calls with preserved state are layout-identical; if a pre-existing test asserted the reset behavior, update that test to pass `preserveState: false` and note it in the commit message).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/controller/org_chart_controller.dart test/controller/org_chart_controller_test.dart
git commit -m "feat: setData preserves expansion/highlight state for surviving ids

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Pure drag logic — `DragState` and `resolveDropTarget`

**Files:**
- Create: `lib/src/widgets/drag_reparent.dart`
- Test: `test/widgets/drag_reparent_test.dart`

**Interfaces:**
- Consumes: `ChartState<T>`/`NodeLayout<T>` (`lib/src/model/chart_state.dart`), `OrgNode<T>.descendants` (`lib/src/model/org_node.dart`), `LayoutRect`/`Pt` (`lib/src/model/geometry.dart`).
- Produces (used by Tasks 4–5):
  - `class DragState<T>` with fields `OrgNode<T> node`, `LayoutRect sourceRect`, `Offset grabOffset`, `Offset position`, `String? targetId`; getter `Offset get ghostTopLeft`; method `DragState<T> copyWith({Offset? position, String? targetId, bool clearTarget = false})`.
  - `OrgNode<T>? resolveDropTarget<T>({required ChartState<T> state, required OrgNode<T> dragged, required Pt point, bool Function(OrgNode<T> node, OrgNode<T> candidateParent)? canReparent})`.

- [ ] **Step 1: Write the failing tests**

Create `test/widgets/drag_reparent_test.dart`:

```dart
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';
import 'package:flex_org_chart/src/widgets/drag_reparent.dart';

typedef Row = ({String id, String? parentId});

// Tree: a -> (b, c); c -> d. Rects laid out manually, non-overlapping,
// 100x50 each, so hits are unambiguous.
ChartState<Row> makeState(OrgTree<Row> tree) {
  LayoutRect r(double left, double top) => LayoutRect(left, top, 100, 50);
  final rects = {'a': r(0, 0), 'b': r(-120, 100), 'c': r(120, 100), 'd': r(120, 200)};
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/drag_reparent_test.dart`
Expected: FAIL — `drag_reparent.dart` does not exist (compile error).

- [ ] **Step 3: Implement**

Create `lib/src/widgets/drag_reparent.dart`:

```dart
import 'dart:ui' show Offset;

import '../model/chart_state.dart';
import '../model/geometry.dart';
import '../model/org_node.dart';

/// Immutable snapshot of an in-progress drag-to-reparent interaction.
/// The `OrgChart` widget holds exactly one nullable instance and replaces
/// it on every pointer update.
class DragState<T> {
  /// Creates a drag snapshot. All positions are in layout space (the same
  /// coordinate space as [ChartState] rects).
  const DragState({
    required this.node,
    required this.sourceRect,
    required this.grabOffset,
    required this.position,
    this.targetId,
  });

  /// The node being dragged.
  final OrgNode<T> node;

  /// [node]'s layout rect at the moment it was lifted.
  final LayoutRect sourceRect;

  /// Pointer offset within the node at lift — keeps the ghost anchored
  /// under the finger where it was grabbed rather than snapping its
  /// top-left corner to the pointer.
  final Offset grabOffset;

  /// Current pointer position, in layout space.
  final Offset position;

  /// Id of the currently resolved valid drop target, or `null` when the
  /// pointer is not over one.
  final String? targetId;

  /// Where the ghost's top-left corner renders, in layout space.
  Offset get ghostTopLeft => position - grabOffset;

  /// Copy with a new pointer position and/or target. [targetId] is a valid
  /// null state (pointer over empty space), so clearing it needs the
  /// explicit [clearTarget] flag.
  DragState<T> copyWith({
    Offset? position,
    String? targetId,
    bool clearTarget = false,
  }) => DragState(
    node: node,
    sourceRect: sourceRect,
    grabOffset: grabOffset,
    position: position ?? this.position,
    targetId: clearTarget ? null : (targetId ?? this.targetId),
  );
}

/// Resolves the drop target under [point] for [dragged]: the topmost
/// visible node (last in [ChartState.nodes] order, matching paint order)
/// whose rect contains [point].
///
/// Returns `null` — no target — when the topmost hit is the dragged node
/// itself or one of its descendants (re-parenting there would create a
/// cycle) or is vetoed by [canReparent]. An invalid topmost hit does NOT
/// fall through to nodes painted beneath it: the pointer is visually over
/// the invalid node, so targeting something hidden behind it would be
/// surprising.
OrgNode<T>? resolveDropTarget<T>({
  required ChartState<T> state,
  required OrgNode<T> dragged,
  required Pt point,
  bool Function(OrgNode<T> node, OrgNode<T> candidateParent)? canReparent,
}) {
  for (var i = state.nodes.length - 1; i >= 0; i--) {
    final n = state.nodes[i];
    final r = n.rect;
    if (point.x < r.left ||
        point.x > r.right ||
        point.y < r.top ||
        point.y > r.bottom) {
      continue;
    }
    // Topmost geometric hit found — validity decides target-or-nothing.
    final excluded = dragged.descendants.any((d) => d.id == n.node.id);
    if (excluded) return null;
    if (canReparent != null && !canReparent(dragged, n.node)) return null;
    return n.node;
  }
  return null;
}
```

(`OrgNode.descendants` yields the node itself first, so the self case needs no separate check.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/drag_reparent_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/widgets/drag_reparent.dart test/widgets/drag_reparent_test.dart
git commit -m "feat: pure drop-target resolution and drag state for re-parenting

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `ChartViewport.enabled` flag

**Files:**
- Modify: `lib/src/widgets/chart_viewport.dart`
- Test: `test/widgets/viewport_test.dart` (append one test)

**Interfaces:**
- Produces: `ChartViewport({..., bool enabled = true})` — when false, pan/pinch/scroll gestures leave the transform untouched. Task 4 passes `enabled: _drag == null`.

- [ ] **Step 1: Write the failing test**

Append to `test/widgets/viewport_test.dart`, following that file's existing harness (it already pumps a `ChartViewport` with a `TransformationController` and drives `startGesture`; mirror the setup of the nearest existing pan test):

```dart
testWidgets('enabled: false ignores pan and scroll', (tester) async {
  final tc = TransformationController();
  await tester.pumpWidget(
    MaterialApp(
      home: ChartViewport(
        transformationController: tc,
        enabled: false,
        child: const SizedBox(width: 2000, height: 2000),
      ),
    ),
  );
  final before = tc.value.clone();
  final g = await tester.startGesture(const Offset(200, 200));
  await g.moveBy(const Offset(80, 40));
  await g.up();
  await tester.pump();
  expect(tc.value, before);
  tc.dispose();
});
```

Note: `ChartViewport` is not exported from `flex_org_chart.dart`; check the top of `viewport_test.dart` — it already imports it via `package:flex_org_chart/src/widgets/chart_viewport.dart` (or adjust the import to that path).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/viewport_test.dart`
Expected: FAIL — no `enabled` parameter (compile error).

- [ ] **Step 3: Implement**

In `chart_viewport.dart`: add the field and guard both input paths.

```dart
  const ChartViewport({
    super.key,
    required this.child,
    required this.transformationController,
    this.scaleExtent = const (0.001, 20.0),
    this.onZoom,
    this.onInteractionStart,
    this.enabled = true,
  });

  /// When false, pan/pinch/scroll gestures are ignored entirely — the
  /// transform can only change programmatically. The owning `OrgChart`
  /// disables the viewport while a drag-to-reparent is in flight so a
  /// second pointer can't pan or zoom under the drag (which would
  /// invalidate the gesture's frozen coordinate transform).
  final bool enabled;
```

In `build`, guard the two entry points (leave the widget tree itself alone so disabling mid-gesture doesn't tear down the detector):

```dart
      onPointerSignal: (event) {
        if (!widget.enabled) return;
        if (event is PointerScrollEvent) { ... existing body ... }
      },
      ...
        onScaleStart: (details) {
          if (!widget.enabled) return;
          ... existing body ...
        },
        onScaleUpdate: (details) {
          if (!widget.enabled) return;
          _composeGesture(details);
        },
```

(`onScaleEnd` keeps its unconditional cleanup — nulling `_gestureStart`/`_focalStart` is correct whether or not the gesture was honored, and it covers a gesture that started enabled and got disabled mid-flight.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/viewport_test.dart`
Expected: PASS (all, including pre-existing).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/widgets/chart_viewport.dart test/widgets/viewport_test.dart
git commit -m "feat: ChartViewport enabled flag to suppress gestures during drags

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Lift and ghost — `onReparent` param, long-press, drag rendering

**Files:**
- Modify: `lib/src/widgets/org_chart.dart`
- Test: `test/widgets/drag_test.dart` (create)

**Interfaces:**
- Consumes: `DragState<T>`, `resolveDropTarget` (Task 2); `ChartViewport.enabled` (Task 3).
- Produces on `OrgChart`: `void Function(OrgNode<T> node, OrgNode<T> newParent)? onReparent`, `bool Function(OrgNode<T> node, OrgNode<T> candidateParent)? canReparent`, `Widget Function(BuildContext, OrgNode<T>)? dropTargetBuilder` (all three params land now; drop/callback behavior is Task 5). Ghost carries `ValueKey('drag-ghost')`; drop-target overlay carries `ValueKey('drop-target-<id>')`.

- [ ] **Step 1: Write the failing tests**

Create `test/widgets/drag_test.dart`:

```dart
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

// a -> (b, c); c -> d. initialExpandLevel: 2 so d is visible from the start.
const rows = <Row>[
  (id: 'a', parentId: null),
  (id: 'b', parentId: 'a'),
  (id: 'c', parentId: 'a'),
  (id: 'd', parentId: 'c'),
];

OrgChartController<Row> makeController([List<Row> data = rows]) =>
    OrgChartController<Row>(
      data: data,
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
      initialExpandLevel: 2,
    );

Widget app(
  OrgChartController<Row> c, {
  void Function(OrgNode<Row>, OrgNode<Row>)? onReparent,
  bool Function(OrgNode<Row>, OrgNode<Row>)? canReparent,
}) => MaterialApp(
  home: Scaffold(
    body: OrgChart<Row>(
      controller: c,
      compact: false,
      nodeSize: (_) => (w: 100, h: 50),
      onReparent: onReparent,
      canReparent: canReparent,
      nodeBuilder: (context, node) =>
          Text('node-${node.id}', key: ValueKey('node-${node.id}')),
    ),
  ),
);

/// Long-presses the center of [key] and returns the still-down gesture.
Future<TestGesture> lift(WidgetTester tester, String key) async {
  final g = await tester.startGesture(
    tester.getCenter(find.byKey(ValueKey(key))),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return g;
}

void main() {
  testWidgets('long-press lifts: ghost appears, original dims', (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c, onReparent: (_, __) {}));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    // The original node's opacity drops to 0.4 (its Positioned wrapper key
    // is 'node-position-d'; the Opacity widget sits inside it).
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('node-position-d')),
        matching: find.byType(Opacity),
      ).first,
    );
    expect(opacity.opacity, closeTo(0.4, 0.01));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('ghost follows the pointer', (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c, onReparent: (_, __) {}));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    final before = tester.getTopLeft(find.byKey(const ValueKey('drag-ghost')));
    await g.moveBy(const Offset(60, -30));
    await tester.pump();
    final after = tester.getTopLeft(find.byKey(const ValueKey('drag-ghost')));
    // Screen-space delta equals pointer delta (scale is uniform; the fitted
    // chart in an 800x600 test surface renders at scale ~1 or below — accept
    // direction and monotonicity rather than exact pixels).
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('onReparent null: long-press produces no ghost (off is off)',
      (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('quick drag on a node still pans the viewport', (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c, onReparent: (_, __) {}));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const ValueKey('node-a')));
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('node-d'))),
    );
    // Move immediately — long-press never wins the arena.
    await g.moveBy(const Offset(50, 50));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byKey(const ValueKey('node-a')));
    expect(after, isNot(equals(before)));
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/drag_test.dart`
Expected: FAIL — `onReparent` is not a parameter (compile error).

- [ ] **Step 3: Implement**

All in `lib/src/widgets/org_chart.dart`.

3a. Imports:

```dart
import 'package:flutter/services.dart' show HapticFeedback;
import 'drag_reparent.dart';
```

3b. Constructor params + fields (dartdoc'd like their neighbors):

```dart
    this.onReparent,
    this.canReparent,
    this.dropTargetBuilder,
```

```dart
  /// Called when the user drops a dragged node onto a valid new parent.
  /// Non-null enables drag-and-drop re-parenting: long-press a node
  /// (~500ms) to lift it, drag, and drop it onto the node that should
  /// become its parent. The chart never mutates data itself — update your
  /// data source here and call [OrgChartController.setData] (which
  /// preserves expansion state by default, so the moved subtree animates
  /// to its new parent). If you do nothing, the chart stays as it was.
  final void Function(OrgNode<T> node, OrgNode<T> newParent)? onReparent;

  /// Optional veto on drop targets, beyond the built-in rule that a node
  /// can never be dropped onto itself or its own descendants. Candidates
  /// failing it are treated exactly like empty space: no highlight while
  /// hovering, and dropping snaps the node back. Only consulted when
  /// [onReparent] is non-null.
  final bool Function(OrgNode<T> node, OrgNode<T> candidateParent)?
  canReparent;

  /// Overrides the overlay drawn on top of the node currently under a
  /// drag when it is a valid drop target. Defaults to a rounded border in
  /// [highlightedLinkStyle]'s color. Only consulted when [onReparent] is
  /// non-null.
  final Widget Function(BuildContext, OrgNode<T>)? dropTargetBuilder;
```

3c. State fields in `_OrgChartState` (next to the existing animation fields), plus lifecycle:

```dart
  /// Non-null while a drag-to-reparent is in flight (or snap-back is
  /// playing). All coordinates in layout space; see drag_reparent.dart.
  DragState<T>? _drag;

  /// Drives the ~150ms ghost snap-back after an invalid drop. Constructed
  /// eagerly in initState for the same disposal-safety reason as
  /// _viewportAnim/_layoutAnim (see their comments).
  late final AnimationController _snapBack;

  /// Where the ghost was released, frozen for the snap-back lerp.
  Offset? _snapFrom;
```

In `initState` (after `_layoutAnim` setup):

```dart
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _snapBack.addListener(() => setState(() {}));
    _snapBack.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _drag = null;
          _snapFrom = null;
        });
      }
    });
```

In `dispose` (before `super.dispose()`): `_snapBack.dispose();`

3d. Drag lifecycle methods on `_OrgChartState`:

```dart
  bool get _dragEnabled => widget.onReparent != null;

  void _startDrag(OrgNode<T> node, LayoutRect rect, Offset localPosition) {
    // Never lift mid layout-animation: rendered positions are mid-lerp and
    // would disagree with the state rects target resolution scans.
    if (!_dragEnabled || _layoutAnim.isAnimating || _snapBack.isAnimating) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _drag = DragState<T>(
        node: node,
        sourceRect: rect,
        grabOffset: localPosition,
        position: Offset(
          rect.left + localPosition.dx,
          rect.top + localPosition.dy,
        ),
      );
    });
  }

  void _updateDrag(Offset localPosition) {
    final drag = _drag;
    if (drag == null || _snapBack.isAnimating) return;
    // localPosition is relative to the dragged node's wrapper, whose
    // layout-space top-left is sourceRect.left/top (Flutter un-transforms
    // pointer coordinates through the viewport's Transform for us).
    final position = Offset(
      drag.sourceRect.left + localPosition.dx,
      drag.sourceRect.top + localPosition.dy,
    );
    final target = resolveDropTarget<T>(
      state: widget.controller.state,
      dragged: drag.node,
      point: (x: position.dx, y: position.dy),
      canReparent: widget.canReparent,
    );
    setState(() {
      _drag = drag.copyWith(
        position: position,
        targetId: target?.id,
        clearTarget: target == null,
      );
    });
  }

  void _endDrag() {
    final drag = _drag;
    if (drag == null || _snapBack.isAnimating) return;
    final targetId = drag.targetId;
    final target = targetId == null
        ? null
        : widget.controller.nodeById(targetId);
    if (target != null) {
      setState(() => _drag = null);
      widget.onReparent?.call(drag.node, target);
    } else {
      // Invalid drop: snap the ghost back to where the node lives.
      _snapFrom = drag.ghostTopLeft;
      _snapBack.forward(from: 0);
    }
  }

  /// Cancels without snap-back: used when the world changes under the
  /// drag (relayout, controller swap, programmatic viewport move) and the
  /// frozen coordinates can no longer be trusted.
  void _cancelDrag() {
    if (_drag == null) return;
    _snapBack.stop();
    setState(() {
      _drag = null;
      _snapFrom = null;
    });
  }
```

3e. Wire cancellation into existing paths:

- `_onChanged`: first line after the `mounted` check — `if (_drag != null) _cancelDrag();`
- `didUpdateWidget`: when `controllerChanged` or `widget.onReparent == null` — `_cancelDrag();`
- `fitBounds`, `centerOn`, `zoomBy` (the `ChartViewportHandle` methods): first line — `_cancelDrag();` (a programmatic viewport change mid-drag invalidates the frozen gesture transform).

3f. Node wrapper: extend the existing per-node `GestureDetector` (inside the `for (final n in merged)` loop). Replace the current `GestureDetector`/`Opacity` composition with:

```dart
              child: IgnorePointer(
                ignoring: n.exiting,
                child: Opacity(
                  opacity:
                      (_drag != null && _drag!.node.id == n.node.id
                              ? 0.4
                              : n.opacity)
                          .clamp(0.0, 1.0),
                  child: GestureDetector(
                    onTap: widget.onNodeTap == null
                        ? null
                        : () => widget.onNodeTap!(n.node),
                    onLongPressStart: !_dragEnabled
                        ? null
                        : (d) => _startDrag(n.node, n.rect, d.localPosition),
                    onLongPressMoveUpdate: !_dragEnabled
                        ? null
                        : (d) => _updateDrag(d.localPosition),
                    onLongPressEnd: !_dragEnabled ? null : (_) => _endDrag(),
                    onLongPressCancel: !_dragEnabled ? null : _cancelDrag,
                    child: widget.nodeBuilder(context, n.node),
                  ),
                ),
              ),
```

(When `_dragEnabled` is false every long-press handler is null, so no recognizer is created — byte-for-byte today's gesture behavior. Note the dim check uses the node id, so it applies to the original while the ghost floats.)

3g. Ghost + drop-target overlay: append to the `children` list of the animated layer's `Stack`, after the node loop:

```dart
          if (_drag != null) ...[
            if (_drag!.targetId != null)
              Builder(
                builder: (context) {
                  final targetLayout = _animNext.byId(_drag!.targetId!);
                  if (targetLayout == null) return const SizedBox.shrink();
                  return Positioned(
                    key: ValueKey('drop-target-${_drag!.targetId}'),
                    left: targetLayout.rect.left + origin.dx,
                    top: targetLayout.rect.top + origin.dy,
                    width: targetLayout.rect.width,
                    height: targetLayout.rect.height,
                    child: IgnorePointer(
                      child:
                          widget.dropTargetBuilder?.call(
                            context,
                            targetLayout.node,
                          ) ??
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: widget.highlightedLinkStyle.color,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                    ),
                  );
                },
              ),
            Positioned(
              key: const ValueKey('drag-ghost'),
              left: _ghostTopLeft.dx + origin.dx,
              top: _ghostTopLeft.dy + origin.dy,
              width: _drag!.sourceRect.width,
              height: _drag!.sourceRect.height,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.7,
                  child: widget.nodeBuilder(context, _drag!.node),
                ),
              ),
            ),
          ],
```

with this helper on `_OrgChartState` (snap-back aware ghost position):

```dart
  /// Ghost top-left in layout space: follows the pointer during the drag,
  /// lerps back to the node's own rect while the snap-back plays.
  Offset get _ghostTopLeft {
    final drag = _drag!;
    final from = _snapFrom;
    if (from == null || !_snapBack.isAnimating && _snapBack.value == 0) {
      return drag.ghostTopLeft;
    }
    final t = Curves.easeOut.transform(_snapBack.value);
    final home = Offset(drag.sourceRect.left, drag.sourceRect.top);
    return Offset.lerp(from, home, t)!;
  }
```

3h. Viewport suppression: in `build`'s `ChartViewport(...)` call, add `enabled: _drag == null,`.

Note on the `Positioned` wrappers in 3g: they must be direct children of the `Stack` — the `Builder` shown above wraps the overlay's *content* lookup, but `Positioned` must stay outermost. Restructure to compute `targetLayout` before the list literal instead:

```dart
        // Above the children list, inside the AnimatedBuilder builder:
        final dragTargetLayout = (_drag?.targetId) == null
            ? null
            : _animNext.byId(_drag!.targetId!);
```

then use `if (dragTargetLayout != null) Positioned(key: ValueKey('drop-target-${_drag!.targetId}'), ...)` directly (no `Builder`), reading `dragTargetLayout.rect`/`.node`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/drag_test.dart`
Expected: PASS (4 tests). Also run the full widget suite to catch regressions: `flutter test test/widgets/` — all pass (especially `org_chart_static_test.dart` and `viewport_test.dart`, which exercise the untouched-when-disabled paths).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/widgets/org_chart.dart test/widgets/drag_test.dart
git commit -m "feat: long-press lift and drag ghost for node re-parenting

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Drop behavior — target highlight, onReparent, veto, snap-back, cancels

The mechanisms were built in Task 4 (`_updateDrag`/`_endDrag`/`_cancelDrag`); this task proves the end-to-end behaviors with widget tests and fixes whatever the tests flush out. Expect the implementation deltas here to be small or zero — the value is the coverage.

**Files:**
- Modify (only if tests fail): `lib/src/widgets/org_chart.dart`
- Test: `test/widgets/drag_test.dart` (append)

**Interfaces:**
- Consumes: everything Task 4 produced; `setData(preserveState:)` from Task 1.

- [ ] **Step 1: Write the failing/verifying tests**

Append to `test/widgets/drag_test.dart` (reuses `rows`, `makeController`, `app`, `lift` from Task 4):

```dart
  testWidgets('drag over a valid target shows the drop overlay', (tester) async {
    final c = makeController();
    await tester.pumpWidget(app(c, onReparent: (_, __) {}));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('node-b'))));
    await tester.pump();
    expect(find.byKey(const ValueKey('drop-target-b')), findsOneWidget);
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('drop on a valid target fires onReparent with the right pair',
      (tester) async {
    final c = makeController();
    (String, String)? fired;
    await tester.pumpWidget(app(
      c,
      onReparent: (node, newParent) => fired = (node.id, newParent.id),
    ));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('node-b'))));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(fired, ('d', 'b'));
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
  });

  testWidgets('app applying the drop via setData animates and preserves view',
      (tester) async {
    var data = List.of(rows);
    final c = makeController(data);
    await tester.pumpWidget(app(c, onReparent: (node, newParent) {
      data = [
        for (final r in data)
          r.id == node.id ? (id: r.id, parentId: newParent.id) : r,
      ];
      c.setData(data);
    }));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('node-b'))));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    // d survived the setData and is now under b.
    expect(c.nodeById('d')!.parent!.id, 'b');
    expect(find.text('node-d'), findsOneWidget);
  });

  testWidgets('drop on own descendant snaps back, no callback', (tester) async {
    final c = makeController();
    var fired = false;
    await tester.pumpWidget(app(c, onReparent: (_, __) => fired = true));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-c'); // c's descendant is d
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('node-d'))));
    await tester.pump();
    expect(find.byKey(const ValueKey('drop-target-d')), findsNothing);
    await g.up();
    await tester.pump();
    expect(fired, isFalse);
    // Ghost still present, snapping back...
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
  });

  testWidgets('drop on empty space snaps back, no callback', (tester) async {
    final c = makeController();
    var fired = false;
    await tester.pumpWidget(app(c, onReparent: (_, __) => fired = true));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    await g.moveBy(const Offset(250, 250)); // off into empty canvas
    await tester.pump();
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(fired, isFalse);
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
  });

  testWidgets('canReparent veto: no overlay, drop snaps back', (tester) async {
    final c = makeController();
    var fired = false;
    await tester.pumpWidget(app(
      c,
      onReparent: (_, __) => fired = true,
      canReparent: (node, candidate) => candidate.id != 'b',
    ));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('node-b'))));
    await tester.pump();
    expect(find.byKey(const ValueKey('drop-target-b')), findsNothing);
    await g.up();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(fired, isFalse);
  });

  testWidgets('setData mid-drag cancels the drag', (tester) async {
    final c = makeController();
    var fired = false;
    await tester.pumpWidget(app(c, onReparent: (_, __) => fired = true));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    expect(find.byKey(const ValueKey('drag-ghost')), findsOneWidget);
    c.setData(const [
      (id: 'a', parentId: null),
      (id: 'b', parentId: 'a'),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
    await g.up();
    await tester.pumpAndSettle();
    expect(fired, isFalse);
  });

  testWidgets('release without movement over self is a silent no-op',
      (tester) async {
    final c = makeController();
    var fired = false;
    await tester.pumpWidget(app(c, onReparent: (_, __) => fired = true));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    await g.up(); // release in place: pointer is over d itself
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(fired, isFalse);
    expect(find.byKey(const ValueKey('drag-ghost')), findsNothing);
  });
```

- [ ] **Step 2: Run the tests**

Run: `flutter test test/widgets/drag_test.dart`
Expected: mostly PASS if Task 4's implementation is faithful. Any failure here is a real bug in Task 4's wiring — debug the specific failing behavior (do not weaken the test to pass). Likely trouble spots: `moveTo` coordinates are screen-space (the transform-aware `localPosition` conversion handles this — if the overlay appears on the wrong node, the grab-offset math in `_updateDrag` is wrong); snap-back timing (the 200ms pump must outlast the 150ms controller).

- [ ] **Step 3: Fix anything the tests flushed out; run the full suite**

Run: `flutter test`
Expected: PASS across the board.

- [ ] **Step 4: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/widgets/org_chart.dart test/widgets/drag_test.dart
git commit -m "test: end-to-end drop, veto, snap-back, and cancel coverage for drag re-parenting

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(If Step 3 changed production code, use `feat:`/`fix:` and describe the fix instead.)

---

### Task 6: Example app wiring, README, CHANGELOG

**Files:**
- Modify: `example/lib/main.dart` (the demo screen holding the `OrgChart` — locate the `OrgChart<...>(` construction and the employee data list; the example keeps its 25-person org in a flat list)
- Modify: `README.md` (feature table row + a short usage snippet)
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `onReparent` (Task 4), `setData` default preservation (Task 1).

- [ ] **Step 1: Wire the example app**

In the example's chart construction, add an `onReparent` handler that mutates the demo employee list and calls `setData`, following the pattern the app already uses for its data (adapt field/ctor names to the example's actual employee type — inspect `example/lib/main.dart` first; the handler must produce a new list where the dragged employee's manager id is the drop target's id):

```dart
  onReparent: (node, newParent) {
    setState(() {
      _employees = [
        for (final e in _employees)
          e.id == node.data.id ? e.copyWith(managerId: newParent.data.id) : e,
      ];
    });
    _controller.setData(_employees);
  },
```

If the example's employee type has no `copyWith`, add one (real, per the repo's standards) or construct the replacement instance explicitly with all fields.

- [ ] **Step 2: Run the example app's checks**

Run: `cd example && flutter analyze && cd ..`
Expected: clean. If the example has tests, run them; otherwise a manual smoke run (`cd example && flutter run -d macos`) is worth doing but not gating.

- [ ] **Step 3: Update README**

- Feature table (`README.md:77-80` area): flip `| Drag-and-drop re-parenting | roadmap | done |` to `| Drag-and-drop re-parenting | done (long-press to lift) | done |` and move the row up with the other done rows (keep the remaining roadmap rows — node editing API, department bounding boxes, image/PDF export — in planned order under it).
- In the usage/example section, add a short snippet after the existing controller example:

````markdown
Drag-and-drop re-parenting is opt-in — provide `onReparent`, apply the
change to your data, and call `setData` (which preserves expansion state
by default, so the moved subtree animates to its new parent):

```dart
OrgChart<Employee>(
  controller: controller,
  nodeBuilder: ...,
  onReparent: (node, newParent) {
    myData = reassignManager(myData, node.id, newParent.id);
    controller.setData(myData);
  },
  // Optional: veto targets beyond the built-in cycle rule.
  canReparent: (node, candidate) => candidate.data.role != 'contractor',
);
```

Long-press (~500ms) lifts a node; a quick drag still pans the canvas.
Dropping on the node's own subtree, on empty space, or on a vetoed
target snaps back and calls nothing.
````

- [ ] **Step 4: Update CHANGELOG**

Add at the top of `CHANGELOG.md`:

```markdown
## 0.2.0

- **Drag-and-drop re-parenting** (opt-in): long-press a node to lift it,
  drop it on its new parent. `OrgChart.onReparent` receives
  `(node, newParent)`; the app applies the change and calls `setData`.
  `OrgChart.canReparent` vetoes targets beyond the built-in
  self/descendant cycle rule; `OrgChart.dropTargetBuilder` customizes the
  valid-target overlay.
- **Behavior change**: `OrgChartController.setData` now preserves
  expansion and highlight state for node ids that survive into the new
  data (`preserveState: true` by default). Pass `preserveState: false`
  for the previous reset-everything behavior.
```

- [ ] **Step 5: Full suite, format, analyze, commit**

```bash
flutter test && dart format . && flutter analyze
git add example README.md CHANGELOG.md
git commit -m "feat(example),docs: wire drag re-parenting into the demo; README + 0.2.0 changelog

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** callback data flow (T4/T5), long-press lift + haptic (T4), ghost inside transform (T4), target highlight + `dropTargetBuilder` (T4/T5), self/descendant rule + veto (T2/T5), snap-back (T4/T5), `setData` `preserveState` (T1), viewport suppression (T3), cancel on relayout/controller swap/programmatic viewport (T4 3e, tested T5), exiting nodes excluded (source: existing `IgnorePointer(ignoring: exiting)`; target: `resolveDropTarget` scans `state.nodes` which never contains exiting nodes), no-movement release (T5), app-ignores-callback contract (doc'd T4 param + README T6). Out of scope per spec: edge auto-pan, hover auto-expand.
- **Deviation from spec, intentional:** coordinate conversion uses gesture-transform-aware `localPosition` instead of manual matrix inversion (see header note); `chartPointFromViewport` from the spec is therefore not built — its correctness burden moves to the "ghost follows pointer" and `moveTo`-based widget tests, which exercise the conversion through a real fitted (scaled) transform.
- **Additional guard not in spec:** lifts are refused while a layout animation or snap-back is in flight (`_startDrag`), because mid-lerp rendered positions disagree with the state rects that target resolution uses.

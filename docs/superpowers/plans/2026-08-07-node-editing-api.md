# Node Editing API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Programmatic `addNode` / `removeNode` / `reparent` / `updateNode` on `OrgChartController`, with a `withParent` write-callback, an `onDataChanged` persistence hook, and a `data` getter — per the approved spec at `docs/superpowers/specs/2026-08-07-node-editing-api-design.md`.

**Architecture:** All changes in `lib/src/controller/org_chart_controller.dart` plus a new controller test file. `setData`'s capture/restore logic is extracted to a private `_applyData`; every op validates fully, builds a new `List<T>`, routes through `_applyData(preserveState: true)`, then fires `onDataChanged`. One mutation path; ops throw before mutating; a thrown op leaves the controller unchanged.

**Tech Stack:** Flutter/Dart, no new dependencies. Tests: `flutter_test` controller unit tests + one widget test.

**Refinement over the spec (error-state editing):** the spec doesn't say what ops do when the controller is already in a data-error state (`dataError != null`, `_tree == null`, `_data` non-empty). Editing a list the controller couldn't stratify is undefined territory — every op throws `StateError('cannot edit while dataError is set; call setData with valid data first')` up front. This follows the spec's "ops can never leave `dataError`" rule to its logical end.

## Global Constraints

- Spec semantics govern: ops throw (`ArgumentError` for bad ids/self/descendant, `StateError` for missing `withParent`, id-changing `withParent`, or the error-state refinement above) **before any mutation**; after a throw there is no relayout, no notify, no `onDataChanged`, `dataError` untouched.
- `reparent` to the current parent is a silent no-op: no relayout, no notify, no `onDataChanged`.
- `onDataChanged` fires only from successful edit ops, never from `setData`; it receives `List.unmodifiable(_data)` — the same view the `data` getter returns.
- Empty-string parent ids are equivalent to null (root) everywhere, matching `stratify`.
- No TODOs, stubs, or placeholders. TDD per task. `dart format .` and `flutter analyze` clean before each commit.
- Commit messages: conventional-commit style with trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- No new public exports from `lib/flex_org_chart.dart` (the controller file is already exported wholesale).
- Every new public member gets dartdoc in the file's existing style.
- New controller tests live in `test/controller/node_editing_test.dart` (new file), NOT appended to the already-large `org_chart_controller_test.dart`.

---

### Task 1: `_applyData` extraction + `data` getter

**Files:**
- Modify: `lib/src/controller/org_chart_controller.dart:163-200` (the `setData` region)
- Test: `test/controller/node_editing_test.dart` (create)

**Interfaces:**
- Consumes: existing `setData(List<T> data, {bool preserveState = true})` body (org_chart_controller.dart:173-200).
- Produces: `void _applyData(List<T> newData, {required bool preserveState})` — private, performs exactly what `setData`'s body does today (capture flags → replace `_data` with `List.of(newData)` → re-stratify → restore by id → `_relayout()`); `List<T> get data => List.unmodifiable(_data);`. Tasks 2-5 call both.

- [ ] **Step 1: Write the failing test**

Create `test/controller/node_editing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

typedef Row = ({String id, String? parentId});

OrgChartController<Row> make(
  List<Row> data, {
  Row Function(Row, String?)? withParent,
  void Function(List<Row>)? onDataChanged,
  int initialExpandLevel = 1,
}) => OrgChartController<Row>(
  data: data,
  idOf: (r) => r.id,
  parentIdOf: (r) => r.parentId,
  initialExpandLevel: initialExpandLevel,
  // withParent / onDataChanged params are added in Tasks 2-3; this helper
  // gains them there. For Task 1, delete these two lines if present.
);

void configure(OrgChartController<Row> c) => c.configure(OrgChartConfig<Row>(
  layout: ChartLayout.top,
  compact: false,
  spacing: const ChartSpacing(),
  nodeSize: (_) => (w: 100, h: 50),
));

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
      expect(() => c.data.add((id: 'x', parentId: null)),
          throwsUnsupportedError);
    });

    test('reflects setData', () {
      final c = make(tree);
      configure(c);
      c.setData(const [(id: 'a', parentId: null)]);
      expect(c.data.map((r) => r.id), ['a']);
    });
  });
}
```

For Task 1, `make` takes only `data` and `initialExpandLevel` (no `withParent`/`onDataChanged` — those params don't exist yet; the helper's signature above shows the final shape so later tasks extend it consistently, but write it WITHOUT those two named params now).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/controller/node_editing_test.dart`
Expected: FAIL — compile error, `data` getter undefined (`The getter 'data' isn't defined`).

- [ ] **Step 3: Implement**

In `org_chart_controller.dart`, replace the current `setData` (lines 165-200) with:

```dart
  /// Replaces the backing data and re-stratifies the tree. If the new data
  /// is malformed, [dataError] is set and [state] becomes an empty
  /// [ChartState] — this method never throws.
  ///
  /// With [preserveState] true (the default), nodes whose ids survive into
  /// the new data keep their expansion and highlight flags; only new ids
  /// get the [initialExpandLevel] rule. Pass false to reset every node's
  /// state exactly as the constructor does — the pre-0.2 behavior.
  void setData(List<T> data, {bool preserveState = true}) =>
      _applyData(data, preserveState: preserveState);

  /// The single mutation path shared by [setData] and the editing ops
  /// ([addNode], [removeNode], [reparent], [updateNode]): capture
  /// expansion/highlight flags, swap the data, re-stratify, restore flags
  /// by surviving id, relayout.
  void _applyData(List<T> newData, {required bool preserveState}) {
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
    _data = List.of(newData);
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

And next to the `connections` getter (org_chart_controller.dart:118-120), add:

```dart
  /// The controller's current backing data, including the result of any
  /// editing ops ([addNode], [removeNode], [reparent], [updateNode]), as
  /// an unmodifiable view. Mutating the list you originally passed in has
  /// no effect — hand changes to [setData] or the editing ops instead.
  List<T> get data => List.unmodifiable(_data);
```

(The editing ops named in these dartdocs are added by Tasks 2-5 in this same plan; the forward references are intentional and resolve within the branch.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/controller/node_editing_test.dart` — PASS.
Run: `flutter test` — full suite green (`setData` behavior is unchanged by the extraction; any failure means the refactor altered behavior — fix the refactor, not the tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/controller/org_chart_controller.dart test/controller/node_editing_test.dart
git commit -m "refactor: extract _applyData mutation path; add data getter

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `addNode` + `onDataChanged`

**Files:**
- Modify: `lib/src/controller/org_chart_controller.dart` (constructor + new `---- editing ----` section after `setData`)
- Test: `test/controller/node_editing_test.dart` (extend)

**Interfaces:**
- Consumes: `_applyData` and `data` (Task 1).
- Produces: constructor param `void Function(List<T> data)? onDataChanged` (field `this.onDataChanged`); `void addNode(T item)`; private validation helpers used by Tasks 3-5:
  - `void _assertEditable()` — throws `StateError` when `_dataError != null`.
  - `OrgNode<T> _requireNode(String id)` — returns the node or throws `ArgumentError('no node with id "<id>"')`.
  - `bool _isRootId(String? id)` — `id == null || id.isEmpty`.
  - `void _notifyDataChanged()` — `onDataChanged?.call(data);`.

- [ ] **Step 1: Write the failing tests**

Update `make` in `test/controller/node_editing_test.dart` to accept and forward `onDataChanged` (add the named param to the helper and pass it through to the constructor). Then append:

```dart
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
      expect(() => c.addNode((id: 'b', parentId: 'a')),
          throwsArgumentError);
      expect(c.data.length, 4);
      expect(notified, 0);
      expect(changed, isNull);
    });

    test('unknown parent id throws ArgumentError and changes nothing', () {
      final c = make(tree);
      configure(c);
      expect(() => c.addNode((id: 'e', parentId: 'ghost')),
          throwsArgumentError);
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
      expect(() => c.addNode((id: 'e', parentId: null)),
          throwsStateError);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/controller/node_editing_test.dart`
Expected: FAIL — compile error (`onDataChanged` not a constructor param, `addNode` undefined).

- [ ] **Step 3: Implement**

Constructor (org_chart_controller.dart:77-85): add param + field:

```dart
  OrgChartController({
    required List<T> data,
    required this.idOf,
    required this.parentIdOf,
    this.initialExpandLevel = 1,
    List<Connection> connections = const [],
    this.onDataChanged,
  }) : _data = List.of(data),
       _connections = List.of(connections);
```

```dart
  /// Called after every successful editing op ([addNode], [removeNode],
  /// [reparent], [updateNode]) with the new backing list — the same
  /// unmodifiable view [data] returns. The persistence hook: save here
  /// and every programmatic or drag-driven edit reaches your backend.
  /// Never fired by [setData]; the app initiated that change itself.
  final void Function(List<T> data)? onDataChanged;
```

New `// ---- editing ----` section directly after `setData`/`_applyData`:

```dart
  // ---- editing ----

  /// Adds [item] to the chart. Its parent (per [parentIdOf]) must already
  /// exist; a `null`/empty parent id adds a new root. The new node follows
  /// normal visibility rules — it is hidden if its parent is collapsed
  /// (the parent is not auto-expanded).
  ///
  /// Throws [ArgumentError] if [item]'s id already exists or its parent id
  /// is unknown; throws [StateError] if the controller is in a data-error
  /// state ([dataError] non-null). On throw, nothing changes.
  void addNode(T item) {
    _assertEditable();
    final id = idOf(item);
    if (_tree?.nodeById(id) != null || _data.any((e) => idOf(e) == id)) {
      throw ArgumentError('a node with id "$id" already exists');
    }
    final parentId = parentIdOf(item);
    if (!_isRootId(parentId) && _tree?.nodeById(parentId!) == null) {
      throw ArgumentError('parent id "$parentId" does not exist');
    }
    _applyData([..._data, item], preserveState: true);
    _notifyDataChanged();
  }

  void _assertEditable() {
    if (_dataError != null) {
      throw StateError(
        'cannot edit while dataError is set; call setData with valid data '
        'first',
      );
    }
  }

  OrgNode<T> _requireNode(String id) {
    final node = _tree?.nodeById(id);
    if (node == null) throw ArgumentError('no node with id "$id"');
    return node;
  }

  bool _isRootId(String? id) => id == null || id.isEmpty;

  void _notifyDataChanged() => onDataChanged?.call(data);
```

(`_requireNode` is unused until Task 3 lands in the same branch; if `flutter analyze` flags it as unused, move its introduction to Task 3 instead and note that in the commit message — do not suppress the lint.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/controller/node_editing_test.dart` — PASS. Then `flutter test` — full suite green.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/controller/org_chart_controller.dart test/controller/node_editing_test.dart
git commit -m "feat: addNode editing op and onDataChanged persistence hook

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `reparent` + `withParent`

**Files:**
- Modify: `lib/src/controller/org_chart_controller.dart` (constructor + editing section)
- Test: `test/controller/node_editing_test.dart` (extend)

**Interfaces:**
- Consumes: `_applyData`, `_assertEditable`, `_requireNode`, `_isRootId`, `_notifyDataChanged` (Tasks 1-2).
- Produces: constructor param `T Function(T item, String? newParentId)? withParent` (field `this.withParent`); `void reparent(String id, String? newParentId)`; private helpers used by Tasks 4-5:
  - `T Function(T, String?) _requireWithParent()` — returns the callback or throws `StateError`.
  - `T _reparented(T item, String? newParentId)` — applies `withParent` and enforces the id-stability contract (throws `StateError` if the result's id differs).
  - `void _assertValidNewParent(OrgNode<T> node, String? newParentId)` — throws `ArgumentError` when non-root `newParentId` is unknown, or is `node` itself or any of its descendants.

- [ ] **Step 1: Write the failing tests**

Update `make` to accept and forward `withParent`. Reusable fixture callback for records:

```dart
Row rowWithParent(Row r, String? p) => (id: r.id, parentId: p);
```

Append:

```dart
  group('reparent', () {
    test('moves a subtree and preserves its expansion', () {
      List<Row>? changed;
      final c = make(tree,
          withParent: rowWithParent, onDataChanged: (d) => changed = d);
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
      final c = make(tree,
          withParent: rowWithParent, onDataChanged: (d) => changed = d);
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
      final c = make(tree,
          withParent: (r, p) => (id: '${r.id}-oops', parentId: p));
      configure(c);
      expect(() => c.reparent('b', 'c'), throwsStateError);
      expect(c.nodeById('b'), isNotNull);
      expect(c.nodeById('b-oops'), isNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/controller/node_editing_test.dart`
Expected: FAIL — compile error (`withParent` not a param, `reparent` undefined).

- [ ] **Step 3: Implement**

Constructor: add `this.withParent,` after `this.onDataChanged,`. Field:

```dart
  /// Returns a copy of [item] with its parent id replaced by
  /// `newParentId` (`null` meaning "make it a root"). Required by
  /// [reparent] and by [removeNode]'s child promotion — the controller
  /// treats `T` as opaque and cannot write the parent id itself. The
  /// returned item must keep its id; changing it throws [StateError] at
  /// the call site.
  final T Function(T item, String? newParentId)? withParent;
```

Editing section additions:

```dart
  /// Moves the node with [id] (and its whole subtree) under
  /// [newParentId], or makes it a root when [newParentId] is `null` or
  /// empty. Re-parenting a node onto its current parent is a silent
  /// no-op. Expansion/highlight state survives (same ids).
  ///
  /// Throws [StateError] if [withParent] was not provided (or if the
  /// controller is in a data-error state); throws [ArgumentError] for an
  /// unknown [id], an unknown non-null [newParentId], or when
  /// [newParentId] is [id] itself or any of its descendants (which would
  /// create a cycle). On throw, nothing changes.
  void reparent(String id, String? newParentId) {
    _assertEditable();
    _requireWithParent();
    final node = _requireNode(id);
    final currentParentId = parentIdOf(node.data);
    final normalizedNew = _isRootId(newParentId) ? null : newParentId;
    final normalizedCurrent =
        _isRootId(currentParentId) ? null : currentParentId;
    if (normalizedNew == normalizedCurrent) return; // silent no-op
    _assertValidNewParent(node, normalizedNew);
    final newData = [
      for (final e in _data)
        idOf(e) == id ? _reparented(e, normalizedNew) : e,
    ];
    _applyData(newData, preserveState: true);
    _notifyDataChanged();
  }

  T Function(T, String?) _requireWithParent() {
    final f = withParent;
    if (f == null) {
      throw StateError(
        'this operation needs the withParent callback: pass '
        'OrgChartController(withParent: ...) so the controller can write '
        'a new parent id into your data items',
      );
    }
    return f;
  }

  T _reparented(T item, String? newParentId) {
    final result = _requireWithParent()(item, newParentId);
    if (idOf(result) != idOf(item)) {
      throw StateError(
        'withParent must not change the item id: got '
        '"${idOf(result)}" for "${idOf(item)}"',
      );
    }
    return result;
  }

  void _assertValidNewParent(OrgNode<T> node, String? newParentId) {
    if (newParentId == null) return;
    if (_tree?.nodeById(newParentId) == null) {
      throw ArgumentError('parent id "$newParentId" does not exist');
    }
    if (node.descendants.any((d) => d.id == newParentId)) {
      throw ArgumentError(
        'cannot make "$newParentId" the parent of "${node.id}": it is '
        '"${node.id}" itself or one of its descendants',
      );
    }
  }
```

(Validation runs before list building: `_reparented` is only reached after `_assertValidNewParent` passes, so an id-contract `StateError` from `_reparented` still happens before `_applyData` — nothing has mutated.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/controller/node_editing_test.dart` — PASS. Then `flutter test` — green.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/controller/org_chart_controller.dart test/controller/node_editing_test.dart
git commit -m "feat: reparent editing op with withParent write-callback

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `removeNode` with child promotion

**Files:**
- Modify: `lib/src/controller/org_chart_controller.dart` (editing section)
- Test: `test/controller/node_editing_test.dart` (extend)

**Interfaces:**
- Consumes: `_assertEditable`, `_requireNode`, `_isRootId`, `_reparented`, `_applyData`, `_notifyDataChanged` (Tasks 1-3).
- Produces: `void removeNode(String id)`.

- [ ] **Step 1: Write the failing tests**

```dart
  group('removeNode', () {
    test('leaf removal needs no withParent', () {
      List<Row>? changed;
      final c = make(tree, onDataChanged: (d) => changed = d);
      configure(c);
      c.removeNode('d');
      expect(c.nodeById('d'), isNull);
      expect(c.data.length, 3);
      expect(changed!.any((r) => r.id == 'd'), isFalse);
    });

    test('mid-tree removal promotes children to the grandparent', () {
      final c = make(tree, withParent: rowWithParent);
      configure(c);
      c.removeNode('c'); // d promotes to a
      expect(c.nodeById('d')!.parent!.id, 'a');
      expect(c.data.length, 3);
    });

    test('root removal promotes children to roots', () {
      final c = make(tree, withParent: rowWithParent);
      configure(c);
      c.removeNode('a');
      expect(c.nodeById('b')!.parent, isNull);
      expect(c.nodeById('c')!.parent, isNull);
      expect(c.nodeById('d')!.parent!.id, 'c'); // grandchildren untouched
    });

    test('promoted children keep their expansion state', () {
      final c = make(tree, withParent: rowWithParent);
      configure(c);
      c.expand('c'); // d visible
      c.removeNode('a');
      expect(c.nodeById('c')!.isExpanded, isTrue);
      expect(c.state.byId('d'), isNotNull);
    });

    test('removal with children but no withParent throws StateError', () {
      final c = make(tree);
      configure(c);
      expect(() => c.removeNode('c'), throwsStateError);
      expect(c.nodeById('c'), isNotNull);
      expect(c.data.length, 4);
    });

    test('unknown id throws ArgumentError', () {
      final c = make(tree);
      configure(c);
      expect(() => c.removeNode('ghost'), throwsArgumentError);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/controller/node_editing_test.dart`
Expected: FAIL — compile error, `removeNode` undefined.

- [ ] **Step 3: Implement**

```dart
  /// Removes the node with [id]. Its direct children are promoted to the
  /// removed node's parent (via [withParent]); removing a root promotes
  /// its children to roots. Deeper descendants are untouched. The removed
  /// id's expansion/highlight state vanishes with it; promoted children
  /// keep theirs.
  ///
  /// Throws [ArgumentError] on an unknown [id]; throws [StateError] if
  /// the node has children and [withParent] was not provided (a leaf
  /// removes fine without it), or if the controller is in a data-error
  /// state. On throw, nothing changes.
  void removeNode(String id) {
    _assertEditable();
    final node = _requireNode(id);
    final childIds = {for (final child in node.children) child.id};
    if (childIds.isNotEmpty) _requireWithParent();
    final rawParentId = parentIdOf(node.data);
    final promotedParentId = _isRootId(rawParentId) ? null : rawParentId;
    final newData = [
      for (final e in _data)
        if (idOf(e) != id)
          childIds.contains(idOf(e)) ? _reparented(e, promotedParentId) : e,
    ];
    _applyData(newData, preserveState: true);
    _notifyDataChanged();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/controller/node_editing_test.dart` — PASS. Then `flutter test` — green.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/controller/org_chart_controller.dart test/controller/node_editing_test.dart
git commit -m "feat: removeNode editing op with child promotion

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `updateNode`

**Files:**
- Modify: `lib/src/controller/org_chart_controller.dart` (editing section)
- Test: `test/controller/node_editing_test.dart` (extend)

**Interfaces:**
- Consumes: `_assertEditable`, `_requireNode`, `_isRootId`, `_assertValidNewParent`, `_applyData`, `_notifyDataChanged` (Tasks 1-3).
- Produces: `void updateNode(T item)`.

- [ ] **Step 1: Write the failing tests**

The `Row` record has no mutable payload, so give the test file a richer local record for this group:

```dart
  group('updateNode', () {
    // (id, parentId, name) — name is the editable payload.
    List<({String id, String? parentId, String name})> named() => const [
      (id: 'a', parentId: null, name: 'Ada'),
      (id: 'b', parentId: 'a', name: 'Bob'),
      (id: 'c', parentId: 'a', name: 'Cal'),
      (id: 'd', parentId: 'c', name: 'Dee'),
    ];
    OrgChartController<({String id, String? parentId, String name})> makeNamed({
      void Function(List<({String id, String? parentId, String name})>)?
          onDataChanged,
    }) {
      final c = OrgChartController(
        data: named(),
        idOf: (r) => r.id,
        parentIdOf: (r) => r.parentId,
        onDataChanged: onDataChanged,
      );
      c.configure(OrgChartConfig(
        layout: ChartLayout.top,
        compact: false,
        spacing: const ChartSpacing(),
        nodeSize: (_) => (w: 100, h: 50),
      ));
      return c;
    }

    test('replaces the payload in place', () {
      List<({String id, String? parentId, String name})>? changed;
      final c = makeNamed(onDataChanged: (d) => changed = d);
      c.updateNode((id: 'b', parentId: 'a', name: 'Bobby'));
      expect(c.nodeById('b')!.data.name, 'Bobby');
      expect(c.nodeById('b')!.parent!.id, 'a');
      expect(changed!.firstWhere((r) => r.id == 'b').name, 'Bobby');
    });

    test('combined update+reparent is honored and validated', () {
      final c = makeNamed();
      c.updateNode((id: 'd', parentId: 'b', name: 'Dee'));
      expect(c.nodeById('d')!.parent!.id, 'b');
      // Cycle via updateNode is rejected like reparent:
      expect(
        () => c.updateNode((id: 'c', parentId: 'd', name: 'Cal')),
        throwsArgumentError,
      );
    });

    test('expansion and highlight survive an update', () {
      final c = makeNamed();
      c.expand('c');
      c.highlight('c');
      c.updateNode((id: 'c', parentId: 'a', name: 'Calvin'));
      expect(c.nodeById('c')!.isExpanded, isTrue);
      expect(c.nodeById('c')!.isHighlighted, isTrue);
    });

    test('unknown id throws ArgumentError, nothing changes', () {
      final c = makeNamed();
      expect(
        () => c.updateNode((id: 'ghost', parentId: null, name: 'X')),
        throwsArgumentError,
      );
      expect(c.data.length, 4);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/controller/node_editing_test.dart`
Expected: FAIL — compile error, `updateNode` undefined.

- [ ] **Step 3: Implement**

```dart
  /// Replaces the item whose id matches [item]'s id, wholesale. If the
  /// replacement's parent id (per [parentIdOf]) differs from the current
  /// one, that is honored — a combined update+reparent. [withParent] is
  /// not needed: the caller already wrote the parent id into [item].
  /// Expansion/highlight state survives (same id).
  ///
  /// Throws [ArgumentError] on an unknown id, or — when the parent id
  /// changed — for the same invalid new parents [reparent] rejects
  /// (unknown, itself, or one of its descendants); throws [StateError]
  /// in a data-error state. On throw, nothing changes.
  void updateNode(T item) {
    _assertEditable();
    final id = idOf(item);
    final node = _requireNode(id);
    final currentParentId = parentIdOf(node.data);
    final newParentId = parentIdOf(item);
    final normalizedNew = _isRootId(newParentId) ? null : newParentId;
    final normalizedCurrent =
        _isRootId(currentParentId) ? null : currentParentId;
    if (normalizedNew != normalizedCurrent) {
      _assertValidNewParent(node, normalizedNew);
    }
    final newData = [
      for (final e in _data) idOf(e) == id ? item : e,
    ];
    _applyData(newData, preserveState: true);
    _notifyDataChanged();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/controller/node_editing_test.dart` — PASS. Then `flutter test` — green.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/controller/org_chart_controller.dart test/controller/node_editing_test.dart
git commit -m "feat: updateNode editing op with combined update+reparent

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: DnD delegation, example app, README, CHANGELOG, version

**Files:**
- Modify: `example/lib/main.dart` (controller construction ~line 60-95 and the `onReparent` handler at ~line 241)
- Modify: `test/widgets/drag_test.dart` (append one test)
- Modify: `README.md`, `CHANGELOG.md`, `pubspec.yaml`
- Test: `test/widgets/drag_test.dart`

**Interfaces:**
- Consumes: `reparent`, `withParent`, `onDataChanged` (Task 3); the drag test file's existing `rows`/`makeController`/`app`/`lift` helpers.

- [ ] **Step 1: Write the failing widget test**

Append to `test/widgets/drag_test.dart` (its `makeController` does not pass `withParent`; construct a dedicated controller inline):

```dart
  testWidgets('drag-and-drop delegating to controller.reparent works',
      (tester) async {
    List<Row>? saved;
    final c = OrgChartController<Row>(
      data: rows,
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
      initialExpandLevel: 2,
      withParent: (r, p) => (id: r.id, parentId: p),
      onDataChanged: (d) => saved = d,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrgChart<Row>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          onReparent: (node, newParent) =>
              c.reparent(node.id, newParent.id),
          nodeBuilder: (context, node) =>
              Text('node-${node.id}', key: ValueKey('node-${node.id}')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final g = await lift(tester, 'node-d');
    await g.moveTo(tester.getCenter(find.byKey(const ValueKey('node-b'))));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(c.nodeById('d')!.parent!.id, 'b');
    expect(saved!.firstWhere((r) => r.id == 'd').parentId, 'b');
    c.dispose();
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/drag_test.dart`
Expected: FAIL — compile error only if Tasks 2-3 are incomplete; with them landed this test should PASS immediately. If it passes, that IS the green step (the failing-first requirement is satisfied by Tasks 2-3's own RED phases; this test is integration coverage). If it fails for a real reason, debug before proceeding.

- [ ] **Step 3: Rewire the example app**

In `example/lib/main.dart`:
- Controller construction gains:

```dart
      withParent: (e, newManagerId) =>
          Employee(e.id, newManagerId, e.name, e.title),
      onDataChanged: (data) => _employees = List.of(data),
```

(Keep `_employees` in sync so layout-direction rebuilds and future edits observe the same list the controller has.)
- Replace the `onReparent` handler body (currently list surgery + `setData`) with:

```dart
                onReparent: (node, newParent) {
                  controller.reparent(node.id, newParent.id);
                  _setStatus(
                    'Moved ${node.data.name} to report to '
                    '${newParent.data.name}.',
                  );
                },
```

Run: `cd example && flutter analyze && cd ..` — clean. (If `onDataChanged` assigning `_employees` outside `setState` trips the analyzer or feels off: wrap in `setState` — the field feeds rebuild paths.)

- [ ] **Step 4: README, CHANGELOG, version**

- README: flip `| Node editing (add/remove/re-parent via API) | roadmap | done |` to `| Node editing (add/remove/re-parent via API) | done | done |` and move it above the roadmap rows (department bounding boxes, image/PDF export stay in order). After the drag-and-drop snippet, add:

````markdown
Programmatic editing goes through the controller — every op animates and
fires `onDataChanged` for persistence:

```dart
final controller = OrgChartController<Employee>(
  data: employees,
  idOf: (e) => e.id,
  parentIdOf: (e) => e.managerId,
  withParent: (e, id) => e.copyWith(managerId: id), // enables reparent/promotion
  onDataChanged: (data) => api.save(data),
);

controller.addNode(newHire);          // parent must exist
controller.reparent('7', '2');        // cycle-safe; drag-drop can delegate here
controller.removeNode('4');           // children promote to the grandparent
controller.updateNode(renamedPerson); // same id, new payload
```
````

- CHANGELOG, new top section:

```markdown
## 0.3.0

- **Node editing API**: `addNode`, `removeNode` (children promote to the
  removed node's parent), `reparent` (cycle-safe), and `updateNode` on
  `OrgChartController`, plus a `data` getter. Ops validate up front and
  throw (`ArgumentError`/`StateError`) before mutating anything; every
  successful edit animates like a drag-drop confirmation.
- **New controller callbacks**: `withParent` teaches the controller to
  write a parent id into your items (required by `reparent` and child
  promotion); `onDataChanged` fires after every successful edit with the
  new list — the persistence hook. `setData` never fires it.
- The example app's drag-and-drop now delegates to
  `controller.reparent(...)` — one line instead of hand-rolled list
  surgery.
```

- `pubspec.yaml`: `version: 0.3.0`.

- [ ] **Step 5: Full suite, format, analyze, commit**

```bash
flutter test && dart format . && flutter analyze
git add example test/widgets/drag_test.dart README.md CHANGELOG.md pubspec.yaml
git commit -m "feat(example),docs: delegate drag-drop to reparent; node-editing docs; 0.3.0

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** `withParent` (T3), `onDataChanged` incl. never-from-setData (T2), `data` getter (T1), `addNode` semantics+errors (T2), `removeNode` promotion incl. root→roots and leaf-without-callback (T4), `reparent` incl. null→root, silent no-op, cycle rule, id-contract (T3), `updateNode` incl. combined update+reparent validation (T5), single mutation path `_applyData` (T1), error-state refinement (T2, `_assertEditable`, used by all ops), DnD one-liner + example + docs + 0.3.0 (T6). Widget test for DnD→reparent (T6). Controller-unchanged-after-throw asserted in T2 (add) and T3 (reparent); T4/T5 assert data unchanged.
- **Type consistency:** helper names `_assertEditable` / `_requireNode` / `_isRootId` / `_notifyDataChanged` (T2), `_requireWithParent` / `_reparented` / `_assertValidNewParent` (T3) — used with those exact names in T3/T4/T5. `_applyData(List<T>, {required bool preserveState})` consistent across T1-T5.
- **Known interaction:** `reparent` calls `_requireWithParent()` up front (fail fast even for a would-be no-op — StateError beats silently returning), then again inside `_reparented`; harmless double-check, single behavior.

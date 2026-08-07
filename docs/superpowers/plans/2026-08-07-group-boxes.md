# Department Bounding Boxes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Styled, labeled boxes drawn behind declared subtrees ("departments"), animating with the chart — per the approved spec at `docs/superpowers/specs/2026-08-07-group-boxes-design.md`.

**Architecture:** `ChartGroup`/`GroupBoxStyle` models (new file), a pure `computeGroupHulls` function (new file), a `GroupBoxPainter` (new file) painted as the bottom-most child of the existing animated layer, fed the same merged (lerped) node rects the nodes render at. Controller gains a `groups` list mirroring `connections`; widget gains a `groupBoxStyle` default.

**Tech Stack:** Flutter/Dart, no new dependencies.

**Refinements over the spec (pattern corrections, verified against the code):**
1. The spec said dash validation "throws at construction". `GroupBoxStyle` must be a const constructor (like every style class here), and a const constructor cannot run a per-element list check — this is exactly why `ConnectionStyle` validates at *paint time*, falling back to a solid line (see `connection_painter.dart:26-29,113-133`). `GroupBoxStyle.dash` mirrors that exact contract: invalid pattern (empty list or any entry ≤ 0) → solid border at paint time, documented on the field. The dash-walk logic is extracted to a shared `dashedPath(Path, List<double>)` in `path_builder.dart` (Task 3) so the guard exists once, not twice.
2. The spec said `ChartGroup` gets "value ==/hashCode like Connection" — but `Connection` has none; painters rely on stable instance identity (`connection_painter.dart:216-222`). `ChartGroup` mirrors `Connection` (plain immutable, no `==`); `GroupBoxStyle` mirrors `ConnectionStyle` (value equality, needed for `shouldRepaint`).
3. `computeGroupHulls` takes a `nodeById` lookup callback rather than an `OrgTree` (the spec's sketch) — the controller already exposes `nodeById`, and the function needs nothing else from the tree.
4. `chart_group.dart` lives in `model/` (the controller declares groups, like connections) but — unlike the deliberately pure `connection.dart` — it imports `dart:ui`/`flutter/painting` for `Color`/`TextStyle`, because the user-approved API puts a per-group `GroupBoxStyle` override on `ChartGroup`. This is a knowing deviation: only `geometry.dart` carries a hard no-`dart:ui` rule (the layout engine must run without Flutter), and the controller is already Flutter-dependent via `foundation.dart`. Reviewers: this is intentional, decided at plan time.

## Global Constraints

- Spec semantics govern: box = hull of the group root + all currently *visible* members' rects, inflated by the group's effective padding; collapsed root → root-only box; root absent from the frame's rects → no box; unknown `rootId` → silently skipped; nested groups both draw, outer (shallower `rootDepth`) painted first; labels never truncate (overflow documented); hulls computed from the animated layer's merged rects so boxes animate, including shrinking during exit animations.
- No TODOs, stubs, or placeholders. TDD per task (compile error counts as RED). `dart format .` and `flutter analyze` clean before each commit.
- Commit messages: conventional-commit style with trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- New public exports from `lib/flex_org_chart.dart`: `ChartGroup`, `GroupBoxStyle` only. Dartdoc every public member in the file's existing style.
- Version bump to 0.4.0 ships with the CHANGELOG in the docs task (Task 5), not separately.

---

### Task 1: `ChartGroup` + `GroupBoxStyle` models

**Files:**
- Create: `lib/src/model/chart_group.dart`
- Modify: `lib/flex_org_chart.dart` (add export)
- Test: `test/widgets/group_boxes_test.dart` (create; hull/painter/widget tests accumulate here in later tasks)

**Interfaces:**
- Produces: `class ChartGroup { const ChartGroup({required String rootId, String? label, GroupBoxStyle? style}); }` (plain immutable, no `==`); `class GroupBoxStyle { const GroupBoxStyle({Color fill = const Color(0x14808080), Color borderColor = const Color(0xFF9E9E9E), double borderWidth = 1.5, double borderRadius = 12, double padding = 16, TextStyle? labelStyle, List<double>? dash}); }` with value `==`/`hashCode`. Tasks 2-4 consume both.

- [ ] **Step 1: Write the failing tests**

Create `test/widgets/group_boxes_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flex_org_chart/flex_org_chart.dart';

void main() {
  group('GroupBoxStyle', () {
    test('value equality', () {
      const a = GroupBoxStyle(borderColor: Color(0xFF112233), dash: [4, 2]);
      const b = GroupBoxStyle(borderColor: Color(0xFF112233), dash: [4, 2]);
      const c = GroupBoxStyle(borderColor: Color(0xFF112233), dash: [4, 3]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('defaults are the documented ones', () {
      const s = GroupBoxStyle();
      expect(s.fill, const Color(0x14808080));
      expect(s.borderColor, const Color(0xFF9E9E9E));
      expect(s.borderWidth, 1.5);
      expect(s.borderRadius, 12);
      expect(s.padding, 16);
      expect(s.labelStyle, isNull);
      expect(s.dash, isNull);
    });
  });

  group('ChartGroup', () {
    test('holds rootId, label, and optional style override', () {
      const g = ChartGroup(
        rootId: '3',
        label: 'Engineering',
        style: GroupBoxStyle(padding: 24),
      );
      expect(g.rootId, '3');
      expect(g.label, 'Engineering');
      expect(g.style!.padding, 24);
      expect(const ChartGroup(rootId: 'x').label, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/group_boxes_test.dart`
Expected: FAIL — compile error, `GroupBoxStyle`/`ChartGroup` undefined.

- [ ] **Step 3: Implement**

Create `lib/src/model/chart_group.dart`:

```dart
import 'dart:ui';

import 'package:flutter/painting.dart' show TextStyle;

/// A user-declared department: the node with [rootId] plus all of its
/// currently visible descendants, drawn with a styled bounding box behind
/// the chart (see `GroupBoxPainter`). Declared via
/// `OrgChartController.groups`, mirroring how `Connection`s are declared.
class ChartGroup {
  /// Creates a group rooted at the node with id [rootId], optionally
  /// labeled and optionally styled (overriding the `OrgChart` widget's
  /// default `groupBoxStyle`).
  const ChartGroup({required this.rootId, this.label, this.style});

  /// Id of the group's root node, matching whatever `idOf` returns for
  /// it. A group whose root id matches no node is silently skipped.
  final String rootId;

  /// Optional text painted at the box's top-left. Never truncated: a
  /// label wider than its box overflows the box edge.
  final String? label;

  /// Optional style override for this group's box. `null` uses the
  /// `OrgChart` widget's `groupBoxStyle`.
  final GroupBoxStyle? style;
}

/// Visual style for a department bounding box: a rounded, optionally
/// dashed outline with a translucent fill and a top-left label.
class GroupBoxStyle {
  /// Creates a group-box style.
  const GroupBoxStyle({
    this.fill = const Color(0x14808080),
    this.borderColor = const Color(0xFF9E9E9E),
    this.borderWidth = 1.5,
    this.borderRadius = 12,
    this.padding = 16,
    this.labelStyle,
    this.dash,
  });

  /// Fill color painted inside the box, under the chart's nodes and
  /// links. Defaults to a translucent gray wash.
  final Color fill;

  /// Stroke color of the box outline.
  final Color borderColor;

  /// Stroke width of the box outline.
  final double borderWidth;

  /// Corner radius of the box outline and fill.
  final double borderRadius;

  /// Inflation applied to the hull of the group's member rects, on all
  /// four sides, in layout units.
  final double padding;

  /// Text style for the group's `ChartGroup.label`. Defaults to a 12px
  /// label in [borderColor] when `null`.
  final TextStyle? labelStyle;

  /// On/off segment lengths for a dashed outline, in logical pixels, or
  /// `null` for a solid outline. Entries must be positive; a pattern
  /// that is empty or contains a zero/negative entry cannot be validated
  /// here (const constructor) and falls back to a solid outline at paint
  /// time instead of dashing — the same contract as
  /// `ConnectionStyle.dash`.
  final List<double>? dash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupBoxStyle &&
          runtimeType == other.runtimeType &&
          fill == other.fill &&
          borderColor == other.borderColor &&
          borderWidth == other.borderWidth &&
          borderRadius == other.borderRadius &&
          padding == other.padding &&
          labelStyle == other.labelStyle &&
          _dashEquals(dash, other.dash);

  @override
  int get hashCode => Object.hash(
    fill,
    borderColor,
    borderWidth,
    borderRadius,
    padding,
    labelStyle,
    dash == null ? null : Object.hashAll(dash!),
  );
}

bool _dashEquals(List<double>? a, List<double>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

In `lib/flex_org_chart.dart`, after the `connection.dart` export line, add:

```dart
export 'src/model/chart_group.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/group_boxes_test.dart` — PASS. Then `flutter test` — full suite green.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/model/chart_group.dart lib/flex_org_chart.dart test/widgets/group_boxes_test.dart
git commit -m "feat: ChartGroup and GroupBoxStyle models for department boxes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `computeGroupHulls`

**Files:**
- Create: `lib/src/widgets/group_hulls.dart`
- Test: `test/widgets/group_boxes_test.dart` (append)

**Interfaces:**
- Consumes: `ChartGroup`/`GroupBoxStyle` (Task 1); `OrgNode<T>.descendants`/`.depth` (`lib/src/model/org_node.dart`); `LayoutRect` (`lib/src/model/geometry.dart`); `stratify` (exported, used by tests to build trees).
- Produces (Tasks 3-4 rely on these exact shapes):
  - `class GroupHull { const GroupHull({required ChartGroup group, required LayoutRect rect, required int rootDepth}); }`
  - `List<GroupHull> computeGroupHulls<T>({required List<ChartGroup> groups, required Map<String, LayoutRect> memberRects, required OrgNode<T>? Function(String) nodeById, required double Function(ChartGroup) paddingOf})` — returns hulls sorted outer-first (ascending `rootDepth`).

- [ ] **Step 1: Write the failing tests**

Append to `test/widgets/group_boxes_test.dart` (add imports at the top of the file: `import 'package:flex_org_chart/src/widgets/group_hulls.dart';`):

```dart
  group('computeGroupHulls', () {
    // NOTE: `typedef R = ({String id, String? parentId});` goes at the TOP
    // LEVEL of the test file (Dart forbids typedefs inside functions); it
    // is shown here only for reference and is reused by the Task 4 tests.

    // a -> (b, c); c -> d
    OrgTree<R> tree() => stratify<R>(
      data: const [
        (id: 'a', parentId: null),
        (id: 'b', parentId: 'a'),
        (id: 'c', parentId: 'a'),
        (id: 'd', parentId: 'c'),
      ],
      idOf: (r) => r.id,
      parentIdOf: (r) => r.parentId,
    );

    LayoutRect r100(double left, double top) => LayoutRect(left, top, 100, 50);

    test('hull unions visible member rects and inflates by padding', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [ChartGroup(rootId: 'c', label: 'C-team')],
        memberRects: {
          'a': r100(0, 0),
          'b': r100(-150, 100),
          'c': r100(150, 100),
          'd': r100(150, 200),
        },
        nodeById: t.nodeById,
        paddingOf: (_) => 10,
      );
      expect(hulls, hasLength(1));
      final h = hulls.single.rect;
      // Union of c (150,100,100,50) and d (150,200,100,50) = (150,100,100,150),
      // inflated by 10 on all sides:
      expect(h.left, 140);
      expect(h.top, 90);
      expect(h.width, 120);
      expect(h.height, 170);
    });

    test('collapsed root: only the root rect is in memberRects → root-only box',
        () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [ChartGroup(rootId: 'c')],
        memberRects: {'a': r100(0, 0), 'b': r100(-150, 100), 'c': r100(150, 100)},
        nodeById: t.nodeById,
        paddingOf: (_) => 10,
      );
      expect(hulls.single.rect.left, 140);
      expect(hulls.single.rect.height, 70); // 50 + 2*10
    });

    test('root not in memberRects → no hull', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [ChartGroup(rootId: 'c')],
        memberRects: {'a': r100(0, 0)},
        nodeById: t.nodeById,
        paddingOf: (_) => 10,
      );
      expect(hulls, isEmpty);
    });

    test('unknown rootId is silently skipped', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [ChartGroup(rootId: 'ghost'), ChartGroup(rootId: 'a')],
        memberRects: {'a': r100(0, 0)},
        nodeById: t.nodeById,
        paddingOf: (_) => 0,
      );
      expect(hulls, hasLength(1));
      expect(hulls.single.group.rootId, 'a');
    });

    test('nested groups sort outer (shallower root) first', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [ChartGroup(rootId: 'c'), ChartGroup(rootId: 'a')],
        memberRects: {
          'a': r100(0, 0),
          'b': r100(-150, 100),
          'c': r100(150, 100),
          'd': r100(150, 200),
        },
        nodeById: t.nodeById,
        paddingOf: (_) => 0,
      );
      expect(hulls.map((h) => h.group.rootId), ['a', 'c']);
      expect(hulls.first.rootDepth, 0);
      expect(hulls.last.rootDepth, 1);
    });

    test('per-group padding via paddingOf', () {
      final t = tree();
      final hulls = computeGroupHulls<R>(
        groups: const [
          ChartGroup(rootId: 'b', style: GroupBoxStyle(padding: 30)),
          ChartGroup(rootId: 'c'),
        ],
        memberRects: {'b': r100(-150, 100), 'c': r100(150, 100), 'd': r100(150, 200)},
        nodeById: t.nodeById,
        paddingOf: (g) => g.style?.padding ?? 5,
      );
      final byId = {for (final h in hulls) h.group.rootId: h.rect};
      expect(byId['b']!.left, -180); // -150 - 30
      expect(byId['c']!.left, 145); // 150 - 5
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/group_boxes_test.dart`
Expected: FAIL — compile error, `group_hulls.dart` missing.

- [ ] **Step 3: Implement**

Create `lib/src/widgets/group_hulls.dart`:

```dart
import '../model/chart_group.dart';
import '../model/geometry.dart';
import '../model/org_node.dart';

/// A [ChartGroup] resolved against one frame's node rects: the padded
/// bounding box to paint, plus the root's depth for outer-before-inner
/// paint ordering.
class GroupHull {
  /// Creates a resolved hull for [group].
  const GroupHull({
    required this.group,
    required this.rect,
    required this.rootDepth,
  });

  /// The declared group this hull was computed for.
  final ChartGroup group;

  /// The padded union of the group's member rects, in layout space.
  final LayoutRect rect;

  /// Depth of the group's root node (root = 0). Hulls are sorted
  /// ascending on this so outer boxes paint before (beneath) inner ones.
  final int rootDepth;
}

/// Resolves [groups] against one frame's [memberRects] (node id → that
/// frame's rect — during layout animations these are the lerped rects, so
/// hulls animate with the nodes).
///
/// Per group: the root is looked up via [nodeById] (unknown id → skipped);
/// a root with no rect this frame (hidden behind a collapsed ancestor and
/// not animating) produces no hull; otherwise the hull is the union of
/// every member rect present in [memberRects] — the root plus visible
/// descendants — inflated by [paddingOf] on all sides. Exiting nodes still
/// present in the frame's rects are included, which is what makes a
/// collapsing department's box shrink with its members.
///
/// Returned hulls are sorted outer-first (ascending root depth) so nested
/// boxes paint inner-on-top-of-outer.
List<GroupHull> computeGroupHulls<T>({
  required List<ChartGroup> groups,
  required Map<String, LayoutRect> memberRects,
  required OrgNode<T>? Function(String) nodeById,
  required double Function(ChartGroup) paddingOf,
}) {
  final hulls = <GroupHull>[];
  for (final g in groups) {
    final root = nodeById(g.rootId);
    if (root == null) continue;
    if (!memberRects.containsKey(root.id)) continue;
    double? left, top, right, bottom;
    for (final n in root.descendants) {
      final r = memberRects[n.id];
      if (r == null) continue;
      if (left == null || r.left < left) left = r.left;
      if (top == null || r.top < top) top = r.top;
      if (right == null || r.right > right) right = r.right;
      if (bottom == null || r.bottom > bottom) bottom = r.bottom;
    }
    // The containsKey check above guarantees at least the root contributed.
    final pad = paddingOf(g);
    hulls.add(
      GroupHull(
        group: g,
        rect: LayoutRect(
          left! - pad,
          top! - pad,
          (right! - left) + pad * 2,
          (bottom! - top) + pad * 2,
        ),
        rootDepth: root.depth,
      ),
    );
  }
  hulls.sort((a, b) => a.rootDepth.compareTo(b.rootDepth));
  return hulls;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/group_boxes_test.dart` — PASS. Then `flutter test` — green.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/widgets/group_hulls.dart test/widgets/group_boxes_test.dart
git commit -m "feat: pure group-hull computation for department boxes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: shared `dashedPath` + `GroupBoxPainter`

**Files:**
- Create: `lib/src/widgets/group_box_painter.dart`
- Modify: `lib/src/widgets/path_builder.dart` (add shared `dashedPath`)
- Modify: `lib/src/widgets/connection_painter.dart:100-133` (delegate `dashPath` to the shared function)
- Test: `test/widgets/group_boxes_test.dart` (append)

**Interfaces:**
- Consumes: `GroupHull` (Task 2), `GroupBoxStyle`/`ChartGroup` (Task 1).
- Produces:
  - `Path dashedPath(Path source, List<double> dash)` in `path_builder.dart` — same contract as today's `ConnectionPainter.dashPath` (invalid pattern → returns `source` unchanged).
  - `class GroupBoxPainter extends CustomPainter { GroupBoxPainter({required List<GroupHull> hulls, required GroupBoxStyle defaultStyle, required Offset origin}); }` — resolves each hull's style as `hull.group.style ?? defaultStyle`; paints fill then border (dashed when `dash` is a valid pattern) then label. Task 4 constructs it.

- [ ] **Step 1: Write the failing tests**

Append to `test/widgets/group_boxes_test.dart` (imports: `import 'package:flex_org_chart/src/widgets/group_box_painter.dart';` and `import 'package:flex_org_chart/src/widgets/path_builder.dart';` plus `import 'dart:ui' as ui;` if needed):

```dart
  group('dashedPath', () {
    Path line() => Path()
      ..moveTo(0, 0)
      ..lineTo(100, 0);

    test('valid pattern produces multiple contours', () {
      final dashed = dashedPath(line(), const [10, 10]);
      expect(dashed.computeMetrics().length, greaterThan(1));
    });

    test('empty or non-positive patterns fall back to the source path', () {
      // Regression guard shared with ConnectionPainter: a zero entry must
      // not hang the dash walk (see connections_test.dart 'invalid dash
      // patterns').
      for (final bad in [<double>[], <double>[0], <double>[5, -1]]) {
        final result = dashedPath(line(), bad);
        expect(result.computeMetrics().single.length, 100);
      }
    });
  });

  group('GroupBoxPainter', () {
    GroupHull hull({GroupBoxStyle? style, String? label}) => GroupHull(
      group: ChartGroup(rootId: 'x', label: label, style: style),
      rect: const LayoutRect(10, 20, 200, 100),
      rootDepth: 0,
    );

    test('resolves per-group style over the default', () {
      const override = GroupBoxStyle(borderColor: Color(0xFF123456));
      final p = GroupBoxPainter(
        hulls: [hull(style: override)],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      expect(p.styleFor(p.hulls.single), override);
      final q = GroupBoxPainter(
        hulls: [hull()],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      expect(q.styleFor(q.hulls.single), const GroupBoxStyle());
    });

    test('shouldRepaint on hull rect, origin, or default style change', () {
      final a = GroupBoxPainter(
        hulls: [hull()],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      final same = GroupBoxPainter(
        hulls: [hull()],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      // Same group instances are NOT used here (hull() builds fresh
      // ChartGroups), so repaint is expected; identical lists are not.
      final moved = GroupBoxPainter(
        hulls: [
          GroupHull(
            group: a.hulls.single.group,
            rect: const LayoutRect(0, 0, 5, 5),
            rootDepth: 0,
          ),
        ],
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      expect(moved.shouldRepaint(a), isTrue);
      final identicalHulls = GroupBoxPainter(
        hulls: a.hulls,
        defaultStyle: const GroupBoxStyle(),
        origin: Offset.zero,
      );
      expect(identicalHulls.shouldRepaint(a), isFalse);
      expect(
        GroupBoxPainter(
          hulls: a.hulls,
          defaultStyle: const GroupBoxStyle(),
          origin: const Offset(9, 9),
        ).shouldRepaint(a),
        isTrue,
      );
      // `same` shares no hull instances with `a`, but rects and groups
      // compare by value/identity respectively; group instances differ →
      // conservative repaint is acceptable and expected:
      expect(same.shouldRepaint(a), isTrue);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/group_boxes_test.dart`
Expected: FAIL — compile error (`dashedPath`, `GroupBoxPainter` undefined).

- [ ] **Step 3: Implement**

3a. In `lib/src/widgets/path_builder.dart`, append (import `dart:math` as needed):

```dart
/// Rebuilds [source] as a dashed path: walks each contour's metrics and
/// alternately keeps/drops [dash]-length segments. A contour with zero
/// length contributes nothing — `metric.length == 0` short-circuits the
/// walk immediately, so this never spins or divides by zero.
///
/// Invalid dash patterns ([dash] empty, or containing a zero/negative
/// entry) return [source] unchanged — a solid line. Style constructors
/// are const and cannot validate; without this guard a zero entry makes
/// the walk a no-op that never terminates, hanging the render thread on
/// first paint (regression tests: 'invalid dash patterns' in
/// connections_test.dart, 'dashedPath' in group_boxes_test.dart).
Path dashedPath(Path source, List<double> dash) {
  if (dash.isEmpty || dash.any((len) => len <= 0)) {
    return source;
  }
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    var draw = true;
    var i = 0;
    while (d < metric.length) {
      final len = dash[i % dash.length];
      final end = math.min(d + len, metric.length);
      if (draw) out.addPath(metric.extractPath(d, end), Offset.zero);
      d += len;
      draw = !draw;
      i++;
    }
  }
  return out;
}
```

(`path_builder.dart` currently imports only `dart:ui` — add `import 'dart:math' as math;`. `Offset` is in `dart:ui`.)

3b. In `connection_painter.dart`, replace `dashPath`'s body with a delegation, keeping the `@visibleForTesting` method and trimming its doc to point at the shared function:

```dart
  /// Delegates to [dashedPath] with this style's pattern — see that
  /// function for the dash walk and the invalid-pattern (solid-line)
  /// fallback contract, which regression tests in connections_test.dart
  /// pin through this method.
  @visibleForTesting
  Path dashPath(Path source) => dashedPath(source, style.dash);
```

Add `import 'path_builder.dart';` and remove the now-unused `dart:math` import if nothing else in the file uses it (`_arrowHead` does use `math` — keep it).

3c. Create `lib/src/widgets/group_box_painter.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../model/chart_group.dart';
import '../model/geometry.dart';
import 'group_hulls.dart';
import 'path_builder.dart';

/// Paints department bounding boxes — one rounded, optionally dashed,
/// labeled box per [GroupHull] — beneath the chart's links and nodes.
/// [hulls] arrive sorted outer-first (see [computeGroupHulls]), so nested
/// boxes naturally paint inner-on-top-of-outer.
///
/// Uses the same [origin] translation convention as `EdgePainter` and
/// `ConnectionPainter`: hull rects come in raw layout-bounds space and are
/// shifted here onto the widget's (0,0)-origin canvas.
class GroupBoxPainter extends CustomPainter {
  GroupBoxPainter({
    required this.hulls,
    required this.defaultStyle,
    required this.origin,
  });

  final List<GroupHull> hulls;
  final GroupBoxStyle defaultStyle;
  final Offset origin;

  /// The effective style for [hull]: its group's override or [defaultStyle].
  @visibleForTesting
  GroupBoxStyle styleFor(GroupHull hull) => hull.group.style ?? defaultStyle;

  /// Label inset from the hull's top-left corner.
  static const _labelInset = Offset(10, 6);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    for (final hull in hulls) {
      final style = styleFor(hull);
      final r = hull.rect;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left, r.top, r.width, r.height),
        Radius.circular(style.borderRadius),
      );
      canvas.drawRRect(rrect, Paint()..color = style.fill);
      final border = Paint()
        ..color = style.borderColor
        ..strokeWidth = style.borderWidth
        ..style = PaintingStyle.stroke;
      final dash = style.dash;
      if (dash == null) {
        canvas.drawRRect(rrect, border);
      } else {
        // Invalid patterns fall back to the source path (solid) inside
        // dashedPath — same contract as ConnectionStyle.dash.
        canvas.drawPath(dashedPath(Path()..addRRect(rrect), dash), border);
      }
      final label = hull.group.label;
      if (label != null) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style:
                style.labelStyle ??
                TextStyle(color: style.borderColor, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(r.left + _labelInset.dx, r.top + _labelInset.dy),
        );
        tp.dispose();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GroupBoxPainter oldDelegate) {
    if (oldDelegate.defaultStyle != defaultStyle ||
        oldDelegate.origin != origin) {
      return true;
    }
    final a = oldDelegate.hulls;
    final b = hulls;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      // Group instances are stable across rebuilds (the controller never
      // recreates its ChartGroup list entries), so identity is a cheap,
      // correct proxy — same reasoning as ConnectionPainter.shouldRepaint.
      if (!identical(a[i].group, b[i].group) ||
          !_rectEquals(a[i].rect, b[i].rect)) {
        return true;
      }
    }
    return false;
  }
}

bool _rectEquals(LayoutRect x, LayoutRect y) =>
    x.left == y.left &&
    x.top == y.top &&
    x.width == y.width &&
    x.height == y.height;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/group_boxes_test.dart` — PASS. Then `flutter test` — full suite green (the `connections_test.dart` invalid-dash regression tests now exercise the shared `dashedPath` through the delegating `dashPath` — they must stay green untouched).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/widgets/group_box_painter.dart lib/src/widgets/path_builder.dart lib/src/widgets/connection_painter.dart test/widgets/group_boxes_test.dart
git commit -m "feat: GroupBoxPainter; extract shared dashedPath from ConnectionPainter

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: controller `groups` + widget wiring

**Files:**
- Modify: `lib/src/controller/org_chart_controller.dart` (constructor + getter, next to `connections` at :86,:117,:139-141)
- Modify: `lib/src/widgets/org_chart.dart` (param + animated-layer wiring around :740-780)
- Test: `test/widgets/group_boxes_test.dart` (append widget tests)

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: `OrgChartController({..., List<ChartGroup> groups = const []})` with `List<ChartGroup> get groups` (unmodifiable); `OrgChart({..., GroupBoxStyle groupBoxStyle = const GroupBoxStyle()})`; the group-box `CustomPaint` is the FIRST child of the animated layer's Stack.

- [ ] **Step 1: Write the failing widget tests**

Append to `test/widgets/group_boxes_test.dart`:

```dart
  group('OrgChart group boxes', () {
    OrgChartController<R> makeChart({List<ChartGroup> groups = const []}) =>
        OrgChartController<R>(
          data: const [
            (id: 'a', parentId: null),
            (id: 'b', parentId: 'a'),
            (id: 'c', parentId: 'a'),
            (id: 'd', parentId: 'c'),
          ],
          idOf: (r) => r.id,
          parentIdOf: (r) => r.parentId,
          initialExpandLevel: 2,
          groups: groups,
        );

    Widget app(OrgChartController<R> c, {GroupBoxStyle? style}) => MaterialApp(
      home: Scaffold(
        body: OrgChart<R>(
          controller: c,
          compact: false,
          nodeSize: (_) => (w: 100, h: 50),
          groupBoxStyle: style ?? const GroupBoxStyle(),
          nodeBuilder: (context, node) =>
              Text('node-${node.id}', key: ValueKey('node-${node.id}')),
        ),
      ),
    );

    GroupBoxPainter painterOf(WidgetTester tester) {
      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((p) => p.painter is GroupBoxPainter);
      return paints.single.painter! as GroupBoxPainter;
    }

    testWidgets('declared group renders one hull, painted beneath nodes',
        (tester) async {
      final c = makeChart(groups: const [
        ChartGroup(rootId: 'c', label: 'C-team'),
      ]);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      final p = painterOf(tester);
      expect(p.hulls, hasLength(1));
      expect(p.hulls.single.group.rootId, 'c');
      // Bottom-most: the group-box CustomPaint is the first child of the
      // animated layer's Stack.
      final stack = tester.widget<Stack>(
        find.ancestor(
          of: find.byWidget(
            tester
                .widgetList<CustomPaint>(find.byType(CustomPaint))
                .firstWhere((w) => w.painter is GroupBoxPainter),
          ),
          matching: find.byType(Stack),
        ).first,
      );
      expect(
        ((stack.children.first as Positioned).child as CustomPaint).painter,
        isA<GroupBoxPainter>(),
      );
    });

    testWidgets('collapsing the root ancestor removes the hull',
        (tester) async {
      final c = makeChart(groups: const [ChartGroup(rootId: 'c')]);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      expect(painterOf(tester).hulls, hasLength(1));
      c.collapse('a'); // c hidden behind collapsed a
      await tester.pumpAndSettle();
      expect(painterOf(tester).hulls, isEmpty);
    });

    testWidgets('hull shrinks when collapsing inside the group',
        (tester) async {
      final c = makeChart(groups: const [ChartGroup(rootId: 'c')]);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      final before = painterOf(tester).hulls.single.rect.height;
      c.collapse('c'); // d leaves; box should end at root-only height
      await tester.pumpAndSettle();
      final after = painterOf(tester).hulls.single.rect.height;
      expect(after, lessThan(before));
    });

    testWidgets('per-group style override wins over the widget default',
        (tester) async {
      const override = GroupBoxStyle(borderColor: Color(0xFFAA0000));
      final c = makeChart(groups: const [
        ChartGroup(rootId: 'c', style: override),
      ]);
      await tester.pumpWidget(app(c));
      await tester.pumpAndSettle();
      final p = painterOf(tester);
      expect(p.styleFor(p.hulls.single), override);
    });
  });
```

(The `R` typedef from the Task 2 tests is reused; ensure it is top-level in the file.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widgets/group_boxes_test.dart`
Expected: FAIL — compile error (`groups` not a controller param, `groupBoxStyle` not a widget param).

- [ ] **Step 3: Implement**

3a. Controller (`org_chart_controller.dart`) — constructor param after `connections`, field after `_connections`, getter after `connections`:

```dart
    List<ChartGroup> groups = const [],
```
```dart
  }) : _data = List.of(data),
       _connections = List.of(connections),
       _groups = List.of(groups);
```
```dart
  final List<ChartGroup> _groups;
```
```dart
  /// The declared department groups, as passed to the constructor. Each
  /// is drawn as a bounding box behind its root node and visible
  /// descendants — see `ChartGroup`.
  List<ChartGroup> get groups => List.unmodifiable(_groups);
```

Add `import '../model/chart_group.dart';`. Extend the constructor dartdoc's parameter list mention (one clause: "and [groups] declares department bounding boxes drawn behind subtrees").

3b. Widget (`org_chart.dart`) — constructor param + field:

```dart
    this.groupBoxStyle = const GroupBoxStyle(),
```
```dart
  /// Default style for department bounding boxes declared via
  /// [OrgChartController.groups]. A [ChartGroup.style] overrides this
  /// per group. Boxes are painted beneath links and nodes and animate
  /// with layout changes.
  final GroupBoxStyle groupBoxStyle;
```

Imports: `import '../model/chart_group.dart';`, `import 'group_box_painter.dart';`, `import 'group_hulls.dart';`.

Inside the `AnimatedBuilder` builder, after `final merged = _mergedNodes();` (org_chart.dart:743) and before the `children` list, add:

```dart
        // Hulls from the SAME merged (lerped) rects the nodes render at,
        // so boxes stretch/glide with layout animations — including
        // shrinking as exiting members retreat during a collapse.
        final groupHulls = computeGroupHulls<T>(
          groups: controller.groups,
          memberRects: {for (final n in merged) n.node.id: n.rect},
          nodeById: controller.nodeById,
          paddingOf: (g) => (g.style ?? widget.groupBoxStyle).padding,
        );
```

Then make the group-box paint the FIRST entry of the `children` list, above the existing `EdgePainter` entry:

```dart
        final children = <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: GroupBoxPainter(
                hulls: groupHulls,
                defaultStyle: widget.groupBoxStyle,
                origin: origin,
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: EdgePainter(
                // ... existing EdgePainter args unchanged ...
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widgets/group_boxes_test.dart` — PASS. Then `flutter test` — FULL suite green (drag, animation, viewport, connections, controller suites must be unaffected).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format . && flutter analyze
git add lib/src/controller/org_chart_controller.dart lib/src/widgets/org_chart.dart test/widgets/group_boxes_test.dart
git commit -m "feat: department bounding boxes wired into controller and chart

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: example app, README, CHANGELOG, version

**Files:**
- Modify: `example/lib/main.dart` (controller construction — add two groups over real subtree roots)
- Modify: `README.md`, `CHANGELOG.md`, `pubspec.yaml`

**Interfaces:**
- Consumes: `ChartGroup`/`GroupBoxStyle` (Task 1), controller `groups` (Task 4).

- [ ] **Step 1: Wire the example app**

Inspect `example/lib/main.dart`'s employee list and pick two managers with multi-person subtrees (mid-level managers, not the CEO — the box should visibly wrap a department, not the whole chart; the demo org is 25 people across 4 levels). Add to the controller construction:

```dart
      groups: [
        ChartGroup(rootId: '<manager-a-id>', label: '<their team name>'),
        ChartGroup(
          rootId: '<manager-b-id>',
          label: '<their team name>',
          style: const GroupBoxStyle(
            borderColor: Color(0xFF7C4DFF),
            fill: Color(0x117C4DFF),
            dash: [8, 6],
          ),
        ),
      ],
```

Replace `<manager-a-id>`/`<manager-b-id>`/labels with real ids and sensible department names derived from the data (e.g. the subtree under the engineering-titled manager). Run `cd example && flutter analyze && cd ..` — clean.

- [ ] **Step 2: README**

- Flip `| Department bounding boxes (group nodes by subtree) | roadmap | — |` to `| Department bounding boxes (group nodes by subtree) | done | — |` and move it up with the done rows (image/PDF export stays the only roadmap row).
- After the node-editing snippet, add:

````markdown
Department bounding boxes draw a labeled box behind any subtree — declare
groups on the controller, style them on the widget (or per group):

```dart
OrgChartController<Employee>(
  data: employees,
  idOf: (e) => e.id,
  parentIdOf: (e) => e.managerId,
  groups: [
    ChartGroup(rootId: '3', label: 'Engineering'),
    ChartGroup(rootId: '7', label: 'Design',
        style: GroupBoxStyle(dash: [8, 6])),
  ],
);
```

Boxes wrap the root and its currently visible descendants, shrink and
grow as you collapse/expand within the department, and animate with
every layout change. d3-org-chart has no equivalent.
````

- [ ] **Step 3: CHANGELOG + version**

CHANGELOG, new top section:

```markdown
## 0.4.0

- **Department bounding boxes**: declare `groups:
  [ChartGroup(rootId: ..., label: ..., style: ...)]` on the controller
  and a labeled, styled box is painted behind that node and its visible
  descendants — beneath links and nodes, animating with layout changes
  (including shrinking as a collapsing department's members retreat).
  Styled via `GroupBoxStyle` (fill, border, corner radius, padding,
  label style, optional dash) with per-group overrides; nested groups
  paint outer-first. No d3-org-chart equivalent.
- Internal: the dash-walk (with its invalid-pattern solid-line guard) is
  now shared between `ConnectionPainter` and the new `GroupBoxPainter`
  as `dashedPath`.
```

`pubspec.yaml`: `version: 0.4.0`.

- [ ] **Step 4: Full verification and commit**

```bash
flutter test && dart format . && flutter analyze
cd example && flutter analyze && cd ..
git add example README.md CHANGELOG.md pubspec.yaml
git commit -m "feat(example),docs: department bounding boxes in demo; README + 0.4.0

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** models + exports (T1), hull semantics — visible members, collapsed root, hidden root, unknown id, nesting order, per-group padding (T2), painter — fill/border/dash/label, outer-first painting via pre-sorted hulls, origin convention, shouldRepaint (T3), controller `groups` like `connections` + widget default style + bottom-most placement + animated hulls from merged rects incl. exit shrink (T4, with widget tests for beneath-nodes order, ancestor collapse, shrink, style override), example/README/CHANGELOG/0.4.0 (T5). Label overflow is doc-only (T1 dartdoc) per spec.
- **Spec refinements** (header): paint-time dash fallback instead of constructor throw (const-constructor reality, matches ConnectionStyle); no value equality on ChartGroup (matches Connection identity-based repaint checks); `nodeById` callback instead of OrgTree param.
- **Type consistency:** `GroupHull{group, rect, rootDepth}` and `computeGroupHulls({groups, memberRects, nodeById, paddingOf})` used identically in T2/T3/T4; `GroupBoxPainter({hulls, defaultStyle, origin})` + `styleFor` in T3/T4; `dashedPath(Path, List<double>)` in T3 only.
- **Known risk:** the T4 paint-order test reaches into the Stack's first child — if the assertion proves brittle against `find.ancestor` ordering, asserting `stack.children.first` contains the `GroupBoxPainter` paint is the intent; implementers may simplify the finder as long as the first-child assertion stands.

# Drag-and-drop re-parenting — design

Feature #1 of the post-0.1.0 roadmap. Lets a user long-press a node, drag
it, and drop it onto another node to make that node its new parent. The
chart never mutates data itself: it reports the intended re-parent to the
app, which applies it to its own data and calls `setData`.

## Decisions (settled during brainstorming)

| Question | Decision |
| --- | --- |
| Who updates the data on drop? | App: chart fires `onReparent(node, newParent)`; app updates its data (and backend) then calls `setData`. Mirrors d3-org-chart's `onNodeDrop`. |
| How does a drag start? | Long-press (~500ms) lifts the node. A quick drag on a node still pans the canvas. |
| Drop feedback | Ghost of the node follows the pointer; the valid target under the pointer gets a highlight overlay. Invalid targets get nothing; dropping there snaps back silently. |
| Opt-in / veto | Off unless `onReparent` is provided. Optional `canReparent(node, candidateParent)` predicate vetoes targets beyond the built-in self/descendant cycle rule. |
| Implementation | Custom drag in chart coordinates (Approach B): long-press recognizer + `TransformationController` matrix inversion + ghost rendered inside the transformed Stack + rect-scan target resolution against `ChartState`. Not Flutter `Draggable`/`DragTarget`, whose Overlay-based ghost escapes the chart's zoom transform. |

## Public API

Three additions to `OrgChart`, none to `OrgChartController`'s data model:

```dart
OrgChart<T>(
  // Enables drag-and-drop when non-null. Fired on a valid drop. The chart
  // changes nothing itself — the app updates its data and calls setData().
  void Function(OrgNode<T> node, OrgNode<T> newParent)? onReparent,

  // Optional veto beyond the built-in self/descendant rule. Targets
  // failing it never highlight; drops on them snap back.
  bool Function(OrgNode<T> node, OrgNode<T> candidateParent)? canReparent,

  // Optional. Drawn on top of the node currently under the drag when it
  // is a valid target. Default: rounded border in the highlight color.
  Widget Function(BuildContext, OrgNode<T>)? dropTargetBuilder,
)
```

The drag ghost is the node's own `nodeBuilder` output at ~70% opacity.
No separate ghost builder in v1; one can be added later without breaking
anything.

### `setData` gains `preserveState`

`OrgChartController.setData` today re-stratifies and resets every node's
expansion to `initialExpandLevel`, which would collapse the chart after
every drop. New signature:

```dart
void setData(List<T> data, {bool preserveState = true})
```

With `preserveState: true` (the default — a deliberate behavior change),
nodes whose ids survive keep their expansion and highlight flags; new ids
get the initial-expand rule. `preserveState: false` reproduces today's
full reset. Because surviving ids keep their identity, the existing
layout-transition animation makes the dropped subtree glide to its new
parent with no extra work.

## Interaction flow

**Lift.** When `onReparent` is non-null, each node's wrapper gains a
long-press recognizer. Winning the gesture arena via long-press is what
coexists with panning: quick drags pan, holding claims the pointer. On
lift: `HapticFeedback.selectionClick`, the original node dims to ~40%
opacity in place, and the ghost appears at the node's position inside the
transformed Stack (zoom-correct by construction).

**Drag.** Each pointer update inverts the `TransformationController`
matrix (including the layout-bounds origin shift and expand-button
reserve) to get chart-space coordinates, moves the ghost, and re-resolves
the drop target: the topmost visible node rect containing the pointer
(when rects overlap, "topmost" = painted last, i.e. latest in
`ChartState.nodes` order),
excluding the dragged node and its entire subtree, then `canReparent` if
provided. A resolved target renders the `dropTargetBuilder` overlay.
Viewport pan/zoom is suppressed for the duration of the drag.

**Drop.**
- Valid target → `onReparent(node, newParent)` fires; ghost removed;
  dimmed original restores. If the app calls `setData`, the
  preserved-state relayout animates the move; if not, the chart stays
  as it was (documented contract).
- Empty space, self, descendant, or vetoed node → no callback; ghost
  animates back to the node's origin over ~150ms.
- Gesture cancel (system interruption, pointer lost) → same snap-back.

**Out of scope for v1** (decisions, not oversights): edge auto-pan while
dragging, and auto-expanding a collapsed target on hover. Both additive
later.

## Components & wiring

Pure logic in standalone files, gesture plumbing in the widget — the
package's existing pattern (`viewport_math.dart` vs `chart_viewport.dart`).

**New: `lib/src/widgets/drag_reparent.dart`** — no widgets, fully
unit-testable:
- `chartPointFromViewport(Matrix4 transform, Offset viewportPoint, ...)`
  — matrix inversion plus the same origin shift `_shifted` applies.
- `resolveDropTarget<T>({state, draggedId, chartPoint, canReparent})` —
  rect scan with self/subtree exclusion and veto; returns `OrgNode<T>?`.
- Immutable `DragState<T>` (dragged node, chart-space position, current
  target id) so the widget holds one nullable field.

**`org_chart.dart`** (~150 lines): `DragState<T>? _drag` field;
long-press recognizer on the existing per-node `GestureDetector` (only
when `onReparent != null`); ghost + drop-target overlay appended to the
animated-layer Stack; a dragging flag passed to `ChartViewport`;
snap-back driven by a third short `AnimationController`.

**`chart_viewport.dart`** (small): accept a flag that suppresses
pan/zoom while a drag is in flight.

**`org_chart_controller.dart`** (small): `setData` captures
`{id: (isExpanded, isHighlighted, isOnHighlightedPath)}` before
discarding the old tree, re-stratifies, re-applies by id.

Layout engine, painters, and models are untouched; the drag layer talks
to the layout pipeline only through `ChartState` rects it already
exposes.

## Edge cases

- **Release without movement**: pointer is over the dragged node itself
  → invalid → silent snap-back, no callback. Long-press alone is never a
  re-parent.
- **Data changes mid-drag** (external `setData`, expansion change): the
  drag cancels immediately — ghost removed, no snap-back animation, no
  callback. Stale rects must never resolve a drop.
- **Controller swap or `onReparent` becoming null mid-drag**: same
  cancel path. `dispose` mid-drag disposes the snap-back controller like
  the other two.
- **Exiting nodes** (`exiting: true` mid-animation): excluded as both
  drag sources and drop targets.
- **Roots**: draggable like any node. A single-root chart's root has no
  valid non-descendant targets, so every drop snaps back — correct by
  construction, no special case.
- **App ignores `onReparent`**: chart stays as-is. Documented contract.

## Testing

**Unit — `drag_reparent_test.dart`**: `chartPointFromViewport` under
identity / panned / zoomed / combined matrices including the origin
shift; `resolveDropTarget` for hit, miss, self, deep descendant, veto,
overlapping rects (topmost wins), exiting-node exclusion.

**Unit — `controller_test.dart` additions**: `preserveState: true` keeps
expansion/highlights for surviving ids and applies initial-expand to new
ids; `preserveState: false` reproduces today's reset.

**Widget — `drag_test.dart`** (`WidgetTester.startGesture` + timed
holds): long-press lifts (ghost appears, original dims); drag over valid
target shows `dropTargetBuilder`; release fires `onReparent` with the
right pair; release over descendant/empty fires nothing and snaps back;
`canReparent` veto never highlights; mid-drag `setData` cancels.
Regressions: quick drag on a node still pans the viewport; with
`onReparent: null` behavior is identical to today's (no recognizers
added).

**Example app**: wire `onReparent` to mutate the demo employee list and
call `setData`, exercising the full loop.

## Roadmap context

Post-0.1.0 order (user-decided 2026-08-06): 1) this feature,
2) node editing API (add/remove/re-parent programmatically),
3) department bounding box (new — group nodes visually by subtree),
4) image/PDF export. Pagination was dropped from the roadmap entirely.

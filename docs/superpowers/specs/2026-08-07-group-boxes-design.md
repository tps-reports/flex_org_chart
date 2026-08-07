# Department bounding boxes — design

Feature #3 of the roadmap (README row: "Department bounding boxes (group
nodes by subtree)"). Draws a styled, labeled box behind each declared
subtree ("department"), animating with the chart. No d3-org-chart
equivalent — this is a flex_org_chart original.

## Decisions (settled during brainstorming)

| Question | Decision |
| --- | --- |
| Group model | By subtree root id: `ChartGroup(rootId, label?, style?)`. A group is the root node plus all currently visible descendants. Nesting falls out naturally. |
| Layout impact | Overlay only — box = bounding rect of visible members + padding, drawn beneath edges. No layout-engine changes. Layout-aware spacing can be added later without breaking API. |
| Styling | Painter-drawn `GroupBoxStyle` (fill, border color/width, corner radius, padding, optional dash, labelStyle) with the label at the box's top-left. No widget builder in v1 (YAGNI). |
| API home | Groups declared on the controller (like `connections`); default `GroupBoxStyle` on the widget; optional per-group override on `ChartGroup`. |
| Implementation | Per-frame hulls computed from the animated layer's merged (lerped) node rects, painted by a new bottom-most `GroupBoxPainter` — boxes stretch/glide with layout animations. Not precomputed in `ChartState` (would snap). |

## Public API

```dart
// Controller — declares WHAT, mirroring connections:
OrgChartController<T>(
  data: ...,
  groups: [
    ChartGroup(rootId: '3', label: 'Engineering'),
    ChartGroup(rootId: '7', label: 'Design',
        style: GroupBoxStyle(borderColor: ...)), // optional override
  ],
);
List<ChartGroup> get groups; // unmodifiable, like connections

// Widget — declares HOW:
OrgChart<T>(
  groupBoxStyle: GroupBoxStyle(
    fill: Color(0x14808080),
    borderColor: Color(0xFF9E9E9E),
    borderWidth: 1.5,
    borderRadius: 12,
    padding: 16,          // hull inflation, all sides
    labelStyle: TextStyle(...),
    dash: null,           // optional dash pattern, validated at construction
  ),
)
```

`ChartGroup` is immutable (`rootId`, optional `label`, optional `style`),
with value `==`/`hashCode` like `Connection`.

## Semantics

- A group's box wraps the root plus all currently **visible** descendants:
  collapsing within the department shrinks the box; expanding grows it;
  both animate.
- Collapsed group root → box wraps just the root.
- Group root hidden behind a collapsed ancestor → no box drawn.
- Unknown `rootId` → silently skipped (matches connections with missing
  endpoints).
- Nested groups → both draw; outer (shallower root depth) paints first so
  the inner box sits on top of the outer's fill.
- Labels paint whenever the box does; no truncation in v1 — a label wider
  than its box overflows the box edge (documented).
- During exit animations, hulls include exiting nodes at their lerped
  rects: a collapsing department's box visibly shrinks as members retreat
  into the parent. This falls out of feeding the merged animated node
  list rather than `state.nodes`.
- `GroupBoxStyle` dash validation matches `ConnectionStyle`: non-positive
  dash segments throw at construction (regression lesson from the 0.1.0
  render-thread hang).

## Components & file layout

- **New `lib/src/model/chart_group.dart`** — `ChartGroup` and
  `GroupBoxStyle` (immutable, value equality, dash validation).
- **New `lib/src/widgets/group_hulls.dart`** — pure function:
  `List<GroupHull> computeGroupHulls({groups, memberRects, tree, paddingOf})`
  where `paddingOf` is `double Function(ChartGroup)` resolving each
  group's effective padding (its style override or the widget default) —
  resolve each group root (skip unknown/invisible), collect visible
  member ids via the existing `descendants` walk, union rects, inflate by
  `paddingOf(group)`, sort outer-before-inner by root depth.
  Returns `GroupHull(group, rect, depth)`. Operates on `LayoutRect`;
  fully unit-testable without widgets.
- **New `lib/src/widgets/group_box_painter.dart`** — `GroupBoxPainter
  extends CustomPainter`: paints rounded rects (fill, then border —
  dashed via the existing path/dash utilities when set) and labels via
  `TextPainter` at the top-left inside the padding, offset by the chart
  origin like the other painters.
- **`org_chart_controller.dart`** (~10 lines) — `groups` constructor
  param + unmodifiable getter, exactly like `connections`.
- **`org_chart.dart`** (~25 lines) — `groupBoxStyle` param; inside the
  `AnimatedBuilder`, feed the merged (lerped) node rects to
  `computeGroupHulls`; prepend `Positioned.fill(CustomPaint(
  GroupBoxPainter(...)))` as the FIRST Stack child, beneath `EdgePainter`.
- **Exports** — `ChartGroup`, `GroupBoxStyle` from `flex_org_chart.dart`.

## Testing

- Unit — `computeGroupHulls`: hull math and padding; collapsed root →
  root-only box; hidden root → no hull; unknown id skipped; nesting depth
  order; per-group style padding override.
- Unit — `GroupBoxStyle` dash validation (throws on non-positive
  segments).
- Widget — box renders for a declared group and sits beneath nodes
  (paint order via tree position); box disappears when the root's
  ancestor collapses; per-group style override wins over the widget
  default.
- Example app: two departments declared. README row → done + snippet.
  CHANGELOG 0.4.0 + pubspec version bump (bump ships with the docs task).

## Roadmap context

After this: image/PDF export (#4). Pagination not planned.

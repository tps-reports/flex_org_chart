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

## 0.1.0

Initial release. A highly customizable, animated org chart widget for
Flutter, ported from [d3-org-chart](https://github.com/bumbeishvili/org-chart)
with a [d3-flextree](https://github.com/Klortho/d3-flextree)-based compact
layout.

- **Data & layout**: `stratify` builds a tree from any flat list via
  `idOf`/`parentIdOf` callbacks, detecting empty data, duplicate ids, missing
  parents, and cycles (`OrgChartDataException`). `LayoutEngine` computes node
  and link positions for all four `ChartLayout` directions (top, bottom,
  left, right), with an optional flextree "compact" pass that folds
  leaf-heavy subtrees into two columns.
- **Controller**: `OrgChartController` owns data and expansion/highlight
  state — `setData`, `expand`/`collapse`/`setExpanded`, `expandAll`/
  `collapseAll`, `highlight`/`highlightPathToRoot`/`clearHighlights`,
  `nodeById`/`visibleNodes`/`connections`/`dataError` — and drives viewport
  navigation (`fit`, `centerNode`, `zoomIn`/`zoomOut`) through whichever
  `OrgChart` widget is currently attached.
- **Widget**: `OrgChart` renders the controller's current layout with a
  fully custom `nodeBuilder`, pinch/drag pan and scroll-wheel zoom, animated
  enter/exit transitions when the visible node set or layout changes,
  a customizable expand/collapse affordance (`DefaultExpandButton` or
  `expandButtonBuilder`), node tap callbacks, and configurable error/empty
  states.
- **Connections**: independent, non-hierarchical `Connection` links are
  rendered as dashed, labeled, arrow-headed arcs (`ConnectionStyle`)
  alongside the hierarchical parent/child links (`LinkStyle`).
- **Highlighting**: `highlight`/`highlightPathToRoot` mark nodes and their
  link/ancestor chain, styled via `highlightedLinkStyle` and the
  `isHighlighted`/`isOnHighlightedPath` flags exposed on `OrgNode`.
- Not yet available: node editing, image/PDF export, pagination for very
  large trees, and drag-and-drop re-parenting. See the README roadmap.

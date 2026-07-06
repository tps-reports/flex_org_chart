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

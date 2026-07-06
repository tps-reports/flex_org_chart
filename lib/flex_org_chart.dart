/// A highly customizable org chart widget for Flutter, ported from
/// [d3-org-chart](https://github.com/bumbeishvili/org-chart) with a
/// flextree-based compact layout for leaf-heavy hierarchies.
///
/// The core building blocks are [OrgChartController], which owns your data
/// and expansion/highlight state, and the [OrgChart] widget, which renders
/// that controller's current layout with pan/zoom, animated transitions,
/// and a fully custom node builder. See the package README for a
/// quickstart and the `example/` app for a complete demo exercising every
/// feature.
library flex_org_chart;

export 'src/controller/org_chart_controller.dart';
export 'src/layout/layout_engine.dart' show ChartSpacing, LayoutEngine;
export 'src/layout/layout_orientation.dart' show ChartLayout;
export 'src/layout/link_geometry.dart' show PathCommand, MoveTo, LineTo, CubicTo;
export 'src/layout/stratify.dart' show stratify;
export 'src/model/chart_state.dart';
export 'src/model/connection.dart';
export 'src/model/geometry.dart';
export 'src/model/org_chart_data_exception.dart';
export 'src/model/org_node.dart';
export 'src/widgets/connection_painter.dart' show ConnectionStyle;
export 'src/widgets/edge_painter.dart' show LinkStyle;
export 'src/widgets/expand_button.dart' show DefaultExpandButton;
export 'src/widgets/org_chart.dart';

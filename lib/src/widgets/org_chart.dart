import 'package:flutter/material.dart';

import '../controller/org_chart_controller.dart';
import '../layout/layout_engine.dart';
import '../layout/layout_orientation.dart';
import '../model/org_chart_data_exception.dart';
import '../model/org_node.dart';
import 'edge_painter.dart';
import 'expand_button.dart';

typedef NodeWidgetBuilder<T> = Widget Function(BuildContext, OrgNode<T>);

/// Renders an [OrgChartController]'s current [ChartState] as a Flutter
/// widget tree.
///
/// This widget is **static** for now: it lays out node widgets and edges in
/// a [Stack] sized to the chart's layout bounds, with no viewport transform
/// (pan/zoom — Task 9) and no animated repositioning (Task 11). Every
/// visible node from `controller.state.nodes` is rendered as an absolutely
/// positioned child so later tasks can wrap this same content in a
/// transformed/animated viewport without changing this widget's structure.
class OrgChart<T> extends StatefulWidget {
  const OrgChart({
    super.key,
    required this.controller,
    required this.nodeBuilder,
    this.layout = ChartLayout.top,
    this.compact = true,
    this.nodeSize,
    this.spacing = const ChartSpacing(),
    this.linkStyle = const LinkStyle(),
    this.expandButtonBuilder,
    this.onNodeTap,
    this.onExpandToggle,
    this.animationDuration = const Duration(milliseconds: 400),
    this.errorBuilder,
    this.emptyBuilder,
  });

  /// Owns the chart's data and derived layout. Must be [configure]d by this
  /// widget (done automatically in initState/didUpdateWidget).
  final OrgChartController<T> controller;

  /// Builds the widget shown for each visible node.
  final NodeWidgetBuilder<T> nodeBuilder;

  /// Direction the tree grows in. Static rendering only supports [top] fully
  /// tested here, but all four directions are laid out by the engine.
  final ChartLayout layout;

  /// Whether to use the flextree "compact" packing pass for leaf-heavy
  /// subtrees.
  final bool compact;

  /// Returns the on-screen size to reserve for a node. Defaults to a fixed
  /// 250x150 box.
  final ({double w, double h}) Function(OrgNode<T>)? nodeSize;

  /// Spacing constants fed to the layout engine.
  final ChartSpacing spacing;

  /// Color/width of the connector lines drawn between parent and child.
  final LinkStyle linkStyle;

  /// Overrides the default expand/collapse affordance rendered under nodes
  /// that have children. Receives a `toggle` callback that flips the
  /// node's expanded state through the controller.
  final Widget Function(BuildContext, OrgNode<T>, VoidCallback toggle)?
      expandButtonBuilder;

  /// Called when a node widget is tapped. When null, node widgets do not
  /// intercept taps (they pass through to whatever is beneath them).
  final void Function(OrgNode<T>)? onNodeTap;

  /// Called after the built-in expand button toggles a node's expansion.
  final void Function(OrgNode<T>, bool expanded)? onExpandToggle;

  /// Reserved for Task 11 (animated layout transitions); unused by this
  /// static-rendering implementation.
  final Duration animationDuration;

  /// Overrides the default error view shown when [controller]'s data is
  /// malformed (e.g. a missing parent id or a cycle).
  final Widget Function(BuildContext, OrgChartDataException)? errorBuilder;

  /// Overrides the default view shown when there are no nodes to display.
  final WidgetBuilder? emptyBuilder;

  @override
  State<OrgChart<T>> createState() => _OrgChartState<T>();
}

class _OrgChartState<T> extends State<OrgChart<T>> {
  static ({double w, double h}) _defaultSize<T>(OrgNode<T> _) =>
      (w: 250.0, h: 150.0);

  @override
  void initState() {
    super.initState();
    _configure();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(OrgChart<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
    _configure();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _configure() {
    widget.controller.configure(OrgChartConfig<T>(
      layout: widget.layout,
      compact: widget.compact,
      spacing: widget.spacing,
      nodeSize: widget.nodeSize ?? _defaultSize,
    ));
  }

  // Calling setState() here in response to a controller notification that
  // fires synchronously from didUpdateWidget (see OrgChartController.configure
  // doc: the first configure() never notifies, every later one does) is
  // safe: Flutter only forbids markNeedsBuild() on an element that is *not*
  // the one currently being rebuilt. didUpdateWidget runs on this element
  // while it is the active build target, so setState on `this` is in scope.
  // The `mounted` guard is defensive belt-and-braces, not a fix for an
  // observed assertion.
  void _onChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _toggle(OrgNode<T> node) {
    final expanding = !node.isExpanded;
    widget.controller.setExpanded(node.id, expanded: expanding);
    widget.onExpandToggle?.call(node, expanding);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final error = controller.dataError;
    if (error != null) {
      return widget.errorBuilder?.call(context, error) ??
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not build org chart: $error',
                  textAlign: TextAlign.center),
            ),
          );
    }
    final state = controller.state;
    if (state.nodes.isEmpty) {
      return widget.emptyBuilder?.call(context) ??
          const Center(child: Text('No data to display'));
    }

    final origin = Offset(-state.bounds.left, -state.bounds.top);
    final children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: EdgePainter(
              links: state.links, style: widget.linkStyle, origin: origin),
        ),
      ),
      for (final layout in state.nodes) ...[
        Positioned(
          key: ValueKey('node-position-${layout.node.id}'),
          left: layout.rect.left + origin.dx,
          top: layout.rect.top + origin.dy,
          width: layout.rect.width,
          height: layout.rect.height,
          child: GestureDetector(
            onTap: widget.onNodeTap == null
                ? null
                : () => widget.onNodeTap!(layout.node),
            child: widget.nodeBuilder(context, layout.node),
          ),
        ),
        if (layout.node.children.isNotEmpty)
          Positioned(
            left: layout.rect.left + origin.dx + layout.rect.width / 2 - 20,
            top: layout.rect.top + origin.dy + layout.rect.height - 8,
            child: KeyedSubtree(
              key: ValueKey('expand-button-${layout.node.id}'),
              child: widget.expandButtonBuilder?.call(
                      context, layout.node, () => _toggle(layout.node)) ??
                  DefaultExpandButton(
                    expanded: layout.node.isExpanded,
                    count: layout.node.directSubordinates,
                    onTap: () => _toggle(layout.node),
                  ),
            ),
          ),
      ],
    ];

    return SizedBox(
      width: state.bounds.width,
      // Reserve headroom below the laid-out bounds for the expand-button
      // overlay, which this task always anchors to the bottom edge of a
      // node's rect (see the Positioned above). Flutter's hit-testing gates
      // every ancestor RenderBox at its own `size` before recursing into
      // children, so a child painted outside that size — even with
      // clipBehavior: Clip.none, which only affects *painting* — is visible
      // but never receives taps. Without this reserve, the expand button on
      // any bottom-most visible node with children sits partially outside
      // `state.bounds` and becomes untappable. `_kExpandButtonOverflowReserve`
      // comfortably covers the default button's ~12px overflow (and
      // reasonably-sized custom expandButtonBuilder overlays); it does not
      // depend on measuring the actual button, since Positioned can't query
      // a child's size before it's laid out.
      height: state.bounds.height + _kExpandButtonOverflowReserve,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}

/// See the height comment in [_OrgChartState.build].
const _kExpandButtonOverflowReserve = 40.0;

import 'package:flutter/material.dart';

import '../controller/org_chart_controller.dart';
import '../layout/layout_engine.dart';
import '../layout/layout_orientation.dart';
import '../model/geometry.dart';
import '../model/org_chart_data_exception.dart';
import '../model/org_node.dart';
import 'chart_viewport.dart';
import 'edge_painter.dart';
import 'expand_button.dart';
import 'viewport_math.dart';

typedef NodeWidgetBuilder<T> = Widget Function(BuildContext, OrgNode<T>);

/// Renders an [OrgChartController]'s current [ChartState] as a Flutter
/// widget tree.
///
/// The chart content (a [Stack] of positioned node widgets and edges, sized
/// to the chart's layout bounds) is rendered inside a [ChartViewport], which
/// supplies pinch/drag pan and scroll-wheel zoom and lets this widget expose
/// [OrgChartController]'s imperative `fit`/`centerNode`/`zoomIn`/`zoomOut`
/// calls by implementing [ChartViewportHandle]. Node repositioning itself is
/// still unanimated (Task 11).
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
    this.scaleExtent = const (0.001, 20.0),
    this.onZoom,
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

  /// `(min, max)` scale the viewport can be pinched/scrolled/zoomed to.
  /// Also clamps [OrgChartController.zoomIn]/[OrgChartController.zoomOut].
  final (double, double) scaleExtent;

  /// Called after every gesture- or scroll-driven zoom with the new scale.
  /// Programmatic zoom (`zoomIn`/`zoomOut`/`fit`/`centerNode`) does not call
  /// this — observe [controller] if you need to react to those too.
  final void Function(double scale)? onZoom;

  @override
  State<OrgChart<T>> createState() => _OrgChartState<T>();
}

class _OrgChartState<T> extends State<OrgChart<T>>
    with TickerProviderStateMixin
    implements ChartViewportHandle {
  static ({double w, double h}) _defaultSize<T>(OrgNode<T> _) =>
      (w: 250.0, h: 150.0);

  final TransformationController _tc = TransformationController();

  // Constructed eagerly in initState (not as a `late final` field
  // initializer) on purpose: `late final` defers construction to first
  // *access*, and if fitBounds/centerOn are never called with
  // `animate: true` before this widget is disposed, that first access would
  // otherwise happen inside dispose() itself (`_viewportAnim.dispose()`).
  // AnimationController's constructor calls `vsync.createTicker`, which
  // looks up a TickerMode ancestor via the element tree — something that
  // throws "Looking up a deactivated widget's ancestor is unsafe" once the
  // widget is being torn down. Constructing it up front in initState, while
  // the element is still active, avoids that entirely.
  late final AnimationController _viewportAnim;
  Size _viewportSize = Size.zero;

  /// Set once, cleared the first time [build] runs with a non-empty
  /// [ChartState] — schedules the one-time initial `fit` (see [build]).
  bool _needsInitialFit = true;

  @override
  void initState() {
    super.initState();
    _viewportAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _configure();
    widget.controller.addListener(_onChanged);
    widget.controller.attachViewport(this);
  }

  @override
  void didUpdateWidget(OrgChart<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_onChanged);
      old.controller.detachViewport(this);
      widget.controller.addListener(_onChanged);
      widget.controller.attachViewport(this);
      _needsInitialFit = true;
    }
    _configure();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.detachViewport(this);
    _tc.dispose();
    _viewportAnim.dispose();
    super.dispose();
  }

  // ---- ChartViewportHandle ----

  /// Drives [_tc] from its current value to [target] over
  /// [_viewportAnim]'s duration, or jumps immediately when `animate: false`.
  ///
  /// Any in-flight animation is stopped first, in *both* branches: `stop()`
  /// cancels the running ticker, which resolves the previous `forward()`
  /// call's `TickerFuture` as cancelled and fires its `whenCompleteOrCancel`
  /// — removing that tween's tick listener. Without the up-front stop, the
  /// `animate: false` branch would set `_tc.value` once but leave the old
  /// tween's listener attached to a still-running controller, which would
  /// keep firing and silently drag the transform back onto the abandoned
  /// trajectory for up to the remaining animation duration (regression:
  /// 'instant jump mid-animation cancels the in-flight tween' in
  /// viewport_test.dart).
  ///
  /// For the animated branch this also makes mid-flight retargeting clean:
  /// `begin` is read from `_tc.value` *after* the stop, i.e. wherever the
  /// interrupted animation had ticked to, so retargeting continues smoothly
  /// instead of jumping back to the old animation's start.
  void _animateTo(Matrix4 target, {bool animate = true}) {
    _viewportAnim.stop();
    if (!animate) {
      _tc.value = target;
      return;
    }
    final tween = Matrix4Tween(begin: _tc.value.clone(), end: target)
        .chain(CurveTween(curve: Curves.easeInOut));
    void tick() => _tc.value = tween.evaluate(_viewportAnim);
    _viewportAnim
      ..reset()
      ..addListener(tick)
      ..forward().whenCompleteOrCancel(() => _viewportAnim.removeListener(tick));
  }

  @override
  void fitBounds(LayoutRect bounds, {bool animate = true}) => _animateTo(
      fitTransform(bounds: _shifted(bounds), viewport: _viewportSize),
      animate: animate);

  @override
  void centerOn(LayoutRect rect, {bool animate = true}) => _animateTo(
      centerTransform(
          rect: _shifted(rect),
          viewport: _viewportSize,
          scale: _tc.value.getMaxScaleOnAxis()),
      animate: animate);

  @override
  void zoomBy(double factor) {
    // Like _animateTo and ChartViewport's onInteractionStart: this writes
    // _tc.value directly, so any in-flight fit/center tween must be stopped
    // first or its still-attached tick listener wipes the zoom back onto
    // the abandoned trajectory on the very next frame (regression: 'zoomIn
    // mid-animation cancels the in-flight tween' in viewport_test.dart).
    _viewportAnim.stop();
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    // Same zoom-at-point math as ChartViewport's scroll-wheel handler
    // (_ChartViewportState._applyScaleAt), anchored at the viewport center
    // instead of the cursor since there's no pointer position to anchor to
    // for a programmatic zoomIn()/zoomOut() call.
    final current = _tc.value.getMaxScaleOnAxis();
    final target =
        (current * factor).clamp(widget.scaleExtent.$1, widget.scaleExtent.$2);
    final applied = target / current;
    _tc.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0.0, 1.0)
      ..scaleByDouble(applied, applied, applied, 1.0)
      ..translateByDouble(-center.dx, -center.dy, 0.0, 1.0)
      ..multiply(_tc.value);
  }

  /// [ChartState] rects are in raw layout-bounds space (origin at
  /// `state.bounds.left/top`, no reserve). Content is actually rendered
  /// shifted by [_kExpandButtonOverflowReserve] / 2 downward (see [build])
  /// so the expand-button overflow reserve is symmetric top/bottom. Every
  /// rect handed to viewport math must go through this so `fit`/`centerNode`
  /// target the position nodes are actually painted at, not their raw model
  /// coordinates.
  LayoutRect _shifted(LayoutRect r) {
    final b = widget.controller.state.bounds;
    return LayoutRect(r.left - b.left,
        r.top - b.top + _kExpandButtonOverflowReserve / 2, r.width, r.height);
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

    // Schedule the one-time initial fit exactly once, the first time this
    // build sees a non-empty chart. Deferred to a post-frame callback
    // because `_viewportSize` (read by fitBounds -> fitTransform) is only
    // known once LayoutBuilder below has run for this frame.
    if (_needsInitialFit) {
      _needsInitialFit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final freshState = widget.controller.state;
        if (freshState.nodes.isNotEmpty) {
          fitBounds(freshState.bounds, animate: false);
        }
      });
    }

    final origin = Offset(
        -state.bounds.left, -state.bounds.top + _kExpandButtonOverflowReserve / 2);
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

    final content = SizedBox(
      width: state.bounds.width,
      // Reserve headroom above *and* below the laid-out bounds for the
      // expand-button overlay, which this widget always anchors to the
      // bottom edge of a node's rect (see the Positioned above). Flutter's
      // hit-testing gates every ancestor RenderBox at its own `size` before
      // recursing into children — true even here, inside ChartViewport's
      // Transform/OverflowBox, since RenderTransform.hitTest inverts the
      // transform and then still checks its (child's) reported `size`
      // before delegating. So a child painted outside that size — even
      // with clipBehavior: Clip.none, which only affects *painting* — is
      // visible but never receives taps. Verified by a widget test that
      // taps a bottom-row expand button through the full ChartViewport
      // composition (viewport_test.dart).
      //
      // The reserve is split evenly top/bottom rather than added only
      // below (as an earlier draft did) even though only the bottom side
      // ever actually overflows: a bottom-only reserve makes this SizedBox
      // taller without growing symmetrically around its content, which is
      // a footgun for any future code that centers this box by its own
      // size. Splitting the padding keeps the content vertically centered
      // in its own box regardless. `_shifted` (used by fit/centerNode) adds
      // the same top half back in, so viewport navigation still targets
      // rendered node positions, not raw model coordinates.
      //
      // The 40px total comfortably covers the default button's ~12px
      // overflow and reasonably-sized custom expandButtonBuilder overlays;
      // it does not depend on measuring the actual button, since Positioned
      // can't query a child's size before it's laid out.
      height: state.bounds.height + _kExpandButtonOverflowReserve,
      child: Stack(clipBehavior: Clip.none, children: children),
    );

    return LayoutBuilder(builder: (context, constraints) {
      _viewportSize = constraints.biggest;
      return ChartViewport(
        transformationController: _tc,
        scaleExtent: widget.scaleExtent,
        onZoom: widget.onZoom,
        // A user gesture takes over the transform: cancel any in-flight
        // programmatic fit/center animation so its tween doesn't keep
        // ticking and fight the gesture (stop() fires the tween's
        // whenCompleteOrCancel, detaching its tick listener).
        onInteractionStart: () => _viewportAnim.stop(),
        child: content,
      );
    });
  }
}

/// See the height comment in [_OrgChartState.build].
const _kExpandButtonOverflowReserve = 40.0;

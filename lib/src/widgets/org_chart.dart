import 'package:flutter/material.dart';

import '../controller/org_chart_controller.dart';
import '../layout/layout_engine.dart';
import '../layout/layout_orientation.dart';
import '../model/chart_state.dart';
import '../model/geometry.dart';
import '../model/org_chart_data_exception.dart';
import '../model/org_node.dart';
import 'chart_viewport.dart';
import 'connection_painter.dart';
import 'edge_painter.dart';
import 'expand_button.dart';
import 'viewport_math.dart';

/// Builds the widget shown for a single visible node.
typedef NodeWidgetBuilder<T> = Widget Function(BuildContext, OrgNode<T>);

/// Renders an [OrgChartController]'s current [ChartState] as a Flutter
/// widget tree.
///
/// The chart content (a [Stack] of positioned node widgets and edges, sized
/// to the chart's layout bounds) is rendered inside a [ChartViewport], which
/// supplies pinch/drag pan and scroll-wheel zoom and lets this widget expose
/// [OrgChartController]'s imperative `fit`/`centerNode`/`zoomIn`/`zoomOut`
/// calls by implementing [ChartViewportHandle]. Whenever the controller's
/// visible node set or their rects actually change, nodes and links animate
/// between the old and new layout over [OrgChart.animationDuration]:
/// entering nodes emerge from their parent's previous position and exiting
/// nodes retreat into their parent's new position.
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
    this.highlightedLinkStyle = const LinkStyle(
      color: Color(0xFFE27396),
      width: 3,
    ),
    this.connectionStyle = const ConnectionStyle(),
    this.expandButtonBuilder,
    this.onNodeTap,
    this.onExpandToggle,
    this.animationDuration = const Duration(milliseconds: 400),
    this.errorBuilder,
    this.emptyBuilder,
    this.scaleExtent = const (0.001, 20.0),
    this.onZoom,
  });

  /// Owns the chart's data and derived layout. Must be configured by this
  /// widget via [OrgChartController.configure] (done automatically in
  /// initState/didUpdateWidget).
  final OrgChartController<T> controller;

  /// Builds the widget shown for each visible node.
  final NodeWidgetBuilder<T> nodeBuilder;

  /// Direction the tree grows in. All four [ChartLayout] values are
  /// supported by the layout engine and renderable here; widget-level tests
  /// in this package focus on [ChartLayout.top].
  final ChartLayout layout;

  /// Whether to use the flextree "compact" packing pass for leaf-heavy
  /// subtrees.
  final bool compact;

  /// Returns the size to reserve for a node, called during layout — before
  /// [nodeBuilder] runs. The returned size becomes a hard width/height
  /// constraint on the rendered node widget (each node is placed in a
  /// [Positioned] of exactly this size): if [nodeBuilder] produces content
  /// larger than this, it will overflow or clip silently.
  ///
  /// Unlike [nodeBuilder], this callback has no [BuildContext] — it cannot
  /// depend on Theme, MediaQuery, or inherited widgets. Derive sizes from
  /// the node's data instead (e.g. taller cards for managers).
  ///
  /// Defaults to a constant 250x150 box for every node.
  final ({double w, double h}) Function(OrgNode<T>)? nodeSize;

  /// Spacing constants fed to the layout engine.
  final ChartSpacing spacing;

  /// Color/width of the connector lines drawn between parent and child.
  final LinkStyle linkStyle;

  /// Color/width of connector lines whose child node is highlighted or on
  /// the highlighted path. Painted on top of regular links.
  final LinkStyle highlightedLinkStyle;

  /// Color/width/dash pattern for the dashed, labeled, arrow-headed arcs
  /// drawn between arbitrary node pairs declared via
  /// [OrgChartController.connections] — independent of the hierarchical
  /// parent/child links styled by [linkStyle]/[highlightedLinkStyle].
  final ConnectionStyle connectionStyle;

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

  /// Duration of the layout-change animation driven by `_layoutAnim`: nodes
  /// and links lerp between their previous and current positions/paths over
  /// this duration whenever the controller's visible node set or rects
  /// actually change (see `_onChanged`'s guard).
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

  // Layout-change animation (Task 11). Constructed eagerly in initState for
  // the same reason _viewportAnim is (see its comment above): a `late final`
  // field initializer only constructs on first *access*, and if a layout
  // change never happens before this widget is disposed, that first access
  // would otherwise happen inside dispose() itself, throwing when
  // AnimationController's constructor tries to look up a vsync ancestor of
  // an already-deactivated element.
  //
  // `_t` is the eased (easeInOut) view of `_layoutAnim` that `_mergedNodes`
  // and the EdgePainter progress both read from.
  late final AnimationController _layoutAnim;
  late final CurvedAnimation _t;

  /// Set once, cleared the first time [build] runs with a non-empty
  /// [ChartState] — schedules the one-time initial `fit` (see [build]).
  bool _needsInitialFit = true;

  @override
  void initState() {
    super.initState();
    _viewportAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _layoutAnim =
        AnimationController(vsync: this, duration: widget.animationDuration);
    _t = CurvedAnimation(parent: _layoutAnim, curve: Curves.easeInOut);
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
    _layoutAnim.duration = widget.animationDuration;
    _configure();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.detachViewport(this);
    _tc.dispose();
    _viewportAnim.dispose();
    _t.dispose();
    _layoutAnim.dispose();
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
      ..forward()
          .whenCompleteOrCancel(() => _viewportAnim.removeListener(tick));
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
  //
  // Ordering trap (Task 11): OrgChartController.configure() reruns
  // _relayout (and notifies, once initialized) on *every* call, and
  // didUpdateWidget calls configure() on every widget rebuild — including
  // rebuilds with no actual data/expansion change (e.g. an ancestor
  // rebuilding for an unrelated reason). _relayout also unconditionally
  // allocates a brand-new ChartState each time, so a plain
  // `identical(controller.state, _lastSeenState)` check can never catch
  // this: the object reference differs on every single notify, "real"
  // change or not. If _onChanged blindly restarted `_layoutAnim` on every
  // notify, an app that rebuilds OrgChart's ancestor frequently would keep
  // resetting the animation to t=0 forever — nodes mid-transition would
  // never reach their destination. Instead, only restart when the
  // *content* actually changed: same node count, same bounds, and same
  // rect per surviving node id means nothing worth animating happened, so
  // we still rebuild (setState) to pick up any other state change — e.g. a
  // highlight-only update — but leave `_layoutAnim` alone rather than
  // restarting it.
  void _onChanged() {
    if (!mounted) return;
    if (_layoutChanged(
        widget.controller.previousState, widget.controller.state)) {
      _layoutAnim.forward(from: 0);
    }
    setState(() {});
  }

  /// Cheap structural comparison of two [ChartState]s using only their
  /// public API (no changes to lib/src/model/ allowed for this task): true
  /// when the visible node count, overall bounds, or any surviving node's
  /// rect differs. Highlight/expansion flags on [OrgNode] are deliberately
  /// not compared here — they don't affect layout, so a highlight-only
  /// change should still repaint (via the unconditional setState in
  /// [_onChanged]) without restarting the position/opacity animation.
  bool _layoutChanged(ChartState<T> a, ChartState<T> b) {
    if (identical(a, b)) return false;
    if (a.nodes.length != b.nodes.length) return true;
    if (!_rectEquals(a.bounds, b.bounds)) return true;
    for (final n in b.nodes) {
      final prevNode = a.byId(n.node.id);
      if (prevNode == null || !_rectEquals(prevNode.rect, n.rect)) return true;
    }
    return false;
  }

  bool _rectEquals(LayoutRect x, LayoutRect y) =>
      x.left == y.left &&
      x.top == y.top &&
      x.width == y.width &&
      x.height == y.height;

  /// Merges [OrgChartController.previousState] and [OrgChartController.state]
  /// into the per-frame node view driving the layout-change animation.
  /// Nodes present in both states lerp their rect by the current eased
  /// progress `t`. Nodes only in [next] (just became visible) enter from
  /// their nearest ancestor's *previous* rect — falling all the way back to
  /// their own final rect if no ancestor existed before — fading in
  /// (opacity 0→1). Nodes only in [prev] (just became hidden) are kept
  /// around and animated toward their nearest ancestor's *next* rect,
  /// fading out (opacity 1→0), until `t` reaches 1 — see [build], which
  /// drops them from the tree once `t >= 1.0`.
  List<_AnimatedNode<T>> _mergedNodes() {
    final prev = widget.controller.previousState;
    final next = widget.controller.state;
    final t = _layoutAnim.isAnimating ? _t.value : 1.0;

    LayoutRect lerpRect(LayoutRect a, LayoutRect b) => LayoutRect(
        a.left + (b.left - a.left) * t,
        a.top + (b.top - a.top) * t,
        a.width + (b.width - a.width) * t,
        a.height + (b.height - a.height) * t);

    LayoutRect parentRect(ChartState<T> st, OrgNode<T> n, LayoutRect fallback) {
      var p = n.parent;
      while (p != null) {
        final r = st.byId(p.id)?.rect;
        if (r != null) return r;
        p = p.parent;
      }
      return fallback;
    }

    final out = <_AnimatedNode<T>>[];
    for (final n in next.nodes) {
      final from = prev.byId(n.node.id)?.rect ??
          parentRect(prev, n.node, n.rect); // enter from parent's old spot
      out.add(_AnimatedNode(n.node, lerpRect(from, n.rect),
          opacity: prev.byId(n.node.id) == null ? t : 1.0));
    }
    if (t < 1.0) {
      for (final o in prev.nodes) {
        if (next.byId(o.node.id) != null) continue;
        final to =
            parentRect(next, o.node, o.rect); // exit into parent's new spot
        out.add(_AnimatedNode(o.node, lerpRect(o.rect, to),
            opacity: 1.0 - t, exiting: true));
      }
    }
    return out;
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

    final origin = Offset(-state.bounds.left,
        -state.bounds.top + _kExpandButtonOverflowReserve / 2);

    // Compute the set of node IDs that are highlighted or on the highlighted path.
    // Only include nodes that have a parent (i.e., are not roots), since root nodes
    // have no incoming link to highlight.
    final highlighted = <String>{
      for (final n in state.nodes)
        if ((n.node.isHighlighted || n.node.isOnHighlightedPath) &&
            n.node.parent != null)
          n.node.id,
    };

    // The whole node/link layer rebuilds every animation frame via this
    // AnimatedBuilder, which listens to `_t` directly rather than relying on
    // `_OrgChartState.setState` — that keeps per-tick rebuilds scoped to
    // this Stack instead of re-running the rest of build() (LayoutBuilder,
    // origin/highlighted computation, the postFrameCallback check) on every
    // frame of a layout-change animation.
    final animatedLayer = AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final merged = _mergedNodes();
        final t = _layoutAnim.isAnimating ? _t.value : 1.0;
        final children = <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: EdgePainter(
                links: state.links,
                prevLinks: controller.previousState.links,
                t: t,
                style: widget.linkStyle,
                origin: origin,
                highlightedChildIds: highlighted,
                highlightedStyle: widget.highlightedLinkStyle,
              ),
            ),
          ),
          // Connections (Task 12) are computed from the *current* (next)
          // state's rects only — unlike EdgePainter's parent/child links,
          // they don't lerp from `previousState` during a layout-change
          // animation. They simply snap to the endpoints' new positions
          // once those positions update; that's an accepted v1 limitation
          // (see task brief), not an oversight.
          Positioned.fill(
            child: CustomPaint(
              painter: ConnectionPainter(
                connections: controller.connections,
                state: state,
                style: widget.connectionStyle,
                origin: origin,
              ),
            ),
          ),
          for (final n in merged) ...[
            Positioned(
              key: ValueKey('node-position-${n.node.id}'),
              left: n.rect.left + origin.dx,
              top: n.rect.top + origin.dy,
              width: n.rect.width,
              height: n.rect.height,
              child: IgnorePointer(
                ignoring: n.exiting,
                child: Opacity(
                  opacity: n.opacity.clamp(0.0, 1.0),
                  child: GestureDetector(
                    onTap: widget.onNodeTap == null
                        ? null
                        : () => widget.onNodeTap!(n.node),
                    child: widget.nodeBuilder(context, n.node),
                  ),
                ),
              ),
            ),
            if (!n.exiting && n.node.children.isNotEmpty)
              Positioned(
                left: n.rect.left + origin.dx + n.rect.width / 2 - 20,
                top: n.rect.top + origin.dy + n.rect.height - 8,
                child: KeyedSubtree(
                  key: ValueKey('expand-button-${n.node.id}'),
                  child: widget.expandButtonBuilder
                          ?.call(context, n.node, () => _toggle(n.node)) ??
                      DefaultExpandButton(
                        expanded: n.node.isExpanded,
                        count: n.node.directSubordinates,
                        onTap: () => _toggle(n.node),
                      ),
                ),
              ),
          ],
        ];
        return Stack(clipBehavior: Clip.none, children: children);
      },
    );

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
      child: animatedLayer,
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

/// One frame's worth of a node's animated position, produced by
/// [_OrgChartState._mergedNodes]. [rect] is already lerped between the
/// node's previous and current layout rects (or, for entering/exiting
/// nodes, between/around its parent's rect); [opacity] fades entering nodes
/// in and exiting nodes out. [exiting] marks a node that only exists in
/// [OrgChartController.previousState] — still rendered (fading out) until
/// the animation completes, then dropped.
class _AnimatedNode<T> {
  _AnimatedNode(this.node, this.rect, {this.opacity = 1, this.exiting = false});
  final OrgNode<T> node;
  final LayoutRect rect;
  final double opacity;
  final bool exiting;
}

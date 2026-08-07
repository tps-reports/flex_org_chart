import 'package:flutter/foundation.dart';

import '../layout/layout_engine.dart';
import '../layout/layout_orientation.dart';
import '../layout/stratify.dart';
import '../model/chart_state.dart';
import '../model/connection.dart';
import '../model/geometry.dart';
import '../model/org_chart_data_exception.dart';
import '../model/org_node.dart';

/// Immutable snapshot of everything the layout engine needs, handed to
/// [OrgChartController.configure] by the widget layer on every build.
class OrgChartConfig<T> {
  /// Creates a layout configuration snapshot.
  const OrgChartConfig({
    required this.layout,
    required this.compact,
    required this.spacing,
    required this.nodeSize,
  });

  /// Direction the tree grows in.
  final ChartLayout layout;

  /// Whether the compact packing pass is enabled.
  final bool compact;

  /// Spacing constants for the layout engine.
  final ChartSpacing spacing;

  /// Returns the size to reserve for a node, consumed by the layout engine
  /// before any node widget is built. The returned size determines the
  /// node's rect in the computed [ChartState], which the rendering widget
  /// then applies as a hard width/height constraint on the node's widget —
  /// content larger than this overflows or clips silently.
  ///
  /// This callback runs outside the widget layer (no `BuildContext`), so it
  /// cannot depend on Theme, MediaQuery, or inherited widgets; derive sizes
  /// from the node's data instead (e.g. taller cards for managers).
  final ({double w, double h}) Function(OrgNode<T>) nodeSize;
}

/// Implemented by the widget that renders the chart (Task 8/9) and attached
/// to the controller via [OrgChartController.attachViewport] so imperative
/// navigation calls (`fit`, `centerNode`, `zoomIn`/`zoomOut`) have somewhere
/// to go.
abstract class ChartViewportHandle {
  /// Animates (or, when `animate` is false, jumps) the viewport so [bounds]
  /// is fully visible, scaled to fit.
  void fitBounds(LayoutRect bounds, {bool animate = true});

  /// Animates (or jumps) the viewport so [rect] is centered, at the current
  /// zoom level.
  void centerOn(LayoutRect rect, {bool animate = true});

  /// Multiplies the current zoom level by [factor], anchored at the
  /// viewport's center.
  void zoomBy(double factor);
}

/// Owns the org-chart's data, expansion/highlight state, and the derived
/// [ChartState] layout. This is a plain [ChangeNotifier] — it knows nothing
/// about widgets or `dart:ui`; the rendering widget (Task 8) observes it and
/// a [ChartViewportHandle] is attached for viewport delegation (Task 9).
///
/// Caller-owned: create and keep it wherever you own the chart's data (e.g.
/// a `State` field), and call [dispose] yourself once you're done with it —
/// the `OrgChart` widget observes and drives an already-constructed
/// controller, it never takes ownership of or disposes one on your behalf.
class OrgChartController<T> extends ChangeNotifier {
  /// Creates a controller over [data]. [idOf] and [parentIdOf] resolve each
  /// item's id and parent id (a `null`/empty parent id makes an item a
  /// root); nodes at [initialExpandLevel] or shallower start expanded; and
  /// [connections] declares any non-hierarchical links to draw alongside
  /// the tree.
  OrgChartController({
    required List<T> data,
    required this.idOf,
    required this.parentIdOf,
    this.initialExpandLevel = 1,
    List<Connection> connections = const [],
  }) : _data = List.of(data),
       _connections = List.of(connections);

  /// Resolves a data item's unique id.
  final String Function(T) idOf;

  /// Resolves a data item's parent id, or `null`/empty for a root item.
  final String? Function(T) parentIdOf;

  /// Depth (root = 0) at or above which nodes start expanded.
  final int initialExpandLevel;

  List<T> _data;
  final List<Connection> _connections;
  OrgTree<T>? _tree;
  OrgChartConfig<T>? _config;
  ChartViewportHandle? _viewport;
  OrgChartDataException? _dataError;
  ChartState<T> _state = ChartState.empty<T>();
  ChartState<T> _previousState = ChartState.empty<T>();
  bool _initialized = false;

  /// The current computed layout: every visible node's rectangle, every
  /// visible parent-child link, and the overall bounds.
  ChartState<T> get state => _state;

  /// The layout as of just before the most recent LAYOUT change — used by the
  /// rendering widget to animate between the two. Highlight-only updates do not
  /// advance it; the animation layer lerps from it.
  ChartState<T> get previousState => _previousState;

  /// The error from the most recent failed [setData]/construction, or
  /// `null` if the current data is valid.
  OrgChartDataException? get dataError => _dataError;

  /// The declared non-hierarchical connections, as passed to the
  /// constructor.
  List<Connection> get connections => List.unmodifiable(_connections);

  /// The controller's current backing data, including the result of any
  /// editing ops (`addNode`, `removeNode`, `reparent`, `updateNode`), as
  /// an unmodifiable view. Mutating the list you originally passed in has
  /// no effect — hand changes to [setData] or the editing ops instead.
  List<T> get data => List.unmodifiable(_data);

  /// The [OrgNode] wrapping every currently visible node's data, in the
  /// order they appear in [state]. Each entry's `.data` is the original
  /// item passed to the constructor/[setData], not the item itself.
  List<OrgNode<T>> get visibleNodes => _state.nodes.map((n) => n.node).toList();

  /// Looks up a node anywhere in the tree by id (regardless of whether it
  /// is currently visible), or `null` if no node has that id.
  OrgNode<T>? nodeById(String id) => _tree?.nodeById(id);

  // ---- framework wiring (called by the OrgChart widget) ----

  /// Called by the widget on every build (initState + didUpdateWidget) with
  /// the layout parameters derived from its current props. The very first
  /// call happens mid-build, so it must not call [notifyListeners] — Flutter
  /// forbids notifying listeners while a widget is building. Subsequent
  /// calls (real config changes, e.g. a resized node or new spacing) do
  /// notify so the rendered chart picks up the new layout.
  ///
  /// Note: this re-runs `_relayout` (and notifies) on *every* call once
  /// initialized, even if `config` is value-identical to the previous one —
  /// there's no equality check on [OrgChartConfig]. That means a widget
  /// rebuild with unchanged layout params still triggers a relayout + a
  /// notification. Left as-is per the task brief; Task 8 may add a config
  /// equality/dedup check if that proves costly in practice.
  void configure(OrgChartConfig<T> config) {
    _config = config;
    _rebuildTreeIfNeeded();
    _relayout(notify: _initialized);
    _initialized = true;
  }

  /// Registers [viewport] as the target of `fit`/`centerNode`/`zoomIn`/
  /// `zoomOut`. Called automatically by the `OrgChart` widget.
  void attachViewport(ChartViewportHandle viewport) => _viewport = viewport;

  /// Unregisters [viewport] if it is the currently attached handle
  /// (no-op otherwise). Called automatically by the `OrgChart` widget.
  void detachViewport(ChartViewportHandle viewport) {
    if (identical(_viewport, viewport)) _viewport = null;
  }

  // ---- data ----

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
  /// (`addNode`, `removeNode`, `reparent`, `updateNode`): capture
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

  // ---- expansion ----

  /// Expands the node with id [id] (shows its direct children), if it
  /// exists. No-op if [id] is unknown.
  void expand(String id) => _setExpanded(id, true);

  /// Collapses the node with id [id] (hides its descendants), if it
  /// exists. No-op if [id] is unknown.
  void collapse(String id) => _setExpanded(id, false);

  void _setExpanded(String id, bool expanded) {
    final node = _tree?.nodeById(id);
    if (node == null) return;
    node.isExpanded = expanded;
    _relayout();
  }

  /// Sets a node's expanded flag and, when [expandAncestors] is true (the
  /// default) and [expanded] is true, expands every ancestor too so the
  /// node is actually reachable/visible — expanding a node whose parent
  /// chain is collapsed would otherwise have no visible effect.
  void setExpanded(
    String id, {
    bool expanded = true,
    bool expandAncestors = true,
  }) {
    final node = _tree?.nodeById(id);
    if (node == null) return;
    node.isExpanded = expanded;
    if (expanded && expandAncestors) {
      for (final a in node.ancestors) {
        a.isExpanded = true;
      }
    }
    _relayout();
  }

  /// Expands every node in the tree, making the whole hierarchy visible.
  void expandAll() {
    _forAll((n) => n.isExpanded = true);
    _relayout();
  }

  /// Collapses every node in the tree, hiding everything below the roots.
  void collapseAll() {
    _forAll((n) => n.isExpanded = false);
    _relayout();
  }

  // ---- highlight ----

  /// Highlights the single node with id [id], clearing any previous
  /// highlight or highlighted path. Pass `null`, or an [id] that doesn't
  /// match any node, to clear the highlight entirely (equivalent to
  /// [clearHighlights]) — there's no separate "unknown id" error or no-op:
  /// every node's highlight flag is simply recomputed against [id], so one
  /// that matches nothing highlights nothing.
  void highlight(String? id) {
    _forAll((n) {
      n.isHighlighted = n.id == id;
      n.isOnHighlightedPath = false;
    });
    _relayout();
  }

  /// Highlights the node with id [id] and marks every ancestor up to the
  /// root as being on the highlighted path, clearing any previous
  /// highlight. Pass `null` to clear the highlight entirely (equivalent to
  /// [clearHighlights]).
  void highlightPathToRoot(String? id) {
    _forAll((n) {
      n.isHighlighted = false;
      n.isOnHighlightedPath = false;
    });
    final node = id == null ? null : _tree?.nodeById(id);
    if (node != null) {
      node.isHighlighted = true;
      for (final a in node.ancestors) {
        a.isOnHighlightedPath = true;
      }
    }
    _relayout();
  }

  /// Clears any current highlight and highlighted path.
  void clearHighlights() => highlight(null);

  // ---- viewport ----

  ChartViewportHandle get _requireViewport {
    final v = _viewport;
    if (v == null) {
      throw StateError(
        'No OrgChart widget is attached to this controller. '
        'Viewport navigation (fit/centerNode/zoomIn/zoomOut) requires an '
        'OrgChart widget built with this controller.',
      );
    }
    return v;
  }

  /// Zooms/pans the viewport so the entire chart is visible.
  ///
  /// Requires an `OrgChart` widget built with this controller to be
  /// currently mounted (throws [StateError] otherwise).
  void fit({bool animate = true}) =>
      _requireViewport.fitBounds(_state.bounds, animate: animate);

  /// Centers the viewport on [id]. If any ancestor of [id] is collapsed
  /// (so the node isn't currently visible), the ancestor chain is expanded
  /// directly first — "center on this node" should reveal it, not silently
  /// no-op. The target node's own expanded flag is left untouched: revealing
  /// a node is not the same as expanding it.
  void centerNode(
    String id, {
    bool withDescendants = false,
    bool animate = true,
  }) {
    final v = _requireViewport;
    final node = _tree?.nodeById(id);
    if (node == null) return;
    if (node.ancestors.any((a) => !a.isExpanded)) {
      for (final a in node.ancestors) {
        a.isExpanded = true;
      }
      _relayout();
    }
    final layout = _state.byId(id);
    if (layout == null) return;
    if (!withDescendants) {
      v.centerOn(layout.rect, animate: animate);
      return;
    }
    var l = layout.rect.left, t = layout.rect.top;
    var r = layout.rect.right, b = layout.rect.bottom;
    for (final d in node.descendants) {
      final dl = _state.byId(d.id)?.rect;
      if (dl == null) continue;
      if (dl.left < l) l = dl.left;
      if (dl.top < t) t = dl.top;
      if (dl.right > r) r = dl.right;
      if (dl.bottom > b) b = dl.bottom;
    }
    v.fitBounds(LayoutRect(l, t, r - l, b - t), animate: animate);
  }

  /// Zooms the viewport in by a fixed step, anchored at its center.
  void zoomIn() => _requireViewport.zoomBy(1.3);

  /// Zooms the viewport out by a fixed step, anchored at its center.
  void zoomOut() => _requireViewport.zoomBy(1 / 1.3);

  // ---- internals ----

  void _forAll(void Function(OrgNode<T>) f) {
    final tree = _tree;
    if (tree == null) return;
    for (final n in tree.allNodes) {
      f(n);
    }
  }

  void _rebuildTreeIfNeeded() {
    if (_tree != null || _config == null) return;
    _dataError = null;
    // Empty data is an empty *state*, not an error: `stratify` throwing on
    // empty input is the right behavior for its own direct callers (it's
    // tested that way), but this controller has a dedicated empty state —
    // `state.nodes.isEmpty` with no [dataError] — for the widget layer to
    // render via `emptyBuilder`. Skip stratify entirely rather than let its
    // exception surface as [dataError]; `_tree` stays null so `_relayout`
    // falls through to `ChartState.empty`, exactly like the error path
    // below, but without setting [dataError].
    if (_data.isEmpty) return;
    try {
      _tree = stratify<T>(data: _data, idOf: idOf, parentIdOf: parentIdOf);
    } on OrgChartDataException catch (e) {
      _dataError = e;
      _tree = null;
      return;
    }
    for (final n in _tree!.allNodes) {
      n.isExpanded = n.depth < initialExpandLevel;
    }
  }

  bool _isVisible(OrgNode<T> node) {
    var p = node.parent;
    while (p != null) {
      if (!p.isExpanded) return false;
      p = p.parent;
    }
    return true;
  }

  // Only advances `_previousState` when the freshly computed state actually
  // differs in layout from the current `_state` (see
  // `ChartState.layoutDiffers`, shared with the `OrgChart` widget's own
  // animation-restart guard). Without this check, every call here —
  // including highlight-only changes and every `configure()` triggered by a
  // widget rebuild — would overwrite `_previousState` with a
  // structurally-identical `_state`, and the widget's `_mergedNodes()`
  // (which reads `previousState`/`state` live) would then lerp between two
  // identical states: any in-flight layout animation snaps to its end
  // position instantly on the very next notify, even though the widget's
  // own guard correctly declined to restart the animation.
  void _relayout({bool notify = true}) {
    final config = _config;
    if (config == null) {
      return;
    }
    final tree = _tree;
    final newState = (tree == null)
        ? ChartState.empty<T>()
        : LayoutEngine.compute<T>(
            tree: tree,
            isVisible: _isVisible,
            layout: config.layout,
            compact: config.compact,
            spacing: config.spacing,
            nodeSize: config.nodeSize,
          );
    if (ChartState.layoutDiffers(_state, newState)) {
      _previousState = _state;
    }
    _state = newState;
    if (notify) notifyListeners();
  }
}

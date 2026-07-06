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
  const OrgChartConfig({
    required this.layout,
    required this.compact,
    required this.spacing,
    required this.nodeSize,
  });
  final ChartLayout layout;
  final bool compact;
  final ChartSpacing spacing;
  final ({double w, double h}) Function(OrgNode<T>) nodeSize;
}

/// Implemented by the widget that renders the chart (Task 8/9) and attached
/// to the controller via [OrgChartController.attachViewport] so imperative
/// navigation calls (`fit`, `centerNode`, `zoomIn`/`zoomOut`) have somewhere
/// to go.
abstract class ChartViewportHandle {
  void fitBounds(LayoutRect bounds, {bool animate = true});
  void centerOn(LayoutRect rect, {bool animate = true});
  void zoomBy(double factor);
}

/// Owns the org-chart's data, expansion/highlight state, and the derived
/// [ChartState] layout. This is a plain [ChangeNotifier] — it knows nothing
/// about widgets or `dart:ui`; the rendering widget (Task 8) observes it and
/// a [ChartViewportHandle] is attached for viewport delegation (Task 9).
class OrgChartController<T> extends ChangeNotifier {
  OrgChartController({
    required List<T> data,
    required this.idOf,
    required this.parentIdOf,
    this.initialExpandLevel = 1,
    List<Connection> connections = const [],
  })  : _data = List.of(data),
        _connections = List.of(connections);

  final String Function(T) idOf;
  final String? Function(T) parentIdOf;
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

  ChartState<T> get state => _state;
  ChartState<T> get previousState => _previousState;
  OrgChartDataException? get dataError => _dataError;
  List<Connection> get connections => List.unmodifiable(_connections);
  List<OrgNode<T>> get visibleNodes =>
      _state.nodes.map((n) => n.node).toList();
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

  void attachViewport(ChartViewportHandle viewport) => _viewport = viewport;

  void detachViewport(ChartViewportHandle viewport) {
    if (identical(_viewport, viewport)) _viewport = null;
  }

  // ---- data ----

  /// Replaces the backing data and re-stratifies the tree. If the new data
  /// is malformed, [dataError] is set and [state] becomes an empty
  /// [ChartState] — this method never throws. On success, initial-expand
  /// flags are re-applied exactly as they are for the constructor's data.
  void setData(List<T> data) {
    _data = List.of(data);
    _tree = null;
    _rebuildTreeIfNeeded();
    _relayout();
  }

  // ---- expansion ----

  void expand(String id) => _setExpanded(id, true);
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
  void setExpanded(String id,
      {bool expanded = true, bool expandAncestors = true}) {
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

  void expandAll() {
    _forAll((n) => n.isExpanded = true);
    _relayout();
  }

  void collapseAll() {
    _forAll((n) => n.isExpanded = false);
    _relayout();
  }

  // ---- highlight ----

  void highlight(String? id) {
    _forAll((n) {
      n.isHighlighted = n.id == id;
      n.isOnHighlightedPath = false;
    });
    _relayout();
  }

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

  void clearHighlights() => highlight(null);

  // ---- viewport ----

  ChartViewportHandle get _requireViewport {
    final v = _viewport;
    if (v == null) {
      throw StateError(
          'No OrgChart widget is attached to this controller. '
          'Viewport navigation (fit/centerNode/zoomIn/zoomOut) requires an '
          'OrgChart widget built with this controller.');
    }
    return v;
  }

  void fit({bool animate = true}) =>
      _requireViewport.fitBounds(_state.bounds, animate: animate);

  /// Centers the viewport on [id]. If any ancestor of [id] is collapsed
  /// (so the node isn't currently visible), the ancestor chain is expanded
  /// directly first — "center on this node" should reveal it, not silently
  /// no-op. The target node's own expanded flag is left untouched: revealing
  /// a node is not the same as expanding it.
  void centerNode(String id,
      {bool withDescendants = false, bool animate = true}) {
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

  void zoomIn() => _requireViewport.zoomBy(1.3);
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

  void _relayout({bool notify = true}) {
    final config = _config;
    _previousState = _state;
    if (config == null) return;
    final tree = _tree;
    _state = (tree == null)
        ? ChartState.empty<T>()
        : LayoutEngine.compute<T>(
            tree: tree,
            isVisible: _isVisible,
            layout: config.layout,
            compact: config.compact,
            spacing: config.spacing,
            nodeSize: config.nodeSize,
          );
    if (notify) notifyListeners();
  }
}

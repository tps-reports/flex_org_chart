import '../model/chart_state.dart';
import '../model/geometry.dart';
import '../model/org_node.dart';
import 'compact.dart';
import 'flextree.dart';
import 'layout_orientation.dart';
import 'link_geometry.dart';

/// Spacing constants fed to the flextree/compact layout passes, in logical
/// pixels.
class ChartSpacing {
  /// Creates a spacing configuration. All values default to the same
  /// constants d3-org-chart uses.
  const ChartSpacing({
    this.siblings = 20,
    this.children = 60,
    this.neighbour = 80,
    this.compactPair = 100,
    this.compactBetween = 20,
  });

  /// Gap between two sibling nodes along the breadth axis.
  final double siblings;

  /// Gap between a node and its children along the depth axis.
  final double children;

  /// Extra gap between two sibling *subtrees* that don't share a parent
  /// within the same level (flextree's neighbour spacing).
  final double neighbour;

  /// Gap between the two nodes forming a compact-mode pair.
  final double compactPair;

  /// Gap between successive compact-mode pairs/columns.
  final double compactBetween;
}

/// Computes a chart's full layout — node rectangles, parent-child link
/// paths, and overall bounds — from a stratified tree and the current
/// display parameters (layout direction, compact mode, spacing, node sizes).
///
/// This is the pure, Flutter-free core used by `OrgChartController`: given
/// the same inputs it always produces the same [ChartState].
class LayoutEngine {
  /// Runs the full layout pipeline: builds the visible flextree forest,
  /// optionally applies the compact-mode packing pass, runs the flextree
  /// algorithm, orients results into screen space for [layout], and derives
  /// link paths and overall bounds.
  static ChartState<T> compute<T>({
    required OrgTree<T> tree,
    required bool Function(OrgNode<T>) isVisible,
    required ChartLayout layout,
    required bool compact,
    required ChartSpacing spacing,
    required ({double w, double h}) Function(OrgNode<T>) nodeSize,
  }) {
    final horizontal =
        layout == ChartLayout.left || layout == ChartLayout.right;

    // 1) Build the visible FlexNode forest under a synthetic root.
    final synthetic = FlexNode<OrgNode<T>?>(null)..ySize = 0;
    final flexById = <String, FlexNode<OrgNode<T>?>>{};
    void add(OrgNode<T> node, FlexNode<OrgNode<T>?> parent) {
      if (!isVisible(node)) return;
      final size = nodeSize(node);
      // In layout space: breadth axis = xSize, depth axis = ySize.
      final breadth = horizontal ? size.h : size.w;
      final depth = horizontal ? size.w : size.h;
      final fn = FlexNode<OrgNode<T>?>(node)
        ..xSize = breadth + spacing.siblings
        ..ySize = depth + spacing.children
        ..parent = parent;
      parent.children.add(fn);
      flexById[node.id] = fn;
      for (final c in node.children) {
        add(c, fn);
      }
    }

    for (final root in tree.roots) {
      add(root, synthetic);
    }
    if (flexById.isEmpty) return ChartState.empty<T>();

    // 2) Compact pass (dimensions before flextree).
    CompactLayout<OrgNode<T>?>? compactPass;
    if (compact) {
      double bw(FlexNode<OrgNode<T>?> n) =>
          horizontal ? nodeSize(n.item!).h : nodeSize(n.item!).w;
      double bh(FlexNode<OrgNode<T>?> n) =>
          horizontal ? nodeSize(n.item!).w : nodeSize(n.item!).h;
      compactPass = CompactLayout<OrgNode<T>?>(
        nodeWidth: bw,
        nodeHeight: bh,
        compactMarginBetween: spacing.compactBetween,
        compactMarginPair: spacing.compactPair,
      );
      compactPass.computeDimensions(synthetic);
      for (final fn in flexById.values) {
        final dim = fn.flexCompactDim;
        if (dim != null) {
          fn.xSize = dim[0];
          fn.ySize = dim[1];
        }
      }
    }

    // 3) Flextree.
    FlexTreeLayout<OrgNode<T>?>(
      spacing: (a, b) => identical(a.parent, b.parent) ? 0 : spacing.neighbour,
    ).run(synthetic);
    compactPass?.computePositions(synthetic);

    // 4) Orient into screen space.
    var maxDepthExtent = 0.0;
    for (final fn in flexById.values) {
      final size = nodeSize(fn.item!);
      final depth = horizontal ? size.w : size.h;
      if (fn.y + depth > maxDepthExtent) maxDepthExtent = fn.y + depth;
    }
    final nodes = <NodeLayout<T>>[];
    final rectById = <String, LayoutRect>{};
    for (final fn in flexById.values) {
      final size = nodeSize(fn.item!);
      final rect = orient(layout, fn.x, fn.y, size.w, size.h, maxDepthExtent);
      rectById[fn.item!.id] = rect;
      nodes.add(NodeLayout(fn.item!, rect));
    }

    // 5) Links: child join point -> parent join point per layout direction.
    final links = <LinkLayout>[];
    for (final fn in flexById.values) {
      final node = fn.item!;
      final parent = node.parent;
      if (parent == null || !rectById.containsKey(parent.id)) continue;
      final c = rectById[node.id]!;
      final p = rectById[parent.id]!;
      final commands = switch (layout) {
        ChartLayout.top => verticalDiagonal(
          s: (x: c.centerX, y: c.top),
          t: (x: p.centerX, y: p.bottom),
        ),
        ChartLayout.bottom => verticalDiagonal(
          s: (x: c.centerX, y: c.bottom),
          t: (x: p.centerX, y: p.top),
        ),
        ChartLayout.left => horizontalDiagonal(
          s: (x: c.left, y: c.centerY),
          t: (x: p.right, y: p.centerY),
        ),
        ChartLayout.right => horizontalDiagonal(
          s: (x: c.right, y: c.centerY),
          t: (x: p.left, y: p.centerY),
        ),
      };
      links.add(
        LinkLayout(childId: node.id, parentId: parent.id, commands: commands),
      );
    }

    // 6) Bounds.
    var minL = double.infinity, minT = double.infinity;
    var maxR = double.negativeInfinity, maxB = double.negativeInfinity;
    for (final r in rectById.values) {
      if (r.left < minL) minL = r.left;
      if (r.top < minT) minT = r.top;
      if (r.right > maxR) maxR = r.right;
      if (r.bottom > maxB) maxB = r.bottom;
    }
    return ChartState<T>(
      nodes: nodes,
      links: links,
      bounds: LayoutRect(minL, minT, maxR - minL, maxB - minT),
    );
  }
}

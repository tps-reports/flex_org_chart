import 'flextree.dart';

/// Port of d3-org-chart's compact-mode passes
/// (calculateCompactFlexDimensions / calculateCompactFlexPositions),
/// REF src/d3-org-chart.js:757-830, in "top"-layout space.
class CompactLayout<T> {
  CompactLayout({
    required this.nodeWidth,
    required this.nodeHeight,
    required this.compactMarginBetween,
    required this.compactMarginPair,
  });

  final double Function(FlexNode<T>) nodeWidth;
  final double Function(FlexNode<T>) nodeHeight;
  final double compactMarginBetween;
  final double compactMarginPair;

  /// Call before [FlexTreeLayout.run]. Marks which leaf children of
  /// multi-child parents get grouped into a compact 2-column block, and
  /// sets [FlexNode.flexCompactDim] on the block's first child to the
  /// block's overall (width, height). Callers must use flexCompactDim as
  /// the node's xSize/ySize when it is non-null (see the golden test's
  /// `size()` helper for the exact substitution the fixture generator uses).
  void computeDimensions(FlexNode<T> root) {
    for (final node in _preorder(root)) {
      node
        ..firstCompact = false
        ..compactEven = null
        ..flexCompactDim = null
        ..firstCompactNode = null;
    }
    for (final node in _preorder(root)) {
      if (node.children.length <= 1) continue;
      final compactChildren = node.children
          .where((d) => d.children.isEmpty)
          .toList();
      if (compactChildren.length < 2) continue;
      for (var i = 0; i < compactChildren.length; i++) {
        final child = compactChildren[i];
        if (i == 0) child.firstCompact = true;
        child.compactEven = i.isEven;
        child.row = i ~/ 2;
      }
      final evenMax = compactChildren
          .where((d) => d.compactEven == true)
          .map(nodeWidth)
          .reduce((a, b) => a > b ? a : b);
      final oddNodes = compactChildren
          .where((d) => d.compactEven == false)
          .toList();
      final oddMax = oddNodes.isEmpty
          ? 0.0
          : oddNodes.map(nodeWidth).reduce((a, b) => a > b ? a : b);
      final columnSize = (evenMax > oddMax ? evenMax : oddMax) * 2;
      final rowHeights = <int, double>{};
      for (final d in compactChildren) {
        final h = nodeHeight(d) + compactMarginBetween;
        if (h > (rowHeights[d.row] ?? double.negativeInfinity)) {
          rowHeights[d.row] = h;
        }
      }
      final rowSize = rowHeights.values.fold(0.0, (a, b) => a + b);
      for (final child in compactChildren) {
        child.firstCompactNode = compactChildren.first;
        child.flexCompactDim = child.firstCompact
            ? [columnSize + compactMarginPair, rowSize - compactMarginBetween]
            : [0, 0];
      }
      node.flexCompactDim = null;
    }
  }

  /// Call after [FlexTreeLayout.run]. Repositions each compact block's
  /// members within the space the block's (fake, doubled-width) node
  /// occupied, arranging them into the zig-zag two-column grid.
  void computePositions(FlexNode<T> root) {
    for (final node in _preorder(root)) {
      if (node.children.isEmpty) continue;
      final compactChildren = node.children
          .where((d) => d.flexCompactDim != null)
          .toList();
      if (compactChildren.isEmpty) continue;
      final fch = compactChildren.first;
      for (var i = 0; i < compactChildren.length; i++) {
        final child = compactChildren[i];
        if (i == 0) fch.x -= fch.flexCompactDim![0] / 2;
        if (i > 0 && i.isEven) {
          // JS: `if (i & i % 2 - 1)` — truthy exactly for even i >= 2.
          child.x =
              fch.x + fch.flexCompactDim![0] * 0.25 - compactMarginPair / 4;
        } else if (i > 0) {
          child.x =
              fch.x + fch.flexCompactDim![0] * 0.75 + compactMarginPair / 4;
        }
      }
      final centerX = fch.x + fch.flexCompactDim![0] * 0.5;
      fch.x = fch.x + fch.flexCompactDim![0] * 0.25 - compactMarginPair / 4;
      final offsetX = node.x - centerX;
      if (offsetX.abs() < 10) {
        for (final d in compactChildren) {
          d.x += offsetX;
        }
      }
      final rowHeights = <int, double>{};
      for (final d in compactChildren) {
        final h = nodeHeight(d);
        if (h > (rowHeights[d.row] ?? double.negativeInfinity)) {
          rowHeights[d.row] = h;
        }
      }
      final rowKeys = rowHeights.keys.toList()..sort();
      final cumSum = <double>[];
      var acc = 0.0;
      for (final k in rowKeys) {
        acc += rowHeights[k]! + compactMarginBetween;
        cumSum.add(acc);
      }
      for (final child in compactChildren) {
        child.y = child.row > 0 ? fch.y + cumSum[child.row - 1] : fch.y;
      }
    }
  }

  Iterable<FlexNode<T>> _preorder(FlexNode<T> t) sync* {
    yield t;
    for (final c in t.children) {
      yield* _preorder(c);
    }
  }
}

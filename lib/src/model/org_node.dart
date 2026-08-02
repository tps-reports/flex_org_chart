/// A single node in the org tree, wrapping one item of caller data `T`
/// together with its position in the hierarchy and its expansion/highlight
/// state.
///
/// Instances are created by `stratify` and owned thereafter by
/// `OrgChartController`; application code should treat [isExpanded],
/// [isHighlighted], and [isOnHighlightedPath] as read-only and drive them
/// through the controller's methods instead of mutating them directly.
class OrgNode<T> {
  /// Internal constructor used by `stratify` to build the tree. Not part of
  /// the public construction API — nodes are always produced by stratifying
  /// a flat data list through `OrgChartController`.
  OrgNode.internal({required this.id, required this.data});

  /// The node's unique id, as returned by the `idOf` callback.
  final String id;

  /// The caller-supplied data item this node wraps.
  final T data;

  /// This node's parent, or `null` if it is a root.
  OrgNode<T>? parent;

  /// This node's direct children, in the order they appeared in the source
  /// data.
  final List<OrgNode<T>> children = [];

  /// Whether this node's children are currently shown. Managed by
  /// `OrgChartController` — do not mutate from app code.
  bool isExpanded = false;

  /// Whether this node is the current highlight target. Managed by
  /// `OrgChartController` — do not mutate from app code.
  bool isHighlighted = false;

  /// Whether this node lies on the ancestor path to the current highlight
  /// target. Managed by `OrgChartController` — do not mutate from app code.
  bool isOnHighlightedPath = false;

  /// Distance from the tree's root: `0` for a root node, otherwise one more
  /// than its parent's depth.
  int get depth => parent == null ? 0 : parent!.depth + 1;

  /// Number of immediate children.
  int get directSubordinates => children.length;

  /// Total number of descendants at any depth below this node.
  int get totalSubordinates {
    var n = 0;
    void walk(OrgNode<T> node) {
      for (final c in node.children) {
        n++;
        walk(c);
      }
    }

    walk(this);
    return n;
  }

  /// This node followed by every descendant, in depth-first pre-order.
  Iterable<OrgNode<T>> get descendants sync* {
    yield this;
    for (final c in children) {
      yield* c.descendants;
    }
  }

  /// This node's ancestors, nearest first, ending at (and including) the
  /// root. Empty for a root node.
  Iterable<OrgNode<T>> get ancestors sync* {
    var p = parent;
    while (p != null) {
      yield p;
      p = p.parent;
    }
  }
}

/// The result of stratifying a flat data list: every root [OrgNode] plus an
/// id index over the whole tree.
class OrgTree<T> {
  /// Internal constructor used by `stratify` to build the tree.
  OrgTree.internal(this.roots, this._byId);

  /// The tree's root nodes (nodes with no parent id), in source order.
  final List<OrgNode<T>> roots;
  final Map<String, OrgNode<T>> _byId;

  /// Looks up any node in the tree by id, at any depth, or `null` if no
  /// node has that id.
  OrgNode<T>? nodeById(String id) => _byId[id];

  /// Every node in the tree, roots and descendants alike, in depth-first
  /// pre-order per root.
  Iterable<OrgNode<T>> get allNodes => roots.expand((r) => r.descendants);
}

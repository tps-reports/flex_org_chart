class OrgNode<T> {
  OrgNode.internal({required this.id, required this.data});
  final String id;
  final T data;
  OrgNode<T>? parent;
  final List<OrgNode<T>> children = [];

  /// Managed by OrgChartController — do not mutate from app code.
  bool isExpanded = false;
  bool isHighlighted = false;
  bool isOnHighlightedPath = false;

  int get depth => parent == null ? 0 : parent!.depth + 1;
  int get directSubordinates => children.length;
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

  Iterable<OrgNode<T>> get descendants sync* {
    yield this;
    for (final c in children) {
      yield* c.descendants;
    }
  }

  Iterable<OrgNode<T>> get ancestors sync* {
    var p = parent;
    while (p != null) {
      yield p;
      p = p.parent;
    }
  }
}

class OrgTree<T> {
  OrgTree.internal(this.roots, this._byId);
  final List<OrgNode<T>> roots;
  final Map<String, OrgNode<T>> _byId;
  OrgNode<T>? nodeById(String id) => _byId[id];
  Iterable<OrgNode<T>> get allNodes => roots.expand((r) => r.descendants);
}

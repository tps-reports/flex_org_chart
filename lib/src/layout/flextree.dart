/// Port of the d3-flextree layout algorithm (WTFPL,
/// https://github.com/Klortho/d3-flextree), after A. van der Ploeg,
/// "Drawing Non-layered Tidy Trees in Linear Time" (2013).
class FlexNode<T> {
  FlexNode(this.item);
  final T item;
  FlexNode<T>? parent;
  final List<FlexNode<T>> children = [];

  /// Layout-space extent. Callers bake margins into these.
  double xSize = 0, ySize = 0;

  /// Outputs: x = center of the xSize box, y = top edge.
  double x = 0, y = 0;

  // Compact-mode annotations (set by the compact pass, Task 4).
  bool firstCompact = false;
  bool? compactEven;
  int row = 0;
  List<double>? flexCompactDim;
  FlexNode<T>? firstCompactNode;

  // van der Ploeg internals.
  double _prelim = 0, _mod = 0, _shift = 0, _change = 0;
  double _msel = 0, _mser = 0;
  FlexNode<T>? _tl, _tr; // left/right thread
  FlexNode<T>? _el, _er; // extreme left/right descendant
}

class _Iyl {
  _Iyl(this.lowY, this.index, this.next);
  final double lowY;
  final int index;
  final _Iyl? next;
}

class FlexTreeLayout<T> {
  FlexTreeLayout({required this.spacing});

  /// Extra horizontal separation between two nodes from different
  /// subtrees whose contours touch. Siblings usually return 0.
  final double Function(FlexNode<T> a, FlexNode<T> b) spacing;

  void run(FlexNode<T> root) {
    _resetAndSetY(root, 0);
    _firstWalk(root);
    _secondWalk(root, 0);
    _toCenterX(root);
    // d3-flextree normalizes the whole tree so the root's center x is
    // exactly 0 (see resolveX in the reference implementation, which always
    // resolves the root's relX/prelim to cancel out). Apply the same rigid
    // horizontal translation here.
    _shiftX(root, -root.x);
  }

  void _shiftX(FlexNode<T> t, double dx) {
    t.x += dx;
    for (final c in t.children) {
      _shiftX(c, dx);
    }
  }

  void _resetAndSetY(FlexNode<T> t, double y) {
    t
      ..y = y
      .._prelim = 0
      .._mod = 0
      .._shift = 0
      .._change = 0
      .._msel = 0
      .._mser = 0
      .._tl = null
      .._tr = null
      .._el = null
      .._er = null;
    for (final c in t.children) {
      _resetAndSetY(c, y + t.ySize);
    }
  }

  void _firstWalk(FlexNode<T> t) {
    if (t.children.isEmpty) {
      _setExtremes(t);
      return;
    }
    _firstWalk(t.children.first);
    var ih = _updateIyl(_bottom(t.children.first._el!), 0, null);
    for (var i = 1; i < t.children.length; i++) {
      _firstWalk(t.children[i]);
      final minY = _bottom(t.children[i]._er!);
      _separate(t, i, ih);
      ih = _updateIyl(minY, i, ih);
    }
    _positionRoot(t);
    _setExtremes(t);
  }

  void _setExtremes(FlexNode<T> t) {
    if (t.children.isEmpty) {
      t._el = t;
      t._er = t;
      t._msel = 0;
      t._mser = 0;
    } else {
      t._el = t.children.first._el;
      t._msel = t.children.first._msel;
      t._er = t.children.last._er;
      t._mser = t.children.last._mser;
    }
  }

  void _separate(FlexNode<T> t, int i, _Iyl ihIn) {
    _Iyl? ih = ihIn;
    FlexNode<T>? sr = t.children[i - 1];
    var mssr = sr._mod;
    FlexNode<T>? cl = t.children[i];
    var mscl = cl._mod;
    while (sr != null && cl != null) {
      if (_bottom(sr) > ih!.lowY) ih = ih.next;
      final dist =
          (mssr + sr._prelim + sr.xSize) -
          (mscl + cl._prelim) +
          spacing(sr, cl);
      if (dist > 0) {
        mscl += dist;
        _moveSubtree(t, i, ih!.index, dist);
      }
      final sy = _bottom(sr);
      final cy = _bottom(cl);
      if (sy <= cy) {
        sr = _nextRightContour(sr);
        if (sr != null) mssr += sr._mod;
      }
      if (sy >= cy) {
        cl = _nextLeftContour(cl);
        if (cl != null) mscl += cl._mod;
      }
    }
    if (sr == null && cl != null) {
      _setLeftThread(t, i, cl, mscl);
    } else if (sr != null && cl == null) {
      _setRightThread(t, i, sr, mssr);
    }
  }

  void _moveSubtree(FlexNode<T> t, int i, int si, double dist) {
    final c = t.children[i];
    c._mod += dist;
    c._msel += dist;
    c._mser += dist;
    _distributeExtra(t, i, si, dist);
  }

  FlexNode<T>? _nextLeftContour(FlexNode<T> t) =>
      t.children.isEmpty ? t._tl : t.children.first;
  FlexNode<T>? _nextRightContour(FlexNode<T> t) =>
      t.children.isEmpty ? t._tr : t.children.last;
  double _bottom(FlexNode<T> t) => t.y + t.ySize;

  void _setLeftThread(FlexNode<T> t, int i, FlexNode<T> cl, double modsumcl) {
    final li = t.children.first._el!;
    li._tl = cl;
    final diff = (modsumcl - cl._mod) - t.children.first._msel;
    li._mod += diff;
    li._prelim -= diff;
    t.children.first._el = t.children[i]._el;
    t.children.first._msel = t.children[i]._msel;
  }

  void _setRightThread(FlexNode<T> t, int i, FlexNode<T> sr, double modsumsr) {
    final ri = t.children[i]._er!;
    ri._tr = sr;
    final diff = (modsumsr - sr._mod) - t.children[i]._mser;
    ri._mod += diff;
    ri._prelim -= diff;
    t.children[i]._er = t.children[i - 1]._er;
    t.children[i]._mser = t.children[i - 1]._mser;
  }

  void _positionRoot(FlexNode<T> t) {
    t._prelim =
        (t.children.first._prelim +
                t.children.first._mod +
                t.children.last._mod +
                t.children.last._prelim +
                t.children.last.xSize) /
            2 -
        t.xSize / 2;
  }

  void _secondWalk(FlexNode<T> t, double modsum) {
    modsum += t._mod;
    t.x = t._prelim + modsum; // left edge, converted to center later
    _addChildSpacing(t);
    for (final c in t.children) {
      _secondWalk(c, modsum);
    }
  }

  void _distributeExtra(FlexNode<T> t, int i, int si, double dist) {
    if (si != i - 1) {
      final nr = (i - si).toDouble();
      t.children[si + 1]._shift += dist / nr;
      t.children[i]._shift -= dist / nr;
      t.children[i]._change -= dist - dist / nr;
    }
  }

  void _addChildSpacing(FlexNode<T> t) {
    var d = 0.0;
    var modsumdelta = 0.0;
    for (final c in t.children) {
      d += c._shift;
      modsumdelta += d + c._change;
      c._mod += modsumdelta;
    }
  }

  _Iyl _updateIyl(double minY, int i, _Iyl? ih) {
    while (ih != null && minY >= ih.lowY) {
      ih = ih.next;
    }
    return _Iyl(minY, i, ih);
  }

  void _toCenterX(FlexNode<T> t) {
    t.x += t.xSize / 2;
    for (final c in t.children) {
      _toCenterX(c);
    }
  }
}

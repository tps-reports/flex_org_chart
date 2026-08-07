import '../model/chart_group.dart';
import '../model/geometry.dart';
import '../model/org_node.dart';

/// A [ChartGroup] resolved against one frame's node rects: the padded
/// bounding box to paint, plus the root's depth for outer-before-inner
/// paint ordering.
class GroupHull {
  /// Creates a resolved hull for [group].
  const GroupHull({
    required this.group,
    required this.rect,
    required this.rootDepth,
  });

  /// The declared group this hull was computed for.
  final ChartGroup group;

  /// The padded union of the group's member rects, in layout space.
  final LayoutRect rect;

  /// Depth of the group's root node (root = 0). Hulls are sorted
  /// ascending on this so outer boxes paint before (beneath) inner ones.
  final int rootDepth;
}

/// Resolves [groups] against one frame's [memberRects] (node id → that
/// frame's rect — during layout animations these are the lerped rects, so
/// hulls animate with the nodes).
///
/// Per group: the root is looked up via [nodeById] (unknown id → skipped);
/// a root with no rect this frame (hidden behind a collapsed ancestor and
/// not animating) produces no hull; otherwise the hull is the union of
/// every member rect present in [memberRects] — the root plus visible
/// descendants — inflated by [paddingOf] on all sides. Exiting nodes still
/// present in the frame's rects are included, which is what makes a
/// collapsing department's box shrink with its members.
///
/// Returned hulls are sorted outer-first (ascending root depth) so nested
/// boxes paint inner-on-top-of-outer.
List<GroupHull> computeGroupHulls<T>({
  required List<ChartGroup> groups,
  required Map<String, LayoutRect> memberRects,
  required OrgNode<T>? Function(String) nodeById,
  required double Function(ChartGroup) paddingOf,
}) {
  final hulls = <GroupHull>[];
  for (final g in groups) {
    final root = nodeById(g.rootId);
    if (root == null) continue;
    if (!memberRects.containsKey(root.id)) continue;
    double? left, top, right, bottom;
    for (final n in root.descendants) {
      final r = memberRects[n.id];
      if (r == null) continue;
      if (left == null || r.left < left) left = r.left;
      if (top == null || r.top < top) top = r.top;
      if (right == null || r.right > right) right = r.right;
      if (bottom == null || r.bottom > bottom) bottom = r.bottom;
    }
    // The containsKey check above guarantees at least the root contributed.
    final pad = paddingOf(g);
    hulls.add(
      GroupHull(
        group: g,
        rect: LayoutRect(
          left! - pad,
          top! - pad,
          (right! - left) + pad * 2,
          (bottom! - top) + pad * 2,
        ),
        rootDepth: root.depth,
      ),
    );
  }
  hulls.sort((a, b) => a.rootDepth.compareTo(b.rootDepth));
  return hulls;
}

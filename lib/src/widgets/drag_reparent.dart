import 'dart:ui' show Offset;

import '../model/chart_state.dart';
import '../model/geometry.dart';
import '../model/org_node.dart';

/// Immutable snapshot of an in-progress drag-to-reparent interaction.
/// The `OrgChart` widget holds exactly one nullable instance and replaces
/// it on every pointer update.
class DragState<T> {
  /// Creates a drag snapshot. All positions are in layout space (the same
  /// coordinate space as [ChartState] rects).
  const DragState({
    required this.node,
    required this.sourceRect,
    required this.grabOffset,
    required this.position,
    this.targetId,
  });

  /// The node being dragged.
  final OrgNode<T> node;

  /// [node]'s layout rect at the moment it was lifted.
  final LayoutRect sourceRect;

  /// Pointer offset within the node at lift — keeps the ghost anchored
  /// under the finger where it was grabbed rather than snapping its
  /// top-left corner to the pointer.
  final Offset grabOffset;

  /// Current pointer position, in layout space.
  final Offset position;

  /// Id of the currently resolved valid drop target, or `null` when the
  /// pointer is not over one.
  final String? targetId;

  /// Where the ghost's top-left corner renders, in layout space.
  Offset get ghostTopLeft => position - grabOffset;

  /// Copy with a new pointer position and/or target. [targetId] is a valid
  /// null state (pointer over empty space), so clearing it needs the
  /// explicit [clearTarget] flag.
  DragState<T> copyWith({
    Offset? position,
    String? targetId,
    bool clearTarget = false,
  }) => DragState(
    node: node,
    sourceRect: sourceRect,
    grabOffset: grabOffset,
    position: position ?? this.position,
    targetId: clearTarget ? null : (targetId ?? this.targetId),
  );
}

/// Resolves the drop target under [point] for [dragged]: the topmost
/// visible node (last in [ChartState.nodes] order, matching paint order)
/// whose rect contains [point].
///
/// Returns `null` — no target — when the topmost hit is the dragged node
/// itself or one of its descendants (re-parenting there would create a
/// cycle) or is vetoed by [canReparent]. An invalid topmost hit does NOT
/// fall through to nodes painted beneath it: the pointer is visually over
/// the invalid node, so targeting something hidden behind it would be
/// surprising.
OrgNode<T>? resolveDropTarget<T>({
  required ChartState<T> state,
  required OrgNode<T> dragged,
  required Pt point,
  bool Function(OrgNode<T> node, OrgNode<T> candidateParent)? canReparent,
}) {
  for (var i = state.nodes.length - 1; i >= 0; i--) {
    final n = state.nodes[i];
    final r = n.rect;
    if (point.x < r.left ||
        point.x > r.right ||
        point.y < r.top ||
        point.y > r.bottom) {
      continue;
    }
    // Topmost geometric hit found — validity decides target-or-nothing.
    final excluded = dragged.descendants.any((d) => d.id == n.node.id);
    if (excluded) return null;
    if (canReparent != null && !canReparent(dragged, n.node)) return null;
    return n.node;
  }
  return null;
}

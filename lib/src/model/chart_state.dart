import 'geometry.dart';
import 'org_node.dart';
import '../layout/link_geometry.dart';

/// A single [OrgNode] paired with its computed on-screen rectangle.
class NodeLayout<T> {
  /// Creates a layout entry pairing [node] with its laid-out [rect].
  const NodeLayout(this.node, this.rect);

  /// The node this layout entry describes.
  final OrgNode<T> node;

  /// The node's computed position and size, in layout-bounds space.
  final LayoutRect rect;
}

/// A parent-child connector line, described as a sequence of [PathCommand]s
/// from a child node to its parent.
class LinkLayout {
  /// Creates a link between [childId] and [parentId] described by [commands].
  const LinkLayout(
      {required this.childId, required this.parentId, required this.commands});

  /// Id of the child endpoint.
  final String childId;

  /// Id of the parent endpoint.
  final String parentId;

  /// Path commands describing the curved connector, in layout-bounds space.
  final List<PathCommand> commands;
}

/// An immutable snapshot of a chart's current layout: every visible node's
/// rectangle, every parent-child link, and the overall bounding box.
///
/// Produced by the layout engine and exposed via
/// `OrgChartController.state`/`OrgChartController.previousState`.
class ChartState<T> {
  /// Creates a chart state from its visible [nodes], parent-child [links],
  /// and overall [bounds].
  ChartState({required this.nodes, required this.links, required this.bounds})
      : _byId = {for (final n in nodes) n.node.id: n};

  /// Every currently visible node, with its laid-out rectangle.
  final List<NodeLayout<T>> nodes;

  /// Every parent-child link between currently visible nodes.
  final List<LinkLayout> links;

  /// The bounding box enclosing every node in [nodes].
  final LayoutRect bounds;

  final Map<String, NodeLayout<T>> _byId;

  /// Looks up a visible node's layout by id, or `null` if [id] is not
  /// currently visible (e.g. it is behind a collapsed ancestor).
  NodeLayout<T>? byId(String id) => _byId[id];

  /// A [ChartState] with no nodes, links, or bounds — the state before any
  /// data has been laid out.
  static ChartState<T> empty<T>() => ChartState(
      nodes: const [], links: const [], bounds: const LayoutRect(0, 0, 0, 0));
}

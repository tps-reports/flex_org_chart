import 'geometry.dart';
import 'org_node.dart';
import '../layout/link_geometry.dart';

class NodeLayout<T> {
  const NodeLayout(this.node, this.rect);
  final OrgNode<T> node;
  final LayoutRect rect;
}

class LinkLayout {
  const LinkLayout(
      {required this.childId, required this.parentId, required this.commands});
  final String childId;
  final String parentId;
  final List<PathCommand> commands;
}

class ChartState<T> {
  ChartState({required this.nodes, required this.links, required this.bounds})
      : _byId = {for (final n in nodes) n.node.id: n};
  final List<NodeLayout<T>> nodes;
  final List<LinkLayout> links;
  final LayoutRect bounds;
  final Map<String, NodeLayout<T>> _byId;
  NodeLayout<T>? byId(String id) => _byId[id];
  static ChartState<T> empty<T>() => ChartState(
      nodes: const [], links: const [], bounds: const LayoutRect(0, 0, 0, 0));
}

import '../model/org_chart_data_exception.dart';
import '../model/org_node.dart';

OrgTree<T> stratify<T>({
  required List<T> data,
  required String Function(T) idOf,
  required String? Function(T) parentIdOf,
}) {
  if (data.isEmpty) {
    throw OrgChartDataException('Cannot build a chart from empty data');
  }
  final byId = <String, OrgNode<T>>{};
  final dups = <String>[];
  for (final item in data) {
    final id = idOf(item);
    if (byId.containsKey(id)) {
      dups.add(id);
    } else {
      byId[id] = OrgNode.internal(id: id, data: item);
    }
  }
  if (dups.isNotEmpty) {
    throw OrgChartDataException('Duplicate node ids', offendingIds: dups);
  }
  final roots = <OrgNode<T>>[];
  final orphans = <String>[];
  for (final node in byId.values) {
    final pid = parentIdOf(node.data);
    if (pid == null || pid.isEmpty) {
      roots.add(node);
    } else if (pid == node.id || !byId.containsKey(pid)) {
      orphans.add(node.id);
    } else {
      node.parent = byId[pid];
      byId[pid]!.children.add(node);
    }
  }
  if (orphans.isNotEmpty) {
    throw OrgChartDataException('Nodes reference missing parent ids',
        offendingIds: orphans);
  }
  final reachable = <String>{};
  for (final r in roots) {
    for (final n in r.descendants) {
      reachable.add(n.id);
    }
  }
  if (reachable.length != byId.length) {
    throw OrgChartDataException('Cycle detected in parent references',
        offendingIds:
            byId.keys.where((id) => !reachable.contains(id)).toList());
  }
  return OrgTree.internal(roots, byId);
}

/// A user-declared visual connection between two nodes, independent of the
/// hierarchical parent/child tree (e.g. a dotted-line reporting relationship).
class Connection {
  const Connection({required this.from, required this.to, this.label});
  final String from;
  final String to;
  final String? label;
}

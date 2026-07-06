/// A user-declared visual connection between two nodes, independent of the
/// hierarchical parent/child tree (e.g. a dotted-line reporting relationship).
class Connection {
  /// Creates a connection between the nodes with id [from] and [to],
  /// optionally labeled.
  const Connection({required this.from, required this.to, this.label});

  /// Id of the source node, matching whatever `idOf` returns for it.
  final String from;

  /// Id of the target node, matching whatever `idOf` returns for it.
  final String to;

  /// Optional text drawn alongside the connection's arc.
  final String? label;
}

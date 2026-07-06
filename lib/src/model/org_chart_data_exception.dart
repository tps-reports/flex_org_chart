/// Thrown by `stratify` (and surfaced via `OrgChartController.dataError`)
/// when the input data cannot be assembled into a valid tree: empty data,
/// duplicate ids, references to missing parent ids, or a parent-id cycle.
class OrgChartDataException implements Exception {
  /// Creates a data exception with a human-readable [message] and the
  /// specific node ids ([offendingIds]) that caused it, if any.
  OrgChartDataException(this.message, {this.offendingIds = const []});

  /// Human-readable description of what is wrong with the data.
  final String message;

  /// Ids of the nodes responsible for the error (duplicates, orphans, or
  /// nodes caught in a cycle). Empty when the error isn't attributable to
  /// specific ids (e.g. empty data).
  final List<String> offendingIds;

  @override
  String toString() =>
      'OrgChartDataException: $message'
      '${offendingIds.isEmpty ? '' : ' (ids: ${offendingIds.join(', ')})'}';
}

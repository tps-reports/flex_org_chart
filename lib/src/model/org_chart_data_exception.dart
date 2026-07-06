class OrgChartDataException implements Exception {
  OrgChartDataException(this.message, {this.offendingIds = const []});
  final String message;
  final List<String> offendingIds;
  @override
  String toString() =>
      'OrgChartDataException: $message'
      '${offendingIds.isEmpty ? '' : ' (ids: ${offendingIds.join(', ')})'}';
}

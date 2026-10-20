import 'models.dart';
import 'l10n_catalog.dart';

// Built-in defect labels have English aliases without rewriting stored data.
final _defectAliases = <String, String>{
  for (final source in ['表面划痕', '边缘缺口', '孔位偏移', '层间裂纹', '尺寸偏差', '表面气孔'])
    source: englishMessages[source]!.toLowerCase(),
};

/// Membership/order are fixed; records remain references to the workspace.
/// Use AppStore.captureCsv when an independent export snapshot is needed.
class RecordQueryResult {
  final List<Inspection> records;
  final Set<String> ids;

  RecordQueryResult._(List<Inspection> matches)
    : records = List.unmodifiable(matches),
      ids = Set.unmodifiable(matches.map((record) => record.id));
}

typedef _Filters = ({
  String query,
  String status,
  String? stationId,
  bool archived,
  bool newest,
  int? startMicros,
  int? endMicros,
});

/// One result per page, without retained search-text copies or query history.
/// AppStore replaces the workspace on commits. In-place edits to existing
/// records must advance revision; replacing/reordering list items also counts
/// as an edit even if the list length stays unchanged.
class RecordQueryCache {
  Workspace? _workspace;
  List<Inspection>? _inspections;
  int? _count, _revision, _session;
  _Filters? _filters;
  RecordQueryResult? _result;

  RecordQueryResult resolve({
    required Workspace workspace,
    required int revision,
    required int session,
    String query = '',
    String status = 'all',
    String? stationId,
    bool archived = false,
    bool newest = true,
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    assert((firstDate == null) == (lastDate == null));
    // Resolve each time so a device timezone change cannot reuse old bounds.
    // The day after the end date is a calendar day, not a 24-hour duration.
    final start = firstDate == null ? null : localDay(firstDate);
    final end = lastDate == null ? null : localDay(lastDate, 1);
    final filters = (
      query: query.toLowerCase(),
      status: status,
      stationId: stationId,
      archived: archived,
      newest: newest,
      startMicros: start?.microsecondsSinceEpoch,
      endMicros: end?.microsecondsSinceEpoch,
    );
    final inspections = workspace.inspections;
    if (_result != null &&
        identical(_workspace, workspace) &&
        identical(_inspections, inspections) &&
        _count == inspections.length &&
        _revision == revision &&
        _session == session &&
        _filters == filters) {
      return _result!;
    }
    final matches =
        inspections.where((r) {
          return r.archived == archived &&
              (stationId == null || r.stationId == stationId) &&
              (start == null || !r.at.isBefore(start)) &&
              (end == null || r.at.isBefore(end)) &&
              (switch (status) {
                'pass' => r.finalPassed,
                'fail' => !r.finalPassed,
                'pending' => r.pending,
                _ => true,
              }) &&
              (filters.query.isEmpty ||
                  '${r.serial} ${r.id} ${r.defect} ${r.recipeName} ${r.note} ${r.operatorName}'
                      .toLowerCase()
                      .contains(filters.query) ||
                  (_defectAliases[r.defect]?.contains(filters.query) ?? false));
        }).toList()..sort(
          (a, b) => newest ? b.at.compareTo(a.at) : a.at.compareTo(b.at),
        );
    final result = RecordQueryResult._(matches);
    _workspace = workspace;
    _inspections = inspections;
    _count = inspections.length;
    _revision = revision;
    _session = session;
    _filters = filters;
    return _result = result;
  }
}

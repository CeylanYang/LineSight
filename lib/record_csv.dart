import 'models.dart';

const csvColumns = [
  '记录 ID',
  '序列号',
  '工位',
  '检测时间（UTC）',
  '配方快照',
  '原始结果',
  '缺陷',
  '置信度',
  '复核结果',
  '复核人',
  '复核时间（UTC）',
  '依据',
  '操作员',
  '示例',
  '已归档',
];

// Only immutable scalar values are captured. Later record edits or station
// renames cannot change the selection, order or labels already being previewed.
class CsvRecord {
  final List<Object> values;
  CsvRecord(Inspection r, String stationName)
    : values = List.unmodifiable([
        r.id,
        r.serial,
        stationName,
        r.at,
        r.recipeName,
        r.passed ? 'PASS' : 'FAIL',
        r.defect,
        r.confidence,
        r.review ?? '',
        r.reviewer ?? '',
        r.reviewedAt ?? '',
        r.note,
        r.operatorName,
        r.sample,
        r.archived,
      ]);
  String get id => values[0] as String;
  String get serial => values[1] as String;
  DateTime get at => values[3] as DateTime;
  bool get sample => values[13] as bool;
  bool get archived => values[14] as bool;
}

class CsvSnapshot {
  final List<CsvRecord> records;
  final DateTime capturedAt;
  CsvSnapshot(Iterable<Inspection> source, Map<String, String> stations)
    : capturedAt = DateTime.now(),
      records = List.unmodifiable(
        source.map((r) {
          final name = stations[r.stationId];
          if (name == null) throw const FormatException('记录关联的工位不存在');
          return CsvRecord(r, name);
        }),
      ) {
    if (records.length > 100000 ||
        records.map((r) => r.id).toSet().length != records.length) {
      throw const FormatException('导出记录超出限制或包含重复 ID');
    }
  }
  Iterable<AuditTarget> get targets =>
      records.map((r) => AuditTarget('record', r.id, r.serial));
}

final _formulaPrefix = RegExp(r'^[\x00-\x20\s\uFEFF]*[=+@\-]|^[\t\r\n]');

String csvCell(Object value) {
  var text = value is DateTime ? instantJson(value) : '$value';
  if (_formulaPrefix.hasMatch(text)) text = "'$text";
  return '"${text.replaceAll('"', '""')}"';
}

// Each yielded value is at most one row. Keep BOM, CRLF and no trailing newline
// compatible with earlier exports, without materializing the complete document.
Iterable<String> csvChunks(CsvSnapshot snapshot) sync* {
  yield '\uFEFF${csvColumns.map(csvCell).join(',')}';
  for (final record in snapshot.records) {
    yield '\r\n${record.values.map(csvCell).join(',')}';
  }
}

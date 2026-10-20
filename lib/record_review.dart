import 'dart:convert';
import 'models.dart';

/// Immutable evidence/version captured when a review form is read or rebased.
/// Other workspace edits do not invalidate this record's review form.
class ReviewRecordVersion {
  final String recordId;
  final String _snapshot;

  ReviewRecordVersion.capture(Inspection record)
    : recordId = record.id,
      _snapshot = _encode(record);

  bool matches(Inspection record) =>
      record.id == recordId && _snapshot == _encode(record);

  // Use the same model round trip as AppStore commits, including UTC instants
  // and canonical recipe fields, so map insertion order cannot cause a conflict.
  static String _encode(Inspection record) =>
      jsonEncode(Inspection.fromJson(record.toJson()).toJson());
}

String? reviewNoteError(String value) {
  if (value.trim().length < 3) return '请填写至少 3 个字的复核依据';
  if (value.length > 2000) return '复核依据不能超过 2000 个字符';
  return null;
}

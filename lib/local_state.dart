import 'dart:convert';
import 'backup.dart';
import 'models.dart';

/// Fully validated startup state. The store applies it only after any legacy
/// migration has committed. No database handle or authenticated session crosses
/// the worker boundary.
class DecodedLocalState {
  final Workspace workspace;
  final Json preferences;
  final RestorePointInfo? restorePoint;
  final BackupReceipt? lastBackup;
  final List<TimeMigrationArchive> timeArchives;
  final Map<String, String> migrationWrites;

  DecodedLocalState({
    required this.workspace,
    required this.preferences,
    required this.restorePoint,
    required this.lastBackup,
    required List<TimeMigrationArchive> timeArchives,
    required Map<String, String> migrationWrites,
  }) : timeArchives = List.unmodifiable(timeArchives),
       migrationWrites = Map.unmodifiable(migrationWrites);
}

/// Pure decoding/validation for compute(). Each stored JSON document is decoded
/// once. Canonical startup neither serializes nor rewrites the working model.
DecodedLocalState decodeLocalState(List<Map<String, Object?>> rows) {
  final values = {
    for (final row in rows) row['key'] as String: row['value'] as String,
  };
  if (!values.containsKey('workspace')) {
    throw const FormatException('本机工作区缺失');
  }
  final archives =
      (values['timeArchives'] == null
              ? <dynamic>[]
              : jsonDecode(values['timeArchives']!) as List)
          .map((j) => TimeMigrationArchive.fromJson(Json.from(j)))
          .toList();
  for (final archive in archives) {
    parseInstant(archive.capturedAt);
  }
  final originals = <String, String>{};
  final decoded = <String, Json>{};
  Workspace? workspace;
  RestorePointInfo? point;
  RestorePointInfo? metadata;
  BackupReceipt? receipt;
  var count = 0;
  for (final key in [
    'workspace',
    'restorePoint',
    'restorePointMeta',
    'backupReceipt',
  ]) {
    final source = values[key];
    if (source == null) continue;
    originals[key] = source;
    final j = Json.from(jsonDecode(source));
    decoded[key] = j;
    if (key == 'workspace' || key == 'restorePoint') {
      count += normalizeWorkspaceTimes(j, localGapCompatibility: true);
      final model = Workspace.fromJson(j)..validate();
      if (key == 'workspace') {
        workspace = model;
      } else {
        // The full point is validated here; only its small summary is retained.
        point = RestorePointInfo.legacy(model);
      }
    } else if (key == 'restorePointMeta') {
      count += normalizeTimeField(j, 'createdAt', localGapCompatibility: true);
      metadata = RestorePointInfo.fromJson(j);
    } else {
      count += normalizeTimeField(j, 'savedAt', localGapCompatibility: true);
      receipt = BackupReceipt.fromJson(j);
    }
  }
  // Validate preferences before producing any durable migration writes.
  final preferences = values['preferences'] == null
      ? <String, dynamic>{}
      : Json.from(jsonDecode(values['preferences']!));
  final writes = <String, String>{};
  if (count > 0) {
    final now = DateTime.now();
    archives.add(
      TimeMigrationArchive(
        id: uid(),
        capturedAt: instantJson(now),
        zoneName: now.timeZoneName,
        offsetMinutes: now.timeZoneOffset.inMinutes,
        count: count,
        originals: originals,
      ),
    );
    writes['timeArchives'] = jsonEncode(
      archives.map((a) => a.toJson()).toList(),
    );
    for (final entry in decoded.entries) {
      // Preserve unknown fields, just as the original migration did.
      writes[entry.key] = jsonEncode(entry.value);
    }
  }
  return DecodedLocalState(
    workspace: workspace!,
    preferences: preferences,
    restorePoint: point == null ? null : metadata ?? point,
    lastBackup: receipt,
    timeArchives: archives,
    migrationWrites: writes,
  );
}

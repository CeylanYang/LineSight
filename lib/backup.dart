import 'dart:convert';
import 'models.dart';

const maxBackupBytes = 20 * 1024 * 1024;
const maxArchiveBytes = 256 * 1024 * 1024;

class LegacyTimeChoice {
  final int? offsetMinutes;
  const LegacyTimeChoice.local() : offsetMinutes = null;
  const LegacyTimeChoice.fixed(int minutes) : offsetMinutes = minutes;
  String get label => offsetMinutes == null
      ? '本机时区历史规则'
      : '固定 ${utcOffsetLabel(offsetMinutes!)}';
}

String fileSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';

class BackupDocument {
  final Workspace workspace;
  final DateTime? exportedAt;
  final int bytes;
  final int legacyTimeCount;
  final LegacyTimeChoice? legacyChoice;
  final String? _legacySource;
  final String? deviceZoneAtResolution;
  final String? legacyExample;
  final DateTime? interpretedExample;
  final String format;
  final String? checksum;
  const BackupDocument(
    this.workspace, {
    this.exportedAt,
    required this.bytes,
    this.legacyTimeCount = 0,
    this.legacyChoice,
    this.deviceZoneAtResolution,
    this.legacyExample,
    this.interpretedExample,
    this.format = 'JSON',
    this.checksum,
    String? legacySource,
  }) : _legacySource = legacySource;
  bool get readyToRestore => legacyTimeCount == 0 || legacyChoice != null;
  String? get timeInterpretation => legacyTimeCount == 0
      ? null
      : '$legacyTimeCount 个无时区时间 · ${legacyChoice?.label ?? '待选择'}'
            '${deviceZoneAtResolution == null ? '' : '（$deviceZoneAtResolution）'}';

  BackupDocument resolveLegacyTimes(LegacyTimeChoice choice) =>
      _legacySource == null ? this : _parse(_legacySource, choice);

  static String encode(Workspace workspace) {
    workspace.validate();
    // Compact JSON keeps the complete history while avoiding indentation overhead.
    final source = jsonEncode({
      'app': 'LineSight',
      'schema': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'workspace': workspace.toJson(),
    });
    if (utf8.encode(source).length > maxBackupBytes) {
      throw StateError('兼容 JSON 超过 20 MB，请选择完整备份（LSB），可保留全部记录与日志。');
    }
    return source;
  }

  factory BackupDocument.parse(String source) => _parse(source, null);

  static BackupDocument _parse(String source, LegacyTimeChoice? choice) {
    final size = utf8.encode(source).length;
    if (size > maxBackupBytes) throw const FormatException('备份不能超过 20 MB');
    try {
      final j = jsonDecode(source);
      if (j['app'] != 'LineSight' || j['schema'] != 1) {
        throw const FormatException('不支持的备份格式或版本');
      }
      // Unresolved legacy fields are provisional UTC for validation only.
      // The restore UI withholds comparison/confirmation until a choice is made.
      final offset = choice == null ? 0 : choice.offsetMinutes;
      String? example;
      void sample(Object? value) {
        if (example == null && value is String && !hasTimeZone(value)) {
          example = value;
        }
      }

      for (final row in j['workspace']['inspections'] as List) {
        sample(row['at']);
        sample(row['reviewedAt']);
        if (example != null) break;
      }
      if (example == null) {
        for (final row in j['workspace']['audits'] as List) {
          sample(row['at']);
          if (example != null) break;
        }
      }
      sample(j['exportedAt']);
      var count = normalizeWorkspaceTimes(
        j['workspace'],
        legacyOffsetMinutes: offset,
      );
      count += normalizeTimeField(j, 'exportedAt', legacyOffsetMinutes: offset);
      final w = Workspace.fromJson(Json.from(j['workspace']));
      w.validate();
      final date = j['exportedAt'];
      return BackupDocument(
        w,
        bytes: size,
        exportedAt: date == null ? null : parseInstant(date as String),
        legacyTimeCount: count,
        legacyChoice: choice,
        deviceZoneAtResolution: choice != null && choice.offsetMinutes == null
            ? '${DateTime.now().timeZoneName}；选择时 ${utcOffsetLabel(DateTime.now().timeZoneOffset.inMinutes)}'
            : null,
        legacySource: count == 0 ? null : source,
        legacyExample: example,
        interpretedExample: example == null
            ? null
            : parseInstant(example!, legacyOffsetMinutes: offset),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份内容不完整或字段格式无效');
    }
  }
}

enum RestoreChangeKind { added, changed, removed }

class RestoreChange {
  final String type, id, label;
  final RestoreChangeKind kind;
  final Json? before, after;
  const RestoreChange(
    this.type,
    this.id,
    this.label,
    this.kind,
    this.before,
    this.after,
  );
  String get actionLabel => switch (kind) {
    RestoreChangeKind.added => '新增',
    RestoreChangeKind.changed => '替换',
    RestoreChangeKind.removed => '移除',
  };
}

class RestoreComparison {
  final List<RestoreChange> changes;
  final int unchanged, newAudits, duplicateAudits, conflictingAudits;
  RestoreComparison._(
    this.changes,
    this.unchanged,
    this.newAudits,
    this.duplicateAudits,
    this.conflictingAudits,
  );

  int count(RestoreChangeKind kind, {String? type}) => changes
      .where((c) => c.kind == kind && (type == null || c.type == type))
      .length;

  factory RestoreComparison(Workspace current, Workspace incoming) {
    final changes = <RestoreChange>[];
    var unchanged = 0;
    void compare(
      String type,
      List<Json> before,
      List<Json> after,
      String labelKey,
    ) {
      final old = {for (final row in before) row['id'] as String: row};
      final next = {for (final row in after) row['id'] as String: row};
      for (final id in {...old.keys, ...next.keys}) {
        final a = old[id], b = next[id];
        if (a != null && b != null && jsonEncode(a) == jsonEncode(b)) {
          unchanged++;
          continue;
        }
        changes.add(
          RestoreChange(
            type,
            id,
            (b ?? a)![labelKey] as String,
            a == null
                ? RestoreChangeKind.added
                : b == null
                ? RestoreChangeKind.removed
                : RestoreChangeKind.changed,
            a,
            b,
          ),
        );
      }
    }

    compare(
      '检测记录',
      current.inspections.map((r) => r.toJson()).toList(),
      incoming.inspections.map((r) => r.toJson()).toList(),
      'serial',
    );
    compare(
      '配方',
      current.recipes.map((r) => r.toJson()).toList(),
      incoming.recipes.map((r) => r.toJson()).toList(),
      'name',
    );
    compare(
      '工位',
      current.stations.map((r) => r.toJson()).toList(),
      incoming.stations.map((r) => r.toJson()).toList(),
      'name',
    );
    final localAudits = {for (final a in current.audits) a.id: a};
    var newAudits = 0, duplicates = 0, conflicts = 0;
    for (final a in incoming.audits) {
      final local = localAudits[a.id];
      if (local == null) {
        newAudits++;
      } else if (jsonEncode(local.toJson()) == jsonEncode(a.toJson())) {
        duplicates++;
      } else {
        conflicts++;
      }
    }
    return RestoreComparison._(
      List.unmodifiable(changes),
      unchanged,
      newAudits,
      duplicates,
      conflicts,
    );
  }
}

class RestorePointInfo {
  final String id, actor;
  final DateTime? createdAt;
  final int records, recipes, stations;
  const RestorePointInfo({
    required this.id,
    required this.actor,
    this.createdAt,
    required this.records,
    required this.recipes,
    required this.stations,
  });
  factory RestorePointInfo.capture(Workspace w, String actor) =>
      RestorePointInfo(
        id: uid(),
        actor: actor,
        createdAt: DateTime.now(),
        records: w.inspections.length,
        recipes: w.recipes.length,
        stations: w.stations.length,
      );
  factory RestorePointInfo.legacy(Workspace w) => RestorePointInfo(
    id: 'legacy',
    actor: '旧版还原点',
    records: w.inspections.length,
    recipes: w.recipes.length,
    stations: w.stations.length,
  );
  factory RestorePointInfo.fromJson(Json j) => RestorePointInfo(
    id: j['id'],
    actor: j['actor'],
    createdAt: j['createdAt'] == null ? null : parseInstant(j['createdAt']),
    records: j['records'],
    recipes: j['recipes'],
    stations: j['stations'],
  );
  Json toJson() => {
    'id': id,
    'actor': actor,
    'createdAt': createdAt == null ? null : instantJson(createdAt!),
    'records': records,
    'recipes': recipes,
    'stations': stations,
  };
}

class BackupReceipt {
  final String actor, operationId;
  final DateTime savedAt;
  final int records;
  final String format;
  final int? bytes;
  final String? sha256;
  const BackupReceipt(
    this.actor,
    this.operationId,
    this.savedAt,
    this.records, {
    this.format = 'JSON',
    this.bytes,
    this.sha256,
  });
  factory BackupReceipt.fromJson(Json j) => BackupReceipt(
    j['actor'],
    j['operationId'],
    parseInstant(j['savedAt']),
    j['records'],
    format: j['format'] ?? 'JSON',
    bytes: j['bytes'],
    sha256: j['sha256'],
  );
  Json toJson() => {
    'actor': actor,
    'operationId': operationId,
    'savedAt': instantJson(savedAt),
    'records': records,
    'format': format,
    if (bytes != null) 'bytes': bytes,
    if (sha256 != null) 'sha256': sha256,
  };
}

// A separate, immutable local archive preserves the exact pre-upgrade strings.
// It is never included in normal backups or consumed by restore/undo.
class TimeMigrationArchive {
  final String id, capturedAt, zoneName;
  final int offsetMinutes, count;
  final Map<String, String> originals;
  TimeMigrationArchive({
    required this.id,
    required this.capturedAt,
    required this.zoneName,
    required this.offsetMinutes,
    required this.count,
    required Map<String, String> originals,
  }) : originals = Map.unmodifiable(originals);
  factory TimeMigrationArchive.fromJson(Json j) => TimeMigrationArchive(
    id: j['id'],
    capturedAt: j['capturedAt'],
    zoneName: j['zoneName'],
    offsetMinutes: j['offsetMinutes'],
    count: j['count'],
    originals: Map<String, String>.from(j['originals']),
  );
  Json toJson() => {
    'id': id,
    'capturedAt': capturedAt,
    'zoneName': zoneName,
    'offsetMinutes': offsetMinutes,
    'count': count,
    'originals': originals,
  };
  String backupSource(String key) {
    if (!['workspace', 'restorePoint'].contains(key) ||
        !originals.containsKey(key)) {
      throw StateError('旧版原件不存在');
    }
    final source =
        '{"app":"LineSight","schema":1,"workspace":${originals[key]}}';
    if (utf8.encode(source).length > maxBackupBytes) {
      throw StateError('旧版原件超过当前支持的 20 MB，请保留本机数据');
    }
    return source;
  }
}

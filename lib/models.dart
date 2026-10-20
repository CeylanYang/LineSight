import 'dart:math';
import 'time.dart';
export 'time.dart';

typedef Json = Map<String, dynamic>;

String uid() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 30).toRadixString(36)}';
String roleName(String role) => switch (role) {
  'admin' => '管理员',
  'engineer' => '质量工程师',
  _ => '操作员',
};

class LocalUser {
  final String id, username, name, role;
  final bool enabled;
  const LocalUser(this.id, this.username, this.name, this.role, this.enabled);
  factory LocalUser.fromJson(Json j) => LocalUser(
    j['id'],
    j['username'],
    j['name'],
    j['role'],
    j['enabled'] == 1,
  );
}

class Recipe {
  String id, name, version, material;
  double sensitivity, confidence;
  List<String> defects;
  Recipe({
    required this.id,
    required this.name,
    required this.version,
    required this.material,
    required this.sensitivity,
    required this.confidence,
    required this.defects,
  });
  factory Recipe.fromJson(Json j) => Recipe(
    id: j['id'],
    name: j['name'],
    version: j['version'],
    material: j['material'],
    sensitivity: (j['sensitivity'] as num).toDouble(),
    confidence: (j['confidence'] as num).toDouble(),
    defects: List<String>.from(j['defects']),
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'material': material,
    'sensitivity': sensitivity,
    'confidence': confidence,
    'defects': defects,
  };
  String get label => '$name · $version';
}

class Station {
  String id, name, line, recipeId;
  bool running;
  Station({
    required this.id,
    required this.name,
    required this.line,
    required this.recipeId,
    this.running = true,
  });
  factory Station.fromJson(Json j) => Station(
    id: j['id'],
    name: j['name'],
    line: j['line'],
    recipeId: j['recipeId'],
    running: j['running'],
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'line': line,
    'recipeId': recipeId,
    'running': running,
  };
}

class Inspection {
  String id, stationId, recipeName, serial, defect, note, operatorName;
  DateTime at;
  bool passed, archived, sample;
  double confidence;
  String? review, reviewer;
  DateTime? reviewedAt;
  Json recipeSnapshot;
  Inspection({
    required this.id,
    required this.stationId,
    required this.recipeName,
    required this.serial,
    required this.at,
    required this.passed,
    required this.defect,
    required this.confidence,
    required this.operatorName,
    this.note = '',
    this.review,
    this.reviewer,
    this.reviewedAt,
    this.recipeSnapshot = const {},
    this.archived = false,
    this.sample = true,
  });
  factory Inspection.fromJson(Json j) => Inspection(
    id: j['id'],
    stationId: j['stationId'],
    recipeName: j['recipeName'],
    serial: j['serial'],
    at: parseInstant(j['at']),
    passed: j['passed'],
    defect: j['defect'],
    confidence: (j['confidence'] as num).toDouble(),
    operatorName: j['operatorName'],
    recipeSnapshot:
        j['recipeSnapshot'] == null || (j['recipeSnapshot'] as Map).isEmpty
        ? {}
        : Recipe.fromJson(Json.from(j['recipeSnapshot'])).toJson(),
    note: j['note'],
    review: j['review'],
    reviewer: j['reviewer'],
    reviewedAt: j['reviewedAt'] == null ? null : parseInstant(j['reviewedAt']),
    archived: j['archived'],
    sample: j['sample'],
  );
  Json toJson() => {
    'id': id,
    'stationId': stationId,
    'recipeName': recipeName,
    'recipeSnapshot': recipeSnapshot,
    'serial': serial,
    'at': instantJson(at),
    'passed': passed,
    'defect': defect,
    'confidence': confidence,
    'operatorName': operatorName,
    'note': note,
    'review': review,
    'reviewer': reviewer,
    'reviewedAt': reviewedAt == null ? null : instantJson(reviewedAt!),
    'archived': archived,
    'sample': sample,
  };
  bool get pending => !passed && review == null && !archived;
  bool get finalPassed => review == null ? passed : review == 'pass';
}

class AuditTarget {
  final String type, id, label;
  const AuditTarget(this.type, this.id, this.label);
  factory AuditTarget.fromJson(Json j) =>
      AuditTarget(j['type'] as String, j['id'] as String, j['label'] as String);
  Json toJson() => {'type': type, 'id': id, 'label': label};
  String get typeLabel => switch (type) {
    'record' => '检测记录',
    'station' => '工位',
    'recipe' => '配方',
    'account' => '本机账户',
    _ => '关联对象',
  };
}

class AuditChange {
  final String field, before, after;
  const AuditChange(this.field, this.before, this.after);
  factory AuditChange.fromJson(Json j) => AuditChange(
    j['field'] as String,
    j['before'] as String,
    j['after'] as String,
  );
  Json toJson() => {'field': field, 'before': before, 'after': after};
}

class AuditEntry {
  final String id, actor, action, detail;
  final DateTime at;
  final String? actorId, operationId;
  final List<AuditTarget> targets;
  final List<AuditChange> changes;
  AuditEntry(
    this.id,
    this.actor,
    this.action,
    this.detail,
    this.at, {
    this.actorId,
    this.operationId,
    Iterable<AuditTarget> targets = const [],
    Iterable<AuditChange> changes = const [],
  }) : targets = List.unmodifiable(targets),
       changes = List.unmodifiable(changes);
  factory AuditEntry.fromJson(Json j) => AuditEntry(
    j['id'],
    j['actor'],
    j['action'],
    j['detail'],
    parseInstant(j['at']),
    actorId: j['actorId'] as String?,
    operationId: j['operationId'] as String?,
    targets: (j['targets'] as List? ?? []).map(
      (x) => AuditTarget.fromJson(Json.from(x)),
    ),
    changes: (j['changes'] as List? ?? []).map(
      (x) => AuditChange.fromJson(Json.from(x)),
    ),
  );

  bool relatesTo(String type, String targetId, {String? legacySerial}) {
    if (targets.isNotEmpty) {
      return targets.any((t) => t.type == type && t.id == targetId);
    }
    // Only the two old record actions contained an unambiguous identifier.
    // Count-only bulk events cannot be reliably assigned to individual records.
    return type == 'record' &&
        ((action == '质量复核' && detail.startsWith('$targetId · ')) ||
            (action == '模拟检测' &&
                legacySerial != null &&
                detail.contains(' · $legacySerial · ')));
  }

  Json toJson({bool includeChildren = true}) => {
    'id': id,
    'actor': actor,
    'action': action,
    'detail': detail,
    'at': instantJson(at),
    if (actorId != null) 'actorId': actorId,
    if (operationId != null) 'operationId': operationId,
    if (includeChildren && targets.isNotEmpty)
      'targets': targets.map((t) => t.toJson()).toList(),
    if (includeChildren && changes.isNotEmpty)
      'changes': changes.map((c) => c.toJson()).toList(),
  };
}

class Workspace {
  List<Recipe> recipes;
  List<Station> stations;
  List<Inspection> inspections;
  List<AuditEntry> audits;
  Workspace({
    required this.recipes,
    required this.stations,
    required this.inspections,
    required this.audits,
  });
  factory Workspace.fromJson(Json j) => Workspace(
    recipes: (j['recipes'] as List)
        .map((x) => Recipe.fromJson(Json.from(x)))
        .toList(),
    stations: (j['stations'] as List)
        .map((x) => Station.fromJson(Json.from(x)))
        .toList(),
    inspections: (j['inspections'] as List)
        .map((x) => Inspection.fromJson(Json.from(x)))
        .toList(),
    audits: (j['audits'] as List)
        .map((x) => AuditEntry.fromJson(Json.from(x)))
        .toList(),
  );
  Json toJson() => {
    'recipes': recipes.map((x) => x.toJson()).toList(),
    'stations': stations.map((x) => x.toJson()).toList(),
    'inspections': inspections.map((x) => x.toJson()).toList(),
    'audits': audits.map((x) => x.toJson()).toList(),
  };
  void validate() {
    if (recipes.isEmpty ||
        recipes.length > 200 ||
        stations.isEmpty ||
        stations.length > 100 ||
        inspections.length > 100000 ||
        audits.length > 100000) {
      throw const FormatException('数据规模超出限制，或缺少配方与工位');
    }
    void unique(Iterable<String> ids) {
      final all = ids.toList();
      if (all.any((x) => x.isEmpty || x.length > 100) ||
          all.toSet().length != all.length) {
        throw const FormatException('数据 ID 重复或无效');
      }
    }

    void validText(String value, int max) {
      if (value.trim().isEmpty || value.length > max) {
        throw const FormatException('字段内容为空或过长');
      }
    }

    unique(recipes.map((x) => x.id));
    unique(stations.map((x) => x.id));
    unique(inspections.map((x) => x.id));
    unique(audits.map((x) => x.id));
    for (final r in recipes) {
      validText(r.name, 80);
      validText(r.version, 30);
      validText(r.material, 80);
      if (!r.sensitivity.isFinite ||
          r.sensitivity < 0 ||
          r.sensitivity > 100 ||
          !r.confidence.isFinite ||
          r.confidence < .5 ||
          r.confidence > 1 ||
          r.defects.isEmpty ||
          r.defects.length > 20 ||
          r.defects.toSet().length != r.defects.length) {
        throw const FormatException('配方参数无效');
      }
      for (final d in r.defects) {
        validText(d, 40);
      }
    }
    for (final s in stations) {
      validText(s.name, 80);
      validText(s.line, 80);
      if (!recipes.any((r) => r.id == s.recipeId)) {
        throw const FormatException('工位引用了不存在的配方');
      }
    }
    for (final r in inspections) {
      validText(r.serial, 100);
      validText(r.recipeName, 120);
      validText(r.operatorName, 80);
      if (r.recipeSnapshot.isNotEmpty) {
        final snapshot = Recipe.fromJson(r.recipeSnapshot);
        if (snapshot.label != r.recipeName ||
            !snapshot.sensitivity.isFinite ||
            snapshot.sensitivity < 0 ||
            snapshot.sensitivity > 100 ||
            !snapshot.confidence.isFinite ||
            snapshot.confidence < .5 ||
            snapshot.confidence > 1 ||
            snapshot.defects.isEmpty) {
          throw const FormatException('检测记录的配方快照无效');
        }
      }
      if (!stations.any((s) => s.id == r.stationId) ||
          !r.confidence.isFinite ||
          r.confidence < 0 ||
          r.confidence > 1 ||
          r.note.length > 2000 ||
          r.defect.length > 80 ||
          (!r.passed && r.defect.trim().isEmpty) ||
          ![null, 'pass', 'reject'].contains(r.review) ||
          (r.review != null && (r.reviewer == null || r.reviewedAt == null))) {
        throw const FormatException('检测记录格式或关联无效');
      }
    }
    for (final a in audits) {
      validText(a.actor, 80);
      validText(a.action, 80);
      validText(a.detail, 4096);
      if (a.actorId != null) validText(a.actorId!, 100);
      if (a.operationId != null) validText(a.operationId!, 100);
      if (a.changes.length > 30) throw const FormatException('日志变更字段过多');
      final fields = <String>{};
      for (final c in a.changes) {
        validText(c.field, 80);
        if (c.before.length > 4096 ||
            c.after.length > 4096 ||
            !fields.add(c.field)) {
          throw const FormatException('日志变更字段重复或内容过长');
        }
      }
      if (a.targets.length > 100000) {
        throw const FormatException('日志关联对象过多');
      }
      final targetKeys = <String>{};
      for (final t in a.targets) {
        validText(t.id, 100);
        validText(t.label, 200);
        if (!['record', 'station', 'recipe', 'account'].contains(t.type) ||
            !targetKeys.add('${t.type}:${t.id}')) {
          throw const FormatException('日志关联类型无效或关联对象重复');
        }
        // Historical targets may have been removed or belong to another device.
      }
    }
  }

  static Workspace seed({bool examples = true}) {
    final recipes = [
      Recipe(
        id: 'r1',
        name: 'BRK-1042',
        version: 'v3.2',
        material: '铝合金 · 支架',
        sensitivity: 80,
        confidence: .75,
        defects: ['表面划痕', '边缘缺口', '孔位偏移'],
      ),
      Recipe(
        id: 'r2',
        name: 'BRK-1021',
        version: 'v2.8',
        material: 'PLA · 结构件',
        sensitivity: 72,
        confidence: .8,
        defects: ['层间裂纹', '表面划痕'],
      ),
      Recipe(
        id: 'r3',
        name: 'IMP-0987',
        version: 'v1.9',
        material: '不锈钢 · 叶轮',
        sensitivity: 88,
        confidence: .85,
        defects: ['表面划痕', '边缘缺口'],
      ),
    ];
    final stations = List.generate(
      4,
      (i) => Station(
        id: 's${i + 1}',
        name: 'Station 0${i + 1}',
        line: 'LINE 03',
        recipeId: i == 2 ? 'r2' : 'r1',
        running: i != 3,
      ),
    );
    final now = DateTime.now();
    final inspections = examples
        ? List.generate(96, (i) {
            final fail = i % 9 == 0 || i % 17 == 0;
            final s = stations[i % 4];
            final r = recipes.firstWhere((r) => r.id == s.recipeId);
            return Inspection(
              id: 'sample-$i',
              stationId: s.id,
              recipeName: r.label,
              recipeSnapshot: Recipe.fromJson(r.toJson()).toJson(),
              serial: 'DEMO-${(104200 + i)}',
              at: now.subtract(Duration(minutes: i * 57)),
              passed: !fail,
              defect: fail ? r.defects[i % r.defects.length] : '',
              confidence: .86 + (i % 13) / 100,
              operatorName: '示例操作员',
              review: fail && i > 28 ? 'reject' : null,
              reviewer: fail && i > 28 ? '示例工程师' : null,
              reviewedAt: fail && i > 28
                  ? now.subtract(Duration(minutes: i * 57 - 10))
                  : null,
            );
          })
        : <Inspection>[];
    return Workspace(
      recipes: recipes,
      stations: stations,
      inspections: inspections,
      audits: [],
    );
  }
}

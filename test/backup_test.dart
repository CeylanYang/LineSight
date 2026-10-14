import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';

void main() {
  test('small file sizes retain their nonzero byte count', () {
    expect(fileSize(0), '0 B');
    expect(fileSize(35), '35 B');
    expect(fileSize(1024), '1.0 KB');
    expect(fileSize(1024 * 1024), '1.00 MB');
  });
  test('compact backup preserves all audit extensions and export metadata', () {
    final w = Workspace.seed();
    w.audits.add(
      AuditEntry(
        'event',
        '管理员',
        '质量复核',
        '依据已记录',
        DateTime.now(),
        actorId: 'actor',
        operationId: 'operation',
        targets: [
          AuditTarget(
            'record',
            w.inspections.first.id,
            w.inspections.first.serial,
          ),
        ],
        changes: [const AuditChange('复核结论', '未复核', '放行')],
      ),
    );
    final text = BackupDocument.encode(w),
        restored = BackupDocument.parse(text);
    expect(restored.workspace.toJson(), w.toJson());
    expect(restored.exportedAt, isNotNull);
    expect(restored.bytes, utf8.encode(text).length);
    expect(text, isNot(contains('\n  ')));
  });

  test(
    'old schema 1 backups without metadata or structured targets still load',
    () {
      final w = Workspace.seed(examples: false);
      w.audits.add(AuditEntry('old', '旧账户', '归档记录', '5 条记录', DateTime.now()));
      final doc = BackupDocument.parse(
        jsonEncode({'app': 'LineSight', 'schema': 1, 'workspace': w.toJson()}),
      );
      expect(doc.exportedAt, isNull);
      expect(doc.workspace.audits.single.targets, isEmpty);
      expect(
        doc.workspace.audits.single.relatesTo('record', 'anything'),
        isFalse,
      );
    },
  );

  test(
    'equal totals expose added, removed and modified objects independently',
    () {
      final current = Workspace.seed(), incoming = Workspace.seed();
      // Start from an exact snapshot to keep timestamps equal.
      final next = Workspace.fromJson(current.toJson());
      next.inspections.removeAt(0);
      final added = incoming.inspections.first..id = 'new-record';
      next.inspections.add(added);
      next.inspections.first.note = '备份中的复核依据';
      next.recipes.first.name = '更名配方';
      final diff = RestoreComparison(current, next);
      expect(next.inspections.length, current.inspections.length);
      expect(diff.count(RestoreChangeKind.added, type: '检测记录'), 1);
      expect(diff.count(RestoreChangeKind.removed, type: '检测记录'), 1);
      expect(diff.count(RestoreChangeKind.changed, type: '检测记录'), 1);
      expect(diff.count(RestoreChangeKind.changed, type: '配方'), 1);
      expect(current.inspections[1].note, isEmpty);
    },
  );

  test('audit preview separates new, identical and conflicting event IDs', () {
    final a = Workspace.seed(examples: false),
        b = Workspace.seed(examples: false);
    final now = DateTime.now();
    final common = AuditEntry('same', '人员', '登录', '相同日志', now);
    a.audits.addAll([common, AuditEntry('conflict', '本机', '登录', '本机原文', now)]);
    b.audits.addAll([
      common,
      AuditEntry('conflict', '导入', '登录', '不同原文', now),
      AuditEntry('new', '导入', '登录', '新日志', now),
    ]);
    final diff = RestoreComparison(a, b);
    expect(diff.newAudits, 1);
    expect(diff.duplicateAudits, 1);
    expect(diff.conflictingAudits, 1);
  });

  test(
    'backup read and write limits count UTF-8 bytes and reject unsupported size',
    () {
      final source = '你' * (maxBackupBytes ~/ 3 + 1);
      expect(source.length, lessThan(maxBackupBytes));
      expect(() => BackupDocument.parse(source), throwsFormatException);
      final w = Workspace.seed(examples: false);
      for (var i = 0; i < 1800; i++) {
        w.audits.add(
          AuditEntry('large-$i', '人员', '备注', '字' * 4096, DateTime.now()),
        );
      }
      expect(() => BackupDocument.encode(w), throwsStateError);
    },
  );

  test('invalid audit targets and change payloads are rejected', () {
    final w = Workspace.seed(examples: false);
    w.audits.add(
      AuditEntry(
        'bad',
        '人员',
        '修改',
        '无效对象',
        DateTime.now(),
        targets: [const AuditTarget('unknown', 'id', 'label')],
      ),
    );
    expect(w.validate, throwsFormatException);
    w.audits.clear();
    w.audits.add(
      AuditEntry(
        'bad',
        '人员',
        '修改',
        '重复字段',
        DateTime.now(),
        changes: [
          const AuditChange('名称', 'a', 'b'),
          const AuditChange('名称', 'b', 'c'),
        ],
      ),
    );
    expect(w.validate, throwsFormatException);
  });
}

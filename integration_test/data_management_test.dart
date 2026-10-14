import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'restore points, stale previews and attributed exports persist atomically',
    (tester) async {
      final path = '${await getDatabasesPath()}/data-management-${uid()}.db';
      var s = AppStore();
      await s.init(path: path);
      await s.register('data.admin', '数据管理员', 'Data-password-42');
      await s.login('data.admin', 'Data-password-42');
      final originalActor = s.user!.id;
      await s.register('data.operator', '其他操作人', 'Operator-password-42');
      final record = s.pending.first;
      await s.review(record.id, 'pass', '核实后放行');
      await s.archive({record.id}, true);
      await s.archive({record.id}, false);
      final history = s.history('record', record.id);
      expect(
        history.map((a) => a.action),
        containsAll(['质量复核', '归档记录', '恢复记录']),
      );
      expect(
        history.where((a) => a.action == '质量复核').single.changes,
        isNotEmpty,
      );

      final stale = s.revision;
      await s.simulate('s1');
      await expectLater(
        s.restore(Workspace.seed(examples: false), expectedRevision: stale),
        throwsStateError,
      );
      expect(s.restorePoint, isNull);
      final count = s.data.inspections.length;
      final beforeIds = s.data.inspections.map((r) => r.id).toSet();
      final incoming = Workspace.seed(examples: false);
      await s.restore(incoming, expectedRevision: s.revision);
      expect(s.data.inspections, isEmpty);
      final point = s.restorePoint!;
      expect(point.records, count);
      expect(point.actor, '数据管理员');
      incoming.recipes.first.name = '外部修改不能进入工作区';
      expect(s.data.recipes.first.name, isNot(incoming.recipes.first.name));
      final savedPoint = await s.readRestorePoint(point.id);
      expect(savedPoint.inspections.map((r) => r.id).toSet(), beforeIds);
      await s.simulate('s1');
      final ticket = await s.beginExport('JSON 备份', s.data.inspections.length);
      s.lock();
      await s.login('data.operator', 'Operator-password-42');
      await s.finishExport(ticket, ExportOutcome.saved);
      expect(s.data.audits.last.actorId, originalActor);
      expect(s.data.audits.last.operationId, ticket.id);
      expect(s.lastBackup!.actor, '数据管理员');
      await expectLater(
        s.finishExport(ticket, ExportOutcome.saved),
        throwsStateError,
      );
      await expectLater(s.undoRestore(), throwsStateError);
      await s.signOut();
      await s.db.close();
      s.dispose();

      s = AppStore();
      await s.init(path: path);
      expect(s.restorePoint!.id, point.id);
      expect(s.lastBackup!.operationId, ticket.id);
      await s.login('data.admin', 'Data-password-42');
      final logCount = s.data.audits.length;
      await s.undoRestore(
        expectedPointId: point.id,
        expectedRevision: s.revision,
      );
      expect(s.data.inspections.map((r) => r.id).toSet(), beforeIds);
      expect(s.restorePoint, isNull);
      expect(s.data.audits.length, greaterThan(logCount));
      expect(
        await s.db.query(
          'state',
          where: 'key IN (?, ?)',
          whereArgs: ['restorePoint', 'restorePointMeta'],
        ),
        isEmpty,
      );
      final restored = BackupDocument.parse(s.backup()).workspace;
      expect(
        restored.audits.any((a) => a.targets.any((t) => t.id == record.id)),
        isTrue,
      );
      await s.restore(Workspace.seed(examples: false));
      await expectLater(
        s.undoRestore(expectedPointId: point.id),
        throwsStateError,
      );
      final stablePointId = s.restorePoint!.id;
      final stableRevision = s.revision;
      await s.db.execute(
        "CREATE TEMP TRIGGER reject_workspace BEFORE INSERT ON state "
        "WHEN NEW.key = 'workspace' BEGIN SELECT RAISE(ABORT, 'forced storage failure'); END",
      );
      await expectLater(
        s.restore(Workspace.seed()),
        throwsA(isA<DatabaseException>()),
      );
      expect(s.data.inspections, isEmpty);
      expect(s.restorePoint!.id, stablePointId);
      expect(s.revision, stableRevision);
      expect((await s.readRestorePoint(stablePointId)).inspections.length, 97);
      await s.db.execute('DROP TRIGGER reject_workspace');
      final cancelled = await s.beginExport('JSON 备份', 0);
      await s.finishExport(cancelled, ExportOutcome.cancelled);
      expect(s.lastBackup!.operationId, ticket.id);
      // Version 1.1.0 stored a snapshot without metadata.
      await s.db.delete(
        'state',
        where: 'key = ?',
        whereArgs: ['restorePointMeta'],
      );
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.restorePoint!.id, 'legacy');
      expect(s.restorePoint!.createdAt, isNull);
      await s.login('data.admin', 'Data-password-42');
      await s.undoRestore(expectedPointId: 'legacy');
      expect(s.data.inspections.length, 97);
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/state_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/stream_backup.dart';
import 'package:sqflite/sqflite.dart';
import '../test_support/workspace_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'large legacy SQLite cells upgrade, restore and reopen without lost history',
    (tester) async {
      final directory = await getDatabasesPath(),
          path = '$directory/large-${uid()}.db';
      var s = AppStore();
      await s.init(path: path);
      await s.register('large.admin', '备份管理员', 'Large-password-42');
      final fixture = archiveFixture(large: true);
      final raw = jsonEncode(fixture.toJson());
      expect(utf8.encode(raw).length, greaterThan(maxBackupBytes));
      // Recreate a version-1 database containing the formerly monolithic text cell.
      await s.db.insert('state', {
        'key': 'workspace',
        'value': raw,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await s.db.execute('DROP TABLE state_chunks');
      await s.db.execute('PRAGMA user_version = 1');
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNull);
      expect(s.data.toJson(), fixture.toJson());
      expect(await s.db.getVersion(), 3);
      await s.login('large.admin', 'Large-password-42');
      final header =
          (await s.db.query(
                'state',
                where: 'key = ?',
                whereArgs: ['workspace'],
              )).single['value']
              as String;
      expect(header, startsWith('LineSightState/2:'));
      expect(
        (await s.db.query(
          'state_chunks',
          columns: ['owner'],
          where: 'owner = ?',
          whereArgs: ['workspace'],
        )).length,
        greaterThan(1),
      );

      final unicode = 'A${'😀' * stateChunkUnits}';
      await s.db.transaction(
        (tx) => StateStorage.write(tx, 'unicode-check', unicode),
      );
      expect(
        await s.db.transaction((tx) => StateStorage.read(tx, 'unicode-check')),
        unicode,
      );
      await s.db.transaction((tx) => StateStorage.remove(tx, 'unicode-check'));

      final ids = s.data.inspections.map((r) => r.id).toSet();
      final revision = s.revision;
      await s.db.execute(
        "CREATE TEMP TRIGGER reject_chunk BEFORE INSERT ON state_chunks "
        "WHEN NEW.owner = 'workspace' AND NEW.part = 1 BEGIN SELECT RAISE(ABORT, 'forced chunk failure'); END",
      );
      await expectLater(
        s.restore(Workspace.seed(examples: false)),
        throwsA(isA<DatabaseException>()),
      );
      expect(s.revision, revision);
      expect(s.restorePoint, isNull);
      expect(s.data.inspections.map((r) => r.id).toSet(), ids);
      expect(
        await s.db.query(
          'state',
          columns: ['key'],
          where: 'key = ?',
          whereArgs: ['restorePoint'],
        ),
        isEmpty,
      );
      final persisted = await s.db.transaction(
        (tx) => StateStorage.read(tx, 'workspace'),
      );
      expect(
        Workspace.fromJson(
          jsonDecode(persisted!),
        ).inspections.map((r) => r.id).toSet(),
        ids,
      );
      await s.db.execute('DROP TRIGGER reject_chunk');

      final file = await ArchiveTask.write(
        s.data,
        '$directory/large-${uid()}.lsb',
      ).result;
      final document = await ArchiveTask.read(file.path).result;
      expect(document.workspace.toJson(), s.data.toJson());
      await s.restoreDocument(document, expectedRevision: s.revision);
      final point = s.restorePoint!.id;
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNull);
      expect(
        s.data.audits.where((a) => a.id.startsWith('archive-')).length,
        1800,
      );
      await s.login('large.admin', 'Large-password-42');
      expect(
        (await s.readRestorePoint(point)).inspections.map((r) => r.id).toSet(),
        ids,
      );
      await s.undoRestore(expectedPointId: point);
      expect(s.data.inspections.map((r) => r.id).toSet(), ids);
      expect(
        await s.db.query(
          'state_chunks',
          columns: ['owner'],
          where: 'owner = ?',
          whereArgs: ['restorePoint'],
        ),
        isEmpty,
      );

      // Removing one saved chunk must produce a recoverable startup error, never seed/reset.
      await s.db.delete(
        'state_chunks',
        where: 'owner = ? AND part = 1',
        whereArgs: ['workspace'],
      );
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNotNull);
      expect(await s.db.query('accounts'), isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
      // This is the exact generated fixture path in the disposable test database directory.
      await File(file.path).delete();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

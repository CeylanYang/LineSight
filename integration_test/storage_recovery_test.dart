import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/files.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/recovery_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/stream_backup.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'damaged state recovery authenticates, preserves raw bytes atomically and reopens',
    (tester) async {
      final directory = await getDatabasesPath(),
          id = uid(),
          path = '$directory/recovery-$id.db';
      var s = AppStore();
      await s.init(path: path);
      final code = await s.register(
        'repair.admin',
        '恢复管理员',
        'Repair-password-42',
      );
      await s.login('repair.admin', 'Repair-password-42');
      await s.register('repair.operator', '操作同事', 'Operator-password-42');
      await s.preference('dark', true);
      await s.preference('autoLock', false);
      final backup = BackupDocument.parse(s.backup());
      final credentials = await s.db.query(
        'accounts',
        columns: [
          'id',
          'username',
          'salt',
          'hash',
          'recoverySalt',
          'recoveryHash',
          'role',
          'enabled',
        ],
        orderBy: 'id',
      );
      final broken =
          '{${'质' * (1024 * 1024)}'; // > Android cursor-window capacity.
      await s.db.update(
        'state',
        {'value': broken},
        where: 'key = ?',
        whereArgs: ['workspace'],
      );
      await s.db.insert('state', {
        'key': 'backupReceipt',
        'value': '{broken receipt',
      });
      await s.db.execute(
        "INSERT INTO state (key, value) VALUES ('invalid-utf8', CAST(x'00FFFFC328' AS TEXT))",
      );
      await s.db.insert('state_chunks', {
        'owner': 'orphan',
        'part': 9,
        'value': '保留😀\u0000尾部',
      });
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNotNull);
      expect(s.ready, isFalse);
      expect(s.canRecoverStorage, isTrue);
      await s
          .init(); // Retry must retain the explicitly selected database path.
      expect(s.db.path, path);
      expect(s.startupError, isNotNull);
      await s.db.update(
        'accounts',
        {'enabled': 0},
        where: 'username = ?',
        whereArgs: ['repair.admin'],
      );
      await expectLater(
        s.loginForStorageRecovery('repair.admin', 'Repair-password-42'),
        throwsStateError,
      );
      await s.db.update(
        'accounts',
        {'enabled': 1},
        where: 'username = ?',
        whereArgs: ['repair.admin'],
      );
      await expectLater(
        s.login('repair.admin', 'Repair-password-42'),
        throwsStateError,
      );
      await expectLater(
        s.register('new.admin', '不能重建', 'Strong-password-42'),
        throwsStateError,
      );
      await expectLater(
        s.loginForStorageRecovery('repair.operator', 'Operator-password-42'),
        throwsStateError,
      );
      for (var i = 0; i < 5; i++) {
        await expectLater(
          s.loginForStorageRecovery('repair.admin', 'wrong-password'),
          throwsStateError,
        );
      }
      await expectLater(
        s.loginForStorageRecovery('repair.admin', code, recoveryCode: true),
        throwsStateError,
      );
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      await expectLater(
        s.loginForStorageRecovery('repair.admin', 'Repair-password-42'),
        throwsStateError,
      );
      // Advance the persisted test lock without waiting a minute.
      await s.db.update(
        'accounts',
        {'lockedUntil': 0},
        where: 'username = ?',
        whereArgs: ['repair.admin'],
      );
      await s.loginForStorageRecovery(
        'repair.admin',
        code.toLowerCase(),
        recoveryCode: true,
      );
      expect(s.user, isNull);
      expect(s.recoveryUser!.role, 'admin');
      expect(() => s.backup(), throwsStateError);
      await expectLater(s.simulate('s1'), throwsStateError);
      await expectLater(
        s.recoverStorage(
          backup,
          expectedSession: s.session,
          fileName: '完整备份.json',
          acknowledged: false,
        ),
        throwsStateError,
      );
      final unresolved = BackupDocument.parse(
        BackupDocument.encode(backup.workspace).replaceAll('Z"', '"'),
      );
      await expectLater(
        s.recoverStorage(
          unresolved,
          expectedSession: s.session,
          fileName: '旧备份.json',
          acknowledged: true,
        ),
        throwsStateError,
      );
      await s.db.execute(
        "CREATE TEMP TRIGGER reject_recovery BEFORE INSERT ON state WHEN NEW.key = 'workspace' BEGIN SELECT RAISE(ABORT, 'forced recovery failure'); END",
      );
      await expectLater(
        s.recoverStorage(
          backup,
          expectedSession: s.session,
          fileName: '完整备份.json',
          acknowledged: true,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await s.db.query('recovery_snapshots'), isEmpty);
      expect(await s.db.query('recovery_state', columns: ['key']), isEmpty);
      expect(await s.db.query('recovery_chunks', columns: ['owner']), isEmpty);
      expect(
        Sqflite.firstIntValue(
          await s.db.rawQuery(
            "SELECT length(CAST(value AS BLOB)) FROM state WHERE key = 'workspace'",
          ),
        ),
        utf8.encode(broken).length,
      );
      expect(s.startupError, isNotNull);
      await s.db.execute('DROP TRIGGER reject_recovery');
      final stale = s.session;
      s.lock();
      await expectLater(
        s.recoverStorage(
          backup,
          expectedSession: stale,
          fileName: '完整备份.json',
          acknowledged: true,
        ),
        throwsStateError,
      );
      await s.loginForStorageRecovery('repair.admin', 'Repair-password-42');
      await s.recoverStorage(
        backup,
        expectedSession: s.session,
        fileName: '完整备份.json',
        acknowledged: true,
      );
      expect(s.startupError, isNull);
      expect(s.ready, isTrue);
      expect(s.user, isNull);
      expect(s.recoveryUser, isNull);
      expect(s.dark, isTrue);
      expect(s.autoLock, isFalse);
      expect(s.restorePoint, isNull);
      expect(s.lastBackup, isNull);
      expect(
        s.data.inspections.map((r) => r.id),
        backup.workspace.inspections.map((r) => r.id),
      );
      expect(s.data.audits.last.action, '异常恢复');
      expect(
        await s.db.query(
          'accounts',
          columns: [
            'id',
            'username',
            'salt',
            'hash',
            'recoverySalt',
            'recoveryHash',
            'role',
            'enabled',
          ],
          orderBy: 'id',
        ),
        credentials,
      );
      await s.login('repair.admin', 'Repair-password-42');
      final history = await s.recoveryHistory();
      expect(history, hasLength(1));
      final original = await writeRecoveryOriginal(
        s.db,
        history.single.id,
        '$directory/original-$id.lsr',
      );
      final raw = await File(original.path).readAsBytes();
      expect(sha256.convert(raw).toString(), original.sha256);
      final lines = utf8.decode(raw).split('\n')..removeLast();
      expect(lines.removeAt(0), 'LINESIGHT-RECOVERY/1');
      final footer = jsonDecode(lines.removeLast()) as Map;
      final payload = utf8.encode(
        'LINESIGHT-RECOVERY/1\n${lines.join('\n')}\n',
      );
      expect(footer['bytes'], payload.length);
      expect(footer['sha256'], sha256.convert(payload).toString());
      final cells = <String, List<int>>{};
      String? current;
      var expectedBytes = 0, segment = 0;
      for (final line in lines.skip(1)) {
        final row = jsonDecode(line) as Map;
        if (row['type'] == 'cell') {
          current = row['table'] == 'state'
              ? 'state:${row['key']}'
              : 'chunks:${row['owner']}:${row['part']}';
          cells[current] = [];
          expectedBytes = row['bytes'];
          segment = 0;
        } else if (row['type'] == 'segment') {
          expect(row['index'], segment++);
          cells[current]!.addAll(base64Decode(row['base64']));
        } else if (row['type'] == 'endCell') {
          expect(cells[current]!.length, expectedBytes);
          expect(row['segments'], segment);
        }
      }
      expect(cells['state:workspace'], utf8.encode(broken));
      expect(cells['state:invalid-utf8'], [0, 255, 255, 195, 40]);
      expect(cells['chunks:orphan:9'], utf8.encode('保留😀\u0000尾部'));
      expect(utf8.decode(raw), isNot(contains(credentials.first['hash'])));
      await expectLater(readBackupFile(original.path), throwsFormatException);
      var cancel = false;
      final cancelPath = '$directory/cancel-original-$id.lsr';
      await expectLater(
        writeRecoveryOriginal(
          s.db,
          history.single.id,
          cancelPath,
          check: () {
            if (cancel) throw const BackupCancelled();
          },
          report: (_, _, _) => cancel = true,
        ),
        throwsA(isA<BackupCancelled>()),
      );
      expect(await File(cancelPath).exists(), isFalse);
      await expectLater(
        writeRecoveryOriginal(
          s.db,
          history.single.id,
          cancelPath,
          byteLimit: 256,
        ),
        throwsFormatException,
      );
      expect(await File(cancelPath).exists(), isFalse);
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNull);
      await s.login('repair.admin', 'Repair-password-42');
      expect((await s.recoveryHistory()).single.id, history.single.id);
      await s.signOut();
      await s.login('repair.operator', 'Operator-password-42');
      await expectLater(s.recoveryHistory(), throwsStateError);
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
      await File(original.path).delete();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'missing workspace blocks setup and unreadable accounts cannot authorize recovery',
    (tester) async {
      final path = '${await getDatabasesPath()}/missing-${uid()}.db';
      final s = AppStore();
      await s.init(path: path);
      await s.register('missing.admin', '管理员', 'Missing-password-42');
      await s.db.delete('state', where: 'key = ?', whereArgs: ['workspace']);
      await s.init();
      expect(s.startupError, isNotNull);
      expect(s.ready, isFalse);
      expect(s.canRecoverStorage, isTrue);
      await s.db.execute('ALTER TABLE accounts RENAME TO preserved_accounts');
      await s.init();
      expect(s.startupError, isNotNull);
      expect(s.canRecoverStorage, isFalse);
      await expectLater(
        s.loginForStorageRecovery('missing.admin', 'Missing-password-42'),
        throwsStateError,
      );
      expect(await s.db.query('preserved_accounts'), hasLength(1));
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
  );
}

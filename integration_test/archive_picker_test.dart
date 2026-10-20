import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/files.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/backup_transfer.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/stream_backup.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';
import '../test_support/workspace_fixtures.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'large native save verifies destination, survives locking and preserves receipt on cancel/failure',
    (tester) async {
      final path = '${await getDatabasesPath()}/archive-picker-${uid()}.db';
      var s = AppStore();
      await s.init(path: path);
      await s.register('archive.admin', '完整备份操作人', 'Archive-password-42');
      await s.login('archive.admin', 'Archive-password-42');
      await s.restore(archiveFixture(large: true));
      final expected = s.data.toJson(), actor = s.user!.id;
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      final name = 'linesight-large-${uid()}.lsb';
      await exportStreamBackup(
        tester.element(find.byType(AppShell)),
        name: name,
        onSaving: () => debugPrint('PICKER_STAGE:SAVE_LOCKED:$name'),
      );
      await tester.pumpAndSettle();
      expect(s.user, isNull);
      expect(s.lastBackup!.actor, '完整备份操作人');
      expect(s.lastBackup!.format, 'LSB 2');
      expect(s.lastBackup!.bytes, greaterThan(maxBackupBytes));
      expect(s.lastBackup!.sha256, hasLength(64));
      final operation = s.lastBackup!.operationId;
      expect(s.data.audits.last.actorId, actor);
      expect(s.data.audits.last.detail, contains('回读校验通过'));
      await s.login('archive.admin', 'Archive-password-42');
      await tester.pumpAndSettle();
      expect(s.fileNotice, contains('已保存'));
      debugPrint('PICKER_STAGE:OPEN_JSON:$name');
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      final document = await readBackupFile(selected!.files.single.path!);
      expect(document.workspace.toJson(), expected);
      expect(document.bytes, s.lastBackup!.bytes);
      await tester.pumpAndSettle();
      if (s.user == null) {
        await s.login('archive.admin', 'Archive-password-42');
        await tester.pumpAndSettle();
      }
      // Show and exercise the actual new export page, including native cancellation.
      openPage(tester.element(find.byType(AppShell)), const BackupExportPage());
      await tester.pumpAndSettle();
      expect(find.byType(BackupExportPage), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_ARCHIVE')) {
        await binding.convertFlutterSurfaceToImage();
        var done = false;
        final shot = binding
            .takeScreenshot('complete-backup')
            .whenComplete(() => done = true);
        for (var i = 0; i < 100 && !done; i++) {
          binding.scheduleForcedFrame();
          await tester.pump(const Duration(milliseconds: 100));
        }
        await shot.timeout(const Duration(seconds: 15));
      }
      debugPrint('PICKER_STAGE:CANCEL');
      await tester.scrollUntilVisible(
        find.text('保存完整备份'),
        240,
        scrollable: find
            .descendant(
              of: find.byType(BackupExportPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存完整备份'));
      for (var i = 0; i < 1800 && s.data.audits.last.action != '取消导出'; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(s.data.audits.last.action, '取消导出');
      expect(s.lastBackup!.operationId, operation);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      // Cancel preparation before a native picker is opened.
      await exportStreamBackup(
        tester.element(find.byType(AppShell)),
        onTask: (task) => task.cancel(),
      );
      expect(s.lastBackup!.operationId, operation);
      expect(s.data.audits.last.action, '取消导出');
      final scratch = await newBackupScratch();
      final small = await writeArchive(
        Workspace.seed(examples: false),
        '${scratch.path}/small.lsb',
      );
      debugPrint('PICKER_STAGE:SAVE_BAD:linesight-rejected-${uid()}.lsb');
      await expectLater(
        saveArchiveFile(
          PreparedArchive(small.path, small.bytes, '0' * 64),
          'linesight-rejected-${uid()}.lsb',
        ),
        throwsA(isA<PlatformException>()),
      );
      await removeBackupScratch(scratch);
      expect(await Directory(scratch.path).exists(), isFalse);
      expect(s.lastBackup!.operationId, operation);
      debugPrint('PICKER_STAGE:DONE');
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNull);
      expect(s.lastBackup!.operationId, operation);
      expect(s.lastBackup!.format, 'LSB 2');
      expect(s.lastBackup!.sha256, hasLength(64));
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/files.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/recovery_storage.dart';
import 'package:linesight_flutter/screens/auth.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/screens/storage_recovery.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/stream_backup.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'administrator recovery uses real pickers, locks and exports preserved originals',
    (tester) async {
      final id = uid(),
          path = '${await getDatabasesPath()}/repair-journey-$id.db';
      final s = AppStore();
      await s.init(path: path);
      await s.register('journey.admin', '本机管理员', 'Journey-password-42');
      await s.login('journey.admin', 'Journey-password-42');
      await s.preference('autoLock', false);
      final scratch = await newBackupScratch();
      final fixture = await writeArchive(s.data, '${scratch.path}/fixture.lsb');
      final name = 'repair-backup-$id.lsb';
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      debugPrint('PICKER_STAGE:SAVE_BACKUP:$name');
      expect(await saveArchiveFile(fixture, name), isTrue);
      await removeBackupScratch(scratch);
      await s.simulate('s1');
      await s.db.update(
        'state',
        {'value': '{broken workspace'},
        where: 'key = ?',
        whereArgs: ['workspace'],
      );
      await s.init();
      await tester.pumpAndSettle();
      expect(find.byType(StorageFailurePage), findsOneWidget);
      var surfaceReady = false;
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_RECOVERY')) return;
        if (!surfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          surfaceReady = true;
        }
        for (var i = 0; i < 4; i++) {
          binding.scheduleForcedFrame();
          await tester.pump(const Duration(milliseconds: 250));
        }
        await tester.pumpAndSettle();
        var done = false;
        final shot = binding
            .takeScreenshot(name)
            .whenComplete(() => done = true);
        for (var i = 0; i < 100 && !done; i++) {
          binding.scheduleForcedFrame();
          await tester.pump(const Duration(milliseconds: 100));
        }
        await shot.timeout(const Duration(seconds: 15));
      }

      Future<void> scroll(Finder target, Type page) async {
        await tester.scrollUntilVisible(
          target,
          220,
          scrollable: find
              .descendant(
                of: find.byType(page),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      Future<void> authenticate() async {
        await scroll(find.text('验证管理员'), StorageFailurePage);
        await tester.enterText(find.byType(TextField).first, 'journey.admin');
        await tester.enterText(
          find.byType(TextField).last,
          'Journey-password-42',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await scroll(find.text('验证管理员'), StorageFailurePage);
        await tester.tap(find.text('验证管理员'));
        for (
          var i = 0;
          i < 300 && find.byType(StorageRecoveryPage).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(find.byType(StorageRecoveryPage), findsOneWidget);
      }

      await capture('storage-failure');
      await authenticate();
      await capture('recovery-select-backup');
      // Invoke the actual UI callback and observe its error after native selection.
      // Normal auto-lock was disabled; recovery verification must still expire.
      debugPrint('PICKER_STAGE:OPEN_LOCKED:$name');
      final select = tester
          .widget<BusyButton>(
            find.ancestor(
              of: find.text('选择恢复备份'),
              matching: find.byType(BusyButton),
            ),
          )
          .onPressed!;
      await expectLater(select(), throwsStateError);
      await tester.pumpAndSettle();
      expect(s.recoveryUser, isNull);
      expect(find.byType(StorageFailurePage), findsOneWidget);
      expect(await s.db.query('recovery_snapshots'), isEmpty);
      await authenticate();
      debugPrint('PICKER_STAGE:OPEN_JSON:$name');
      await tester.tap(find.text('选择恢复备份'));
      for (
        var i = 0;
        i < 900 && find.byType(StorageRecoveryPreviewPage).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(StorageRecoveryPreviewPage), findsOneWidget);
      expect(find.text('SHA-256 通过'), findsOneWidget);
      await capture('recovery-preview');
      await scroll(find.text('已确认备份内容、时间解释和恢复影响'), StorageRecoveryPreviewPage);
      await tester.tap(find.text('已确认备份内容、时间解释和恢复影响'));
      await tester.pumpAndSettle();
      await scroll(find.text('保留原件并恢复'), StorageRecoveryPreviewPage);
      await tester.tap(find.text('保留原件并恢复'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '恢复工作区'));
      for (
        var i = 0;
        i < 300 && find.byType(AuthPage).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(AuthPage), findsOneWidget);
      expect(s.data.inspections.length, 96);
      expect(s.user, isNull);
      await s.login('journey.admin', 'Journey-password-42');
      await tester.pumpAndSettle();
      await s.preference('autoLock', true);
      openPage(tester.element(find.byType(AppShell)), const DataPage());
      await tester.pumpAndSettle();
      await scroll(find.text('查看恢复记录与恢复前原件'), DataPage);
      await tester.tap(find.text('查看恢复记录与恢复前原件'));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryHistoryPage), findsOneWidget);
      await capture('recovery-history');
      await tester.tap(find.widgetWithText(ListTile, name));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryOriginalPage), findsOneWidget);
      await s.preference('dark', true);
      await tester.pumpAndSettle();
      await capture('recovery-original-dark');
      final history = (await s.recoveryHistory()).single;
      final actorId = s.user!.id;
      debugPrint(
        'PICKER_STAGE:SAVE_LOCKED:LineSight-original-${history.id}.lsr',
      );
      await scroll(find.text('导出恢复前原件'), RecoveryOriginalPage);
      final export = tester
          .widget<BusyButton>(
            find.ancestor(
              of: find.text('导出恢复前原件'),
              matching: find.byType(BusyButton),
            ),
          )
          .onPressed!;
      await export();
      await tester.pumpAndSettle();
      expect(s.user, isNull);
      expect(s.data.audits.last.action, '导出数据');
      expect(s.data.audits.last.actorId, actorId);
      expect(s.data.audits.last.detail, contains('回读校验通过'));
      expect(s.data.audits.last.detail, contains(history.id));
      expect(s.lastBackup, isNull);
      await s.login('journey.admin', 'Journey-password-42');
      await tester.pumpAndSettle();
      expect(s.fileNotice, contains('恢复前原件已保存并回读校验'));
      debugPrint(
        'PICKER_STAGE:OPEN_ORIGINAL:LineSight-original-${history.id}.lsr',
      );
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      final received = await File(selected!.files.single.path!).readAsBytes();
      final expectedFile = await writeRecoveryOriginal(
        s.db,
        history.id,
        '${await getDatabasesPath()}/expected-$id.lsr',
      );
      expect(received, await File(expectedFile.path).readAsBytes());
      await File(expectedFile.path).delete();
      await tester.pumpAndSettle();
      if (s.user == null) {
        await s.login('journey.admin', 'Journey-password-42');
        await tester.pumpAndSettle();
      }
      openPage(
        tester.element(find.byType(AppShell)),
        RecoveryOriginalPage(snapshot: history),
      );
      await tester.pumpAndSettle();
      await scroll(find.text('导出恢复前原件'), RecoveryOriginalPage);
      debugPrint('PICKER_STAGE:CANCEL');
      final cancelExport = tester
          .widget<BusyButton>(
            find.ancestor(
              of: find.text('导出恢复前原件'),
              matching: find.byType(BusyButton),
            ),
          )
          .onPressed!;
      await cancelExport();
      await tester.pumpAndSettle();
      expect(s.data.audits.last.action, '取消导出');
      expect(s.lastBackup, isNull);
      debugPrint('PICKER_STAGE:DONE');
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

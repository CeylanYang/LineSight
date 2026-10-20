import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/backup_transfer.dart';
import 'package:linesight_flutter/screens/restore.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/stream_backup.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'verified LSB import reaches preview, restores and rejects corrupted input visibly',
    (tester) async {
      final directory = await getDatabasesPath(),
          id = uid(),
          path = '$directory/import-$id.db';
      final s = AppStore();
      await s.init(path: path);
      await s.register('import.admin', '恢复管理员', 'Import-password-42');
      await s.login('import.admin', 'Import-password-42');
      final archive = await writeArchive(s.data, '$directory/import-$id.lsb');
      await s.simulate('s1');
      expect(s.data.inspections.length, 97);
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      var surfaceReady = false;
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_ARCHIVE_IMPORT')) return;
        if (!surfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          surfaceReady = true;
        }
        // Flush the image surface before requesting a capture; otherwise the
        // native reader can return a previous route or theme-transition frame.
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

      openPage(tester.element(find.byType(AppShell)), const BackupExportPage());
      await tester.pumpAndSettle();
      await capture('backup-formats');
      await s.preference('dark', true);
      await tester.pumpAndSettle();
      final option = tester.widget<RichText>(
        find.descendant(
          of: find.text('完整备份 LSB'),
          matching: find.byType(RichText),
        ),
      );
      expect(option.text.style!.color!.computeLuminance(), greaterThan(.5));
      await capture('backup-formats-dark');
      await tester.tap(find.byType(BackButton).last);
      await s.preference('dark', false);
      await tester.pumpAndSettle();
      openPage(
        tester.element(find.byType(AppShell)),
        BackupImportPage(
          path: archive.path,
          name: '完整备份.lsb',
          session: s.session,
        ),
      );
      for (
        var i = 0;
        i < 300 && find.byType(RestorePreviewPage).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(RestorePreviewPage), findsOneWidget);
      expect(find.text('SHA-256 通过'), findsOneWidget);
      await capture('verified-import');
      await tester.scrollUntilVisible(
        find.text('确认恢复此备份'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(RestorePreviewPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认恢复此备份'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '恢复'));
      await tester.pumpAndSettle();
      expect(s.data.inspections.length, 96);
      expect(s.restorePoint!.records, 97);
      final revision = s.revision;
      final broken = File('$directory/broken-$id.lsb');
      final text = await File(archive.path).readAsString();
      await broken.writeAsString(text.replaceFirst('DEMO-', 'BAD--'));
      openPage(
        tester.element(find.byType(AppShell)),
        BackupImportPage(
          path: broken.path,
          name: '损坏备份.lsb',
          session: s.session,
        ),
      );
      for (var i = 0; i < 300 && find.text('备份未通过检查').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.text('备份未通过检查'), findsOneWidget);
      expect(s.revision, revision);
      expect(s.data.inspections.length, 96);
      await capture('rejected-import');
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      openPage(
        tester.element(find.byType(AppShell)),
        BackupImportPage(
          path: archive.path,
          name: '会话过期备份.lsb',
          session: s.session,
        ),
      );
      s.lock();
      await tester.pumpAndSettle();
      expect(find.byType(RestorePreviewPage), findsNothing);
      expect(s.revision, revision);
      expect(s.data.inspections.length, 96);
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
      await File(archive.path).delete();
      await broken.delete();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

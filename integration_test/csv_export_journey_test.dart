import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/files.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/audit.dart';
import 'package:linesight_flutter/screens/csv_export.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/stream_backup.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';
import '../test_support/csv_fixtures.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'CSV preview, large native save, actor locking and cancellation retain exact data',
    (tester) async {
      final path = '${await getDatabasesPath()}/csv-journey-${uid()}.db';
      var s = AppStore();
      await s.init(path: path);
      await s.register('csv.admin', 'CSV 导出管理员', 'Csv-password-42');
      await s.login('csv.admin', 'Csv-password-42');
      final w = csvFixture();
      w.inspections.first.note = '一行,"引号"\r\n第二行 😀';
      w.inspections.first.serial = ' =HYPERLINK("demo")';
      await s.restore(w);
      final receipt = await s.beginExport('JSON 备份', 4000);
      await s.finishExport(receipt, ExportOutcome.saved);
      final backupId = s.lastBackup!.operationId;
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      var surfaceReady = false;
      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_CSV')) return;
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
          240,
          scrollable: find
              .descendant(
                of: find.byType(page),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      Future<void> login() async {
        await s.login('csv.admin', 'Csv-password-42');
        await tester.pumpAndSettle();
      }

      openPage(tester.element(find.byType(AppShell)), const DataPage());
      await tester.pumpAndSettle();
      await scroll(find.text('导出全部 CSV'), DataPage);
      await tester.tap(find.text('导出全部 CSV'));
      await tester.pumpAndSettle();
      final page = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
      final snapshot = page.snapshot;
      expect(snapshot.records, hasLength(4000));
      expect(snapshot.records.where((r) => r.archived), hasLength(1334));
      await capture('csv-all');
      await s.preference('dark', true);
      await tester.pumpAndSettle();
      await capture('csv-preview-dark');
      await scroll(find.text('保存 CSV'), CsvExportPage);
      await capture('csv-fields');
      // A real transaction after preview must not alter the exported scalar snapshot.
      await s.review('csv-1', 'pass', '在导出预览之后增加的复核');
      expect(snapshot.records[1].values[8], '');
      final actorId = s.user!.id;
      final name =
          'LineSight-records-${snapshot.capturedAt.millisecondsSinceEpoch}.csv';
      debugPrint('PICKER_STAGE:SAVE_LOCKED:$name');
      final save = tester
          .widget<BusyButton>(
            find.ancestor(
              of: find.text('保存 CSV'),
              matching: find.byType(BusyButton),
            ),
          )
          .onPressed!;
      await save();
      await tester.pumpAndSettle();
      expect(s.user, isNull);
      final audit = s.data.audits.last;
      expect(audit.action, '导出数据');
      expect(audit.actorId, actorId);
      expect(audit.detail, contains('回读校验通过'));
      expect(audit.detail, contains('全部检测记录'));
      expect(audit.targets, hasLength(4000));
      expect(s.lastBackup!.operationId, backupId);
      final bytes = int.parse(
        audit.changes.singleWhere((c) => c.field == '文件字节数').after,
      );
      final digest = audit.changes
          .singleWhere((c) => c.field == 'SHA-256')
          .after;
      expect(bytes, greaterThan(maxBackupBytes));
      await login();
      expect(s.fileNotice, contains('CSV 已保存并回读校验，共 4000 条记录'));
      openPage(
        tester.element(find.byType(AppShell)),
        AuditDetailPage(id: audit.id),
      );
      await tester.pumpAndSettle();
      await scroll(find.text('文件校验'), AuditDetailPage);
      await capture('csv-audit');

      debugPrint('PICKER_STAGE:OPEN_CSV:$name');
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      final received = File(selected!.files.single.path!);
      expect(await received.length(), bytes);
      expect((await sha256.bind(received.openRead()).first).toString(), digest);
      final expected = await writeRecordCsv(
        snapshot,
        '${await getDatabasesPath()}/expected-${uid()}.csv',
      );
      expect(expected.sha256, digest);
      expect(expected.bytes, bytes);
      await File(expected.path).delete();
      await tester.pumpAndSettle();
      if (s.user == null) await login();
      Navigator.of(tester.element(find.byType(AuditDetailPage))).pop();
      await tester.pumpAndSettle();
      await s.preference('dark', false);
      await tester.pumpAndSettle();
      openPage(tester.element(find.byType(AppShell)), const RecordsScreen());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'CSV-000001');
      await tester.pumpAndSettle();
      await scroll(find.byTooltip('导出筛选结果 CSV'), RecordsScreen);
      await tester.tap(find.byTooltip('导出筛选结果 CSV'));
      await tester.pumpAndSettle();
      final filtered = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
      expect(filtered.snapshot.records.single.id, 'csv-1');
      expect(filtered.snapshot.records.single.values[8], 'pass');
      await capture('csv-filtered');
      await scroll(find.text('保存 CSV'), CsvExportPage);
      debugPrint('PICKER_STAGE:CANCEL');
      await tester
          .widget<BusyButton>(
            find.ancestor(
              of: find.text('保存 CSV'),
              matching: find.byType(BusyButton),
            ),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(s.data.audits.last.action, '取消导出');
      expect(find.text('保存 CSV'), findsOneWidget);
      expect(s.lastBackup!.operationId, backupId);

      // No picker can open after cancelled preparation or a stale session.
      final context = tester.element(find.byType(CsvExportPage));
      await exportRecords(
        context,
        snapshot,
        expectedSession: s.session,
        onTask: (task) => task.cancel(),
        onSaving: () => fail('Cancelled task opened a picker'),
      );
      expect(s.data.audits.last.action, '取消导出');
      final oldSession = s.session;
      s.lock();
      await tester.pumpAndSettle();
      await login();
      final unchanged = s.revision;
      await expectLater(
        exportRecords(
          tester.element(find.byType(AppShell)),
          snapshot,
          expectedSession: oldSession,
        ),
        throwsStateError,
      );
      expect(s.revision, unchanged);
      await exportRecords(
        tester.element(find.byType(AppShell)),
        snapshot,
        expectedSession: s.session,
        onTask: (_) => s.lock(),
        onSaving: () => fail('Locked preparation opened a picker'),
      );
      await tester.pumpAndSettle();
      expect(s.user, isNull);
      expect(s.data.audits.last.action, isNot('导出数据'));
      await login();
      final invalid = await s.beginExport('CSV', 1);
      await expectLater(
        s.finishExport(invalid, ExportOutcome.saved),
        throwsStateError,
      );
      expect(s.lastBackup!.operationId, backupId);
      final scratch = await newBackupScratch();
      final small = await writeRecordCsv(
        filtered.snapshot,
        '${scratch.path}/small.csv',
      );
      debugPrint('PICKER_STAGE:SAVE_BAD:rejected-csv-${uid()}.csv');
      await expectLater(
        saveArchiveFile(
          PreparedArchive(small.path, small.bytes, '0' * 64),
          'rejected-csv-${uid()}.csv',
        ),
        throwsA(isA<PlatformException>()),
      );
      await removeBackupScratch(scratch);
      expect(await scratch.exists(), isFalse);
      debugPrint('PICKER_STAGE:DONE');
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNull);
      expect(s.lastBackup!.operationId, backupId);
      expect(
        s.data.audits
            .singleWhere((a) => a.id == audit.id)
            .changes
            .singleWhere((c) => c.field == 'SHA-256')
            .after,
        digest,
      );
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

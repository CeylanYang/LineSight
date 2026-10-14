import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local calendar includes 23 and 25 hour days in New York', (
    tester,
  ) async {
    // Run on the disposable emulator set to America/New_York, never change host TZ.
    expect(DateTime(2026, 1).timeZoneOffset, const Duration(hours: -5));
    expect(DateTime(2026, 7).timeZoneOffset, const Duration(hours: -4));
    for (final (date, hours) in [
      (DateTime(2026, 3, 8), 23),
      (DateTime(2026, 11, 1), 25),
    ]) {
      final next = localDay(date, 1);
      expect(next.difference(date).inHours, hours);
      expect(
        inLocalDateRange(
          next.subtract(const Duration(microseconds: 1)).toUtc(),
          date,
          date,
        ),
        isTrue,
      );
      expect(inLocalDateRange(next.toUtc(), date, date), isFalse);
      expect(localDay(next, -1), date);
      final dates = List.generate(7, (i) => localDay(date, i));
      expect(
        dates.map((d) => '${d.year}-${d.month}-${d.day}').toSet().length,
        7,
      );
      expect(dates.every((d) => d.hour == 0), isTrue);
    }
    expect(stamp(DateTime.utc(2026, 3, 8, 4, 59)), '2026-03-07 23:59');
    expect(() => parseInstant('2026-03-08T02:30:00'), throwsFormatException);
    expect(
      parseInstant('2026-03-08T02:30:00', legacyOffsetMinutes: -300),
      DateTime.utc(2026, 3, 8, 7, 30),
    );
    expect(
      parseInstant('2026-11-01T01:30:00', legacyOffsetMinutes: -240),
      DateTime.utc(2026, 11, 1, 5, 30),
    );
    expect(
      parseInstant('2026-11-01T01:30:00', legacyOffsetMinutes: -300),
      DateTime.utc(2026, 11, 1, 6, 30),
    );
  });

  testWidgets(
    'migration preserves originals atomically and legacy restore needs a choice',
    (tester) async {
      final path = '${await getDatabasesPath()}/time-portability-${uid()}.db';
      var s = AppStore();
      await s.init(path: path);
      await s.register('time.admin', '时间管理员', 'Time-password-42');
      await s.login('time.admin', 'Time-password-42');
      final raw = s.data.toJson();
      raw['inspections'][0]['at'] = '2026-03-08T01:30:00.000';
      final original = jsonEncode(raw);
      final metadata = RestorePointInfo.capture(s.data, '时间管理员').toJson();
      metadata['createdAt'] = '2026-03-08T01:40:00.000';
      for (final (key, value) in [
        ('workspace', original),
        ('restorePoint', original),
        ('restorePointMeta', jsonEncode(metadata)),
        (
          'backupReceipt',
          jsonEncode({
            'actor': '时间管理员',
            'operationId': 'old-save',
            'savedAt': '2026-03-08T01:50:00.000',
            'records': 96,
          }),
        ),
      ]) {
        await s.db.insert('state', {
          'key': key,
          'value': value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      // A durable trigger forces failure after the archive insert inside the transaction.
      await s.db.execute(
        "CREATE TRIGGER reject_time_migration BEFORE INSERT ON state "
        "WHEN NEW.key = 'workspace' BEGIN SELECT RAISE(ABORT, 'forced migration failure'); END",
      );
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNotNull);
      expect(
        (await s.db.query(
          'state',
          where: 'key = ?',
          whereArgs: ['workspace'],
        )).single['value'],
        original,
      );
      expect(
        await s.db.query(
          'state',
          where: 'key = ?',
          whereArgs: ['timeArchives'],
        ),
        isEmpty,
      );
      await s.db.execute('DROP TRIGGER reject_time_migration');
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.startupError, isNull);
      expect(s.timeArchives.single.count, 4);
      final archive = s.timeArchives.single;
      expect(archive.originals['workspace'], original);
      expect(archive.originals['restorePoint'], original);
      expect(s.data.inspections.first.at, DateTime.utc(2026, 3, 8, 6, 30));
      expect(s.lastBackup!.savedAt, DateTime.utc(2026, 3, 8, 6, 50));
      expect(s.restorePoint!.createdAt, DateTime.utc(2026, 3, 8, 6, 40));
      await s.db.close();
      s.dispose();
      s = AppStore();
      await s.init(path: path);
      expect(s.timeArchives.single.id, archive.id);
      await s.login('time.admin', 'Time-password-42');
      final document = BackupDocument.parse(archive.backupSource('workspace'));
      await expectLater(() => s.restoreDocument(document), throwsStateError);
      final chosen = document.resolveLegacyTimes(
        const LegacyTimeChoice.fixed(480),
      );
      await s.restoreDocument(chosen, expectedRevision: s.revision);
      expect(s.data.inspections.first.at, DateTime.utc(2026, 3, 7, 17, 30));
      expect(s.data.audits.last.detail, contains('固定 UTC+08:00'));
      await s.undoRestore();
      expect(s.data.inspections.first.at, DateTime.utc(2026, 3, 8, 6, 30));
      expect(s.timeArchives.single.originals['workspace'], original);

      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      openPage(tester.element(find.byType(AppShell)), const TimeStoragePage());
      await tester.pumpAndSettle();
      expect(find.text('时间与日期'), findsOneWidget);
      expect(find.text('已解释的旧时间'), findsOneWidget);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      openPage(
        tester.element(find.byType(AppShell)),
        RestorePreviewPage(
          incoming: document.workspace,
          document: document,
          fileName: '升级前原件.json',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('确认恢复此备份'), findsNothing);
      Future<void> reveal(Finder target, {double delta = 220}) async {
        await tester.scrollUntilVisible(
          target,
          delta,
          scrollable: find
              .descendant(
                of: find.byType(RestorePreviewPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
      }

      final dropdown = find.byType(DropdownButtonFormField<String>);
      await reveal(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('固定 UTC+08:00').last);
      await tester.pumpAndSettle();
      await reveal(find.text('确认恢复此备份'));
      // Comparison is visible but restore stays disabled until the explicit acknowledgement.
      expect(
        tester
            .widget<BusyButton>(find.widgetWithText(BusyButton, '确认恢复此备份'))
            .onPressed,
        isNull,
      );
      await reveal(find.byType(CheckboxListTile), delta: -220);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('CAPTURE_TIME')) {
        await tester.ensureVisible(find.text('旧备份时间'));
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        var done = false;
        final shot = binding
            .takeScreenshot('legacy-time-preview')
            .whenComplete(() => done = true);
        for (var i = 0; i < 100 && !done; i++) {
          binding.scheduleForcedFrame();
          await tester.pump(const Duration(milliseconds: 100));
        }
        await shot.timeout(const Duration(seconds: 15));
      }
      await reveal(find.text('确认恢复此备份'));
      await tester.tap(find.text('确认恢复此备份'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('时间解释：1 个无时区时间'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '恢复'));
      await tester.pumpAndSettle();
      expect(s.data.inspections.first.at, DateTime.utc(2026, 3, 7, 17, 30));
      expect(s.data.audits.last.detail, contains('固定 UTC+08:00'));
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/auth.dart';
import 'package:linesight_flutter/screens/storage_recovery.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'legacy recovery requires visible timezone choice and retains invalid auxiliary originals',
    (tester) async {
      final path = '${await getDatabasesPath()}/legacy-repair-${uid()}.db';
      final s = AppStore();
      await s.init(path: path);
      await s.register('legacy.admin', '管理员', 'Legacy-password-42');
      await s.login('legacy.admin', 'Legacy-password-42');
      final document = BackupDocument.parse(s.backup().replaceAll('Z"', '"'));
      final resolved = document.resolveLegacyTimes(
        const LegacyTimeChoice.fixed(480),
      );
      final invalidArchive = jsonEncode([
        {
          'id': 'invalid-time',
          'capturedAt': 'not-a-date',
          'zoneName': 'GMT',
          'offsetMinutes': 0,
          'count': 1,
          'originals': {'workspace': 'original text'},
        },
      ]);
      await s.db.insert('state', {
        'key': 'timeArchives',
        'value': invalidArchive,
      });
      await s.db.insert('state', {
        'key': 'preferences',
        'value': '{bad preferences',
      });
      await s.init();
      expect(s.startupError, isNotNull);
      await s.loginForStorageRecovery('legacy.admin', 'Legacy-password-42');
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      openPage(
        tester.element(find.byType(StorageRecoveryPage)),
        StorageRecoveryPreviewPage(
          document: document,
          fileName: '旧工作区.json',
          session: s.session,
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(StorageRecoveryPreviewPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        250,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('固定 UTC+08:00').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('已确认备份内容、时间解释和恢复影响'),
        250,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNotNull,
      );
      await tester.tap(find.text('已确认备份内容、时间解释和恢复影响'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保留原件并恢复'),
        250,
        scrollable: scrollable,
      );
      await tester.tap(find.text('保留原件并恢复'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(FilledButton, '恢复工作区'));
      for (
        var i = 0;
        i < 300 && find.byType(AuthPage).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(s.startupError, isNull);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(
        s.data.inspections.first.at,
        resolved.workspace.inspections.first.at,
      );
      expect(s.data.audits.last.detail, contains('固定 UTC+08:00'));
      expect(s.preferences, isEmpty);
      expect(s.timeArchives, isEmpty);
      expect(
        (await s.db.query(
          'recovery_state',
          where: 'key = ?',
          whereArgs: ['timeArchives'],
        )).single['value'],
        invalidArchive,
      );
      expect(
        (await s.db.query(
          'recovery_state',
          where: 'key = ?',
          whereArgs: ['preferences'],
        )).single['value'],
        '{bad preferences',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

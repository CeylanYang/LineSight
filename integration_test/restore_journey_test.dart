import 'package:linesight_flutter/liquid_glass_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/audit.dart';
import 'package:linesight_flutter/screens/restore.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'preview differences, inspect audit and restore then undo through UI',
    (tester) async {
      final path = '${await getDatabasesPath()}/restore-ui-${uid()}.db';
      final s = AppStore();
      await s.init(path: path);
      await s.register('restore.admin', '质量负责人', 'Restore-password-42');
      await s.login('restore.admin', 'Restore-password-42');
      final backup = BackupDocument.parse(s.backup());
      final r = s.pending.first;
      await s.review(r.id, 'pass', '重新核对尺寸与缺陷，符合验收标准');
      await s.archive({r.id}, true);
      await s.simulate('s1');
      final beforeIds = s.data.inspections.map((r) => r.id).toSet();
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        debugPrint('CAPTURE_BEGIN:$name');
        var done = false;
        final shot = binding
            .takeScreenshot(name)
            .whenComplete(() => done = true);
        // Android's image surface needs a fresh frame while acquireLatestImage
        // is waiting, including when the page has no ongoing animation.
        for (var i = 0; i < 100 && !done; i++) {
          binding.scheduleForcedFrame();
          await tester.pump(const Duration(milliseconds: 100));
        }
        await shot.timeout(const Duration(seconds: 15));
        debugPrint('CAPTURE_DONE:$name');
      }

      Future<void> tapText(String text, {bool opensDialog = false}) async {
        final finder = find.text(text);
        await tester.scrollUntilVisible(
          finder,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(finder);
        if (opensDialog) {
          // BusyButton remains busy until the confirmation dialog returns.
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(AlertDialog), findsOneWidget);
        } else {
          await tester.pumpAndSettle();
        }
      }

      Future<void> back() async {
        await tester.tap(find.byType(BackButton).last);
        await tester.pumpAndSettle();
      }

      await tester.tap(
        find.descendant(
          of: find.byType(LiquidGlassBar),
          matching: find.text('我的'),
        ),
      );
      await tester.pumpAndSettle();
      await tapText('数据管理');
      await capture('data-management');
      openPage(
        tester.element(find.byType(DataPage)),
        RestorePreviewPage(
          incoming: backup.workspace,
          fileName: '产线交接备份.json',
          document: backup,
        ),
      );
      await tester.pumpAndSettle();
      await capture('restore-preview');
      // Select the object group, rather than the count row in the summary.
      final recordsGroup = find.widgetWithText(ListTile, '检测记录');
      await tester.scrollUntilVisible(
        recordsGroup,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(recordsGroup);
      await tester.pumpAndSettle();
      expect(find.byType(RestoreChangesPage), findsOneWidget);
      await capture('restore-record-list');
      await tester.tap(find.text(r.serial));
      await tester.pumpAndSettle();
      expect(find.byType(RestoreChangeDetailPage), findsOneWidget);
      await capture('restore-record-detail');
      await back();
      await back();
      await tapText('确认恢复此备份', opensDialog: true);
      await tester.tap(find.widgetWithText(FilledButton, '恢复'));
      await tester.pumpAndSettle();
      expect(s.data.inspections.length, 96);
      expect(s.restorePoint!.records, 97);
      expect(find.byType(DataPage), findsOneWidget);
      await tapText('查看还原点并撤回');
      expect(find.text('还原点预览'), findsOneWidget);
      await capture('restore-point');
      await tapText('确认撤回恢复', opensDialog: true);
      await tester.tap(find.widgetWithText(FilledButton, '撤回恢复'));
      await tester.pumpAndSettle();
      expect(s.restorePoint, isNull);
      expect(s.data.inspections.map((r) => r.id).toSet(), beforeIds);
      openPage(
        tester.element(find.byType(DataPage)),
        AuditPage(target: s.recordTarget(r), legacySerial: r.serial),
      );
      await tester.pumpAndSettle();
      await capture('record-audit');
      await tester.tap(find.text('质量复核'));
      await tester.pumpAndSettle();
      expect(find.byType(AuditDetailPage), findsOneWidget);
      await capture('audit-detail');
      await s.preference('dark', true);
      await tester.pumpAndSettle();
      final darkContext = tester.element(find.text('复核结论'));
      expect(
        DefaultTextStyle.of(darkContext).style.color!.computeLuminance(),
        greaterThan(.5),
      );
      final backContext = tester.element(
        find
            .descendant(
              of: find.byType(BackButton).last,
              matching: find.byType(Icon),
            )
            .last,
      );
      expect(
        IconTheme.of(backContext).color!.computeLuminance(),
        greaterThan(.5),
      );
      await capture('audit-detail-dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await s.db.close();
      s.dispose();
      await deleteDatabase(path);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/csv_export.dart';
import 'package:linesight_flutter/screens/audit.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/screens/statistics.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

AppStore store() => AppStore()
  ..ready = true
  ..data = Workspace.seed()
  ..user = const LocalUser('a', 'admin', '质量负责人', 'admin', true)
  ..preferences = {'haptics': false, 'reduceMotion': true};

void main() {
  testWidgets(
    'CSV audit displays file verification without hiding other changes',
    (tester) async {
      final s = store();
      final event = AuditEntry(
        'csv-export',
        '导出人',
        '导出数据',
        'CSV · 1 条记录 · 文件已保存并回读校验通过',
        DateTime.now(),
        changes: [
          const AuditChange('文件字节数', '', '1234'),
          AuditChange('SHA-256', '', 'a' * 64),
          const AuditChange('附加说明', '原说明', '新说明'),
        ],
      );
      s.data.audits.add(event);
      await tester.pumpWidget(
        AppScope(
          store: s,
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: appTheme(true),
            home: AuditDetailPage(id: event.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('文件校验'), findsOneWidget);
      expect(find.textContaining('1234 B'), findsOneWidget);
      expect(find.text('a' * 64), findsOneWidget);
      expect(find.text('附加说明'), findsOneWidget);
      expect(find.text('原说明'), findsOneWidget);
      expect(find.text('新说明'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('操作人（当时名称）'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('导出人')).dx -
            tester.getTopRight(find.text('操作人（当时名称）')).dx,
        greaterThanOrEqualTo(12),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'CSV preview supports narrow large text, dark tablets and empty selections',
    (tester) async {
      final s = store();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        for (final empty in [false, true]) {
          await tester.pumpWidget(
            AppScope(
              store: s,
              child: MaterialApp(
                key: UniqueKey(),
                theme: appTheme(width == 1100),
                locale: const Locale('zh', 'CN'),
                supportedLocales: const [Locale('zh', 'CN')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!,
                ),
                home: CsvExportPage(
                  snapshot: s.captureCsv(empty ? [] : s.records),
                  session: s.session,
                  scope: '筛选结果',
                  filterSummary: '未归档记录 · 表面缺陷复核工位 · 关键词：划痕 · 时间从新到旧',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (var i = 0; i < 6; i++) {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -600),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$width empty=$empty scroll=$i',
            );
          }
          expect(find.text('保存 CSV'), findsOneWidget);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'all four CSV entry points preserve their exact selection and scope',
    (tester) async {
      final s = store();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> open(Widget page) async {
        await tester.pumpWidget(LineSightApp(key: UniqueKey(), store: s));
        await tester.pumpAndSettle();
        openPage(tester.element(find.byType(AppShell)), page);
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder target) async {
        await tester.scrollUntilVisible(
          target,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(CsvExportPage), findsOneWidget);
      }

      await open(const DataPage());
      await tap(find.text('导出全部 CSV'));
      var page = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
      expect(page.scope, '全部检测记录');
      expect(
        page.snapshot.records.map((r) => r.id),
        s.data.inspections.map((r) => r.id),
      );

      await open(RecordDetailPage(id: s.records.first.id));
      await tester.tap(find.byTooltip('导出此记录'));
      await tester.pumpAndSettle();
      page = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
      expect(page.scope, '单条检测记录');
      expect(page.snapshot.records.single.id, s.records.first.id);

      await open(const StatisticsPage());
      await tester.tap(find.byTooltip('导出当前统计范围的记录'));
      await tester.pumpAndSettle();
      page = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
      expect(page.scope, '当前统计范围');
      final now = DateTime.now();
      final start = localDay(now, -6), end = localDay(now, 1);
      expect(
        page.snapshot.records.map((r) => r.id),
        s.records
            .where((r) => !r.at.isBefore(start) && r.at.isBefore(end))
            .map((r) => r.id),
      );

      await open(const RecordsScreen());
      await tester.tap(find.byTooltip('切换时间排序'));
      await tester.pumpAndSettle();
      await tap(find.byTooltip('导出筛选结果 CSV'));
      page = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
      expect(
        page.snapshot.records.map((r) => r.id),
        s.records.reversed.map((r) => r.id),
      );
      expect(page.filterSummary, contains('时间从旧到新'));
      await open(const RecordsScreen());
      final serial = s.records.first.serial;
      await tester.enterText(find.byType(TextField).first, serial);
      await tester.pumpAndSettle();
      await tap(find.byTooltip('导出筛选结果 CSV'));
      page = tester.widget<CsvExportPage>(find.byType(CsvExportPage));
      expect(page.scope, '筛选结果');
      expect(page.filterSummary, contains(serial));
      expect(page.snapshot.records.single.serial, serial);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
}

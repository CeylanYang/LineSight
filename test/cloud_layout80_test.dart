import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_navigation.dart';
import 'package:linesight_flutter/cloud_workbench.dart';
import 'package:linesight_flutter/cloud_layout.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;
import 'cloud_profile_workflow_test.dart' show printerProfile;
import 'cloud_template_workflow_test.dart' show checklist;

class Layout80Account extends AccessAccount {
  final calls = <String>[];
  Layout80Account({String role = 'owner'}) {
    profile!['display_name'] = '顾承泽';
    activeWorkspace!['name'] = 'checkcheck';
    activeWorkspace!['role'] = role;
    workspaces = [activeWorkspace!];
    templates = [checklist()];
    jobs = [
      for (var i = 0; i < 8; i++)
        {
          'id': 'layout-task-$i',
          'version': 1,
          'part_name': '传动支架 ${i + 1}',
          'status': i == 0 ? 'exception' : 'inspection',
          'quantity': 12,
          'printer': 'Bambu Lab A1',
          'batch_code': 'CC-20261024',
          'created_at': '2026-10-24T06:00:00Z',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'inspections': [],
          'exceptions': [],
          'evidence': [],
        },
    ];
    notifications = [
      for (var i = 0; i < 4; i++)
        {
          'id': 'notice-$i',
          'task_id': 'layout-task-$i',
          'part_name': '传动支架 ${i + 1}',
          'status': i == 0 ? 'exception' : 'inspection',
          'read': false,
        },
    ];
  }
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    calls.add(path);
    if (path.contains('/printer-profiles/')) return [printerProfile];
    if (path.contains('/metrics/')) return <String, dynamic>{};
    if (path.endsWith('/history/')) return <Map<String, dynamic>>[];
    if (path.contains('/jobs/layout-task-')) return jobs.first;
    if (path.contains('/jobs/')) return jobs;
    return <Map<String, dynamic>>[];
  }
}

void main() {
  setUpAll(() async {
    for (final family in ['EvidenceFont', 'sans-serif', 'Roboto']) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> show(
    WidgetTester tester,
    CloudAccount account, {
    double width = 390,
    double scale = 1,
    String language = 'zh',
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = AppStore()
      ..ready = true
      ..preferences = {'haptic': false, 'reduceMotion': true, 'glass': false};
    final tabs = ValueNotifier<int>(0);
    addTearDown(store.dispose);
    addTearDown(account.dispose);
    addTearDown(tabs.dispose);
    await tester.pumpWidget(
      CloudNavigationScope(
        controller: tabs,
        child: MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: appTheme(false).copyWith(
            appBarTheme: appTheme(false).appBarTheme.copyWith(
              titleTextStyle: appTheme(false).appBarTheme.titleTextStyle!
                  .copyWith(fontFamily: 'EvidenceFont'),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: appTheme(false).filledButtonTheme.style!.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: 'EvidenceFont',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            segmentedButtonTheme: SegmentedButtonThemeData(
              style: appTheme(false).segmentedButtonTheme.style!.copyWith(
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(
                    fontFamily: 'EvidenceFont',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            textTheme: appTheme(
              false,
            ).textTheme.apply(fontFamily: 'EvidenceFont'),
          ),
          builder: (context, child) => AppScope(
            store: store,
            child: CloudScope(
              account: account,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
          home: const CloudShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile(
        '../docs/product/linesight/acceptance/${['05-templates-390-zh', '07-my-390-zh', '09-report-390-zh'].contains(name) ? 'cloud82-batch' : 'ui80-batch'}/png/$name.png',
      ),
    );
  }

  Future<void> tab(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(ValueKey('liquid-tab-$index')));
    await tester.pumpAndSettle();
  }

  testWidgets('signed out shows all login methods without another menu', (
    tester,
  ) async {
    final account = CloudAccount()..restoring = false;
    await show(tester, account, width: 360);
    for (final label in ['登录工作区', '登录', '刷卡登录', '进入演示团队']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    expect(find.byType(CloudLoginPage), findsNothing);
    await shot(tester, '01-login-360-zh');
  });

  for (final width in [360.0, 390.0, 412.0]) {
    testWidgets('twelve shortcuts and aligned stocks strip at $width', (
      tester,
    ) async {
      final account = Layout80Account();
      await show(tester, account, width: width);
      for (final label in [
        '在线质检',
        '扫码追溯',
        '新建任务',
        '质量报告',
        '待检任务',
        '异常处理',
        '检测记录',
        '打印配置',
        '检查模板',
        '团队成员',
        '我的卡片',
        '同步与草稿',
        '在线股票',
      ]) {
        expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
      }
      expect(find.byType(CloudTaskTile), findsNothing);
      expect(find.byType(CloudSummaryMetric), findsNWidgets(3));
      expect(find.byType(ExpansionTile), findsNothing);
      final grids = tester
          .widgetList<CloudShortcutGrid>(find.byType(CloudShortcutGrid))
          .toList();
      expect(grids.map((grid) => grid.entries.length), [4, 8]);
      final gridPanel = find
          .ancestor(
            of: find.byType(CloudShortcutGrid).last,
            matching: find.byType(GlassPanel),
          )
          .first;
      final gridRect = tester.getRect(gridPanel);
      final stripRect = tester.getRect(
        find.byKey(const ValueKey('workbench-stocks-strip')),
      );
      expect(stripRect.left, gridRect.left);
      expect(stripRect.width, gridRect.width);
      expect(stripRect.top, gridRect.bottom + 8);
      expect(stripRect.width, greaterThan(stripRect.height * 3));
      await shot(tester, '02-home-${width.toInt()}-zh');
    });
  }
  testWidgets(
    'production and configuration open actual lists; return keeps origin',
    (tester) async {
      final account = Layout80Account();
      await show(tester, account);
      await tab(tester, 1);
      expect(find.byType(CloudTaskTile), findsWidgets);
      expect(account.jobs.length, 8);
      await tester.enterText(find.byType(TextField), 'CC-20261024');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await shot(tester, '03-production-390-zh');
      await tester.tap(find.text('传动支架 1'));
      await tester.pumpAndSettle();
      expect(find.text('处理异常').hitTestable(), findsOneWidget);
      await shot(tester, '04-task-action-390-zh');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'CC-20261024',
      );
      await tab(tester, 0);
      await tester.tap(find.text('检查模板'));
      await tester.pumpAndSettle();
      expect(find.text('Bracket checklist'), findsOneWidget);
      await shot(tester, '05-templates-390-zh');
      await tester.tap(find.text('打印配置').first);
      await tester.pumpAndSettle();
      expect(find.text('Bambu Lab A1'), findsOneWidget);
      await shot(tester, '06-profiles-390-zh');
      await tab(tester, 0);
      await tester.tap(find.text('检查模板'));
      await tester.pumpAndSettle();
      expect(find.text('Bracket checklist'), findsOneWidget);
      await tab(tester, 0);
      await tester.tap(find.text('质量报告'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('导出与报告').hitTestable(), findsOneWidget);
      await shot(tester, '09-report-390-zh');
      await tester.tap(find.byTooltip('导出与报告'));
      await tester.pumpAndSettle();
      expect(find.text('导出 CSV').hitTestable(), findsOneWidget);
      expect(find.text('报告预览').hitTestable(), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tab(tester, 4);
      expect(find.text('我的卡片').hitTestable(), findsOneWidget);
      await shot(tester, '07-my-390-zh');
    },
  );
  for (final language in ['zh', 'en']) {
    testWidgets('large text and viewer layout fit in $language', (
      tester,
    ) async {
      await show(
        tester,
        Layout80Account(role: 'viewer'),
        width: 360,
        scale: 1.4,
        language: language,
      );
      expect(find.text(language == 'zh' ? '新建任务' : 'New task'), findsNothing);
      await shot(tester, '08-home-viewer-large-$language');
    });
  }
}

import 'package:linesight_flutter/liquid_glass_bar.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/dashboard.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/screens/statistics.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('create local account and complete a visible inspection journey',
      (tester) async {
    final directory = await getDatabasesPath();
    final path = '$directory/ui-journey-${uid()}.db';
    final s = AppStore();
    await s.init(path: path);
    await tester.pumpWidget(LineSightApp(store: s));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await File('$directory/evidence-$name.png')
          .writeAsBytes(await binding.takeScreenshot(name));
    }

    await capture('onboarding');
    await tester.enterText(find.byType(TextField).at(0), 'ui.admin');
    await tester.enterText(find.byType(TextField).at(1), '质量负责人');
    await tester.enterText(find.byType(TextField).at(2), 'UI-journey-pass-42');
    await tester.enterText(find.byType(TextField).at(3), 'UI-journey-pass-42');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('创建本地工作区'));
    await tester.tap(find.text('创建本地工作区'));
    for (var i = 0; i < 300 && find.text('保存账户恢复码').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('保存账户恢复码'), findsOneWidget);
    await tester.tap(find.text('我已保存恢复码'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('继续'));
    for (var i = 0; i < 300 && !s.admin; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(s.admin, isTrue);
    expect(find.byType(DashboardPage), findsOneWidget);
    await capture('dashboard');
    await tester.tap(find.text('进入检测台'));
    await tester.pumpAndSettle();
    await capture('station');
    await tester.scrollUntilVisible(find.text('模拟检测'), 250,
        scrollable: find.byType(Scrollable).first);
    final count = s.records.length;
    await tester.tap(find.text('模拟检测'));
    await tester.pumpAndSettle();
    expect(s.records.length, count + 1);
    await tester.tap(find.text('查看最新记录 →'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordDetailPage), findsOneWidget);
    final serial = s.records.first.serial;
    expect(find.text(serial), findsOneWidget);
    await capture('record');
    await tester.scrollUntilVisible(find.byType(TextField), 350,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byType(TextField), '已核对模拟图像并完成复核');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('提交复核'));
    await tester.tap(find.text('提交复核'));
    await tester.pumpAndSettle();
    expect(s.records.first.review, 'reject');
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('质量洞察'));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsPage), findsOneWidget);
    await capture('statistics');
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(LiquidGlassBar), matching: find.text('配方中心')));
    await tester.pumpAndSettle();
    await capture('recipes');
    await tester.tap(find.descendant(
        of: find.byType(LiquidGlassBar), matching: find.text('我的')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('深色模式'), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('深色模式'));
    await tester.pumpAndSettle();
    expect(s.dark, isTrue);
    await capture('settings-dark');
    await tester.scrollUntilVisible(find.text('数据管理'), -300,
        scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('数据管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('数据管理'));
    await tester.pumpAndSettle();
    expect(find.byType(DataPage), findsOneWidget);
    await capture('data-dark');
    s.lock();
    await tester.pumpAndSettle();
    expect(find.byType(DataPage), findsNothing);
    expect(find.text('登录工作台'), findsOneWidget);
    await capture('login-dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await s.db.close();
    s.dispose();
    await deleteDatabase(path);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

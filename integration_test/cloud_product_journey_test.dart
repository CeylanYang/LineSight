import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cloud task inspection issue reinspection and history', (
    tester,
  ) async {
    final store = AppStore()
      ..ready = true
      ..preferences = {'language': 'zh', 'reduceMotion': true, 'glass': true};
    final account = CloudAccount()..restoring = false;
    await tester.runAsync(() => account.signIn(demo: true));
    expect(account.error, isNull);
    expect(account.demoAccount, true);
    expect(account.error, isNull);
    await tester.pumpWidget(LineSightApp(store: store, cloud: account));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    Future<void> ready() async {
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (!account.busy &&
            find
                .byWidgetPredicate(
                  (w) => w is LinearProgressIndicator && w.value == null,
                )
                .evaluate()
                .isEmpty) {
          break;
        }
      }
      expect(account.busy, false);
      expect(
        find.byWidgetPredicate(
          (w) => w is LinearProgressIndicator && w.value == null,
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> hideKeyboard() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 450)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(String text) async {
      await hideKeyboard();
      var finder = find.text(text);
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          220,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
      await tester.tap(finder.first);
      await ready();
    }

    Future<void> capture(String name) async {
      await hideKeyboard();
      await ready();
      await binding.takeScreenshot(name);
    }

    Future<void> checklist() async {
      final template = account.templates.first;
      for (final item in template['items'] as List) {
        final label = find.text('${item['label']}');
        if (label.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            label,
            180,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await tester.ensureVisible(label);
        await tester.pumpAndSettle();
        final panel = find
            .ancestor(of: label, matching: find.byType(GlassPanel))
            .first;
        final chip = find.descendant(
          of: panel,
          matching: find.widgetWithText(ChoiceChip, '合格'),
        );
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
    }

    Future<void> enterNote(String value) async {
      final field = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            ['检验备注', '处理结果'].contains(w.decoration?.labelText),
      );
      if (field.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          field,
          160,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await hideKeyboard();
    }

    await tap('新建任务');
    final fields = find.byType(TextFormField);
    final name = 'DEMO · 手机检验 ${DateTime.now().millisecondsSinceEpoch}';
    await tester.enterText(fields.at(0), name);
    await tester.enterText(fields.at(1), 'A1');
    await tester.enterText(fields.at(2), '10');
    await capture('08-create-cloud-task');
    await tap('创建任务');
    expect(account.jobs.first['part_name'], name);
    await tap(name);
    await capture('09-task-queued-overview');
    await tap('开始打印');
    await tap('确认提交');
    expect(account.jobs.first['status'], 'printing');
    await tap('送检');
    await tap('确认提交');
    expect(account.jobs.first['status'], 'inspection');
    await capture('10-task-awaiting-inspection');
    await tap('登记检验');
    await tap('异常');
    await checklist();
    await enterNote('DEMO · 边缘裂纹，需调整参数后复检');
    await capture('11-inspection-issue-input');
    await tap('确认提交');
    expect(account.jobs.first['status'], 'exception');
    await tap('处理异常');
    await capture('12-task-open-issue');
    await tap('处理异常');
    await enterNote('DEMO · 调整打印参数并重新生产');
    await capture('13-issue-resolution-input');
    await tap('确认提交');
    expect(account.jobs.first['status'], 'inspection');
    await tap('质检');
    await tap('登记检验');
    await checklist();
    await enterNote('DEMO · 复检通过');
    await tap('确认提交');
    expect(account.jobs.first['status'], 'closed');
    expect((account.jobs.first['inspections'] as List).length, 2);
    await capture('14-reinspection-rounds');
    await tap('历史');
    await capture('15-task-event-history');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await ready();
    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CloudTaskListPage(status: 'closed'),
      ),
    );
    await ready();
    await capture('16-cloud-task-list-filter');
    Navigator.of(tester.element(find.byType(CloudTaskListPage))).pop();
    await ready();
    final businessContext = tester.element(find.byType(Scaffold).first);
    Navigator.of(
      businessContext,
    ).push(MaterialPageRoute<void>(builder: (_) => const CloudReportPage()));
    await ready();
    await capture('17-quality-insights');
    Navigator.of(tester.element(find.byType(CloudReportPage))).pop();
    await ready();
    Navigator.of(tester.element(find.byType(Scaffold).first)).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: CloudTemplatesPage()),
      ),
    );
    await ready();
    await capture('18-checklist-templates');
    Navigator.of(tester.element(find.byType(CloudTemplatesPage))).pop();
    await ready();
    Navigator.of(tester.element(find.byType(Scaffold).first)).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CloudInspectionDetailPage(record: account.records.first),
      ),
    );
    await ready();
    await capture('19-inspection-snapshot');
    Navigator.of(tester.element(find.byType(CloudInspectionDetailPage))).pop();
    await ready();
    await tester.runAsync(account.signOut);
    expect(account.signedIn, false);
    await tester.pumpWidget(const SizedBox.shrink());
    account.dispose();
    store.dispose();
  });
}

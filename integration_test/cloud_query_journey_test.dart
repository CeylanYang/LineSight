import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'shared cloud filter scope, category drilldown and evidence report preview',
    (tester) async {
      final store = AppStore()
        ..ready = true
        ..preferences = {'language': 'zh', 'reduceMotion': true, 'glass': true};
      final account = CloudAccount()..restoring = false;
      await tester.runAsync(() => account.signIn(demo: true));
      expect(account.error, isNull);
      final job = account.jobs.firstWhere(
        (job) => job['part_name'] == 'DEMO · 证据与数量批次验收',
      );
      final filters = {
        'q': '${job['id']}',
        'status': 'closed',
        'category': 'crack',
      };
      await tester.pumpWidget(LineSightApp(store: store, cloud: account));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 160; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)),
          );
          await tester.pump(const Duration(milliseconds: 150));
          if (done()) {
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            return;
          }
        }
        fail('Cloud operation did not complete');
      }

      Future<void> push(Widget page) async {
        Navigator.of(
          tester.element(find.byType(Scaffold).first),
        ).push(MaterialPageRoute<void>(builder: (_) => page));
        await tester.pumpAndSettle();
      }

      Future<void> tap(String title) async {
        final target = find.text(title).first;
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            180,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pump();
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await binding.takeScreenshot(name);
      }

      await push(CloudTaskListPage(filters: filters));
      await until(() => find.text('${job['part_name']}').evaluate().isNotEmpty);
      await capture('32-scoped-task-list');
      await tap('筛选范围');
      await until(() => find.byType(AlertDialog).evaluate().isNotEmpty);
      await capture('33-shared-filter-dialog');
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tap('范围报告');
      await until(() => find.text('80.0%').evaluate().isNotEmpty);
      await capture('34-scoped-metrics');
      await tester.scrollUntilVisible(
        find.text('平均异常处理时长'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await capture('35-category-drilldown');
      await tap('报告预览');
      await until(
        () => find.byType(CloudReportSnapshotPage).evaluate().isNotEmpty,
      );
      expect(find.textContaining('LS-'), findsOneWidget);
      await capture('36-report-provenance');
      await tester.scrollUntilVisible(
        find.byType(Image).first,
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await capture('37-report-evidence-thumbnails');
      await tester.runAsync(account.signOut);
      await tester.pumpWidget(const SizedBox.shrink());
      account.dispose();
      store.dispose();
    },
  );
}

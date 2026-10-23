import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_trace.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native QR decode, guarded task route and inspection date drilldown',
    (tester) async {
      final store = AppStore()
        ..ready = true
        ..preferences = {'language': 'zh', 'reduceMotion': true, 'glass': true};
      final account = CloudAccount()..restoring = false;
      await tester.runAsync(() => account.signIn(demo: true));
      expect(account.error, isNull);
      final job = account.jobs.firstWhere(
        (row) => row['part_name'] == 'DEMO · 证据与数量批次验收',
      );
      final trace = TaskTrace(
        account.activeWorkspace!['id'] as int,
        '${job['id']}',
      );
      final checks = (job['inspections'] as List).cast<Map>();
      checks.sort(
        (a, b) => (a['round_no'] as int).compareTo(b['round_no'] as int),
      );
      final day = DateTime.parse(
        '${checks.first['created_at']}',
      ).toUtc().toIso8601String().substring(0, 10);
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

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await binding.takeScreenshot(name);
      }

      Future<void> tap(String text) async {
        final finder = find.text(text);
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            200,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(finder.first);
        await tester.pumpAndSettle();
        await tester.tap(finder.first);
        await tester.pump();
      }

      await push(
        CloudTraceCodePage(trace: trace, partName: '${job['part_name']}'),
      );
      await capture('42-task-qr-code');
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('task-qr-image')),
      );
      final decoded = await tester.runAsync(() async {
        final raster = await boundary.toImage(pixelRatio: 2);
        final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
        raster.dispose();
        final folder = await Directory.systemTemp.createTemp('linesight-qr-');
        final controller = MobileScannerController(autoStart: false);
        try {
          final file = await File(
            '${folder.path}/task.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          return await controller.analyzeImage(
            file.path,
            formats: [BarcodeFormat.qrCode],
          );
        } finally {
          await controller.dispose();
          await folder.delete(recursive: true);
        }
      });
      expect(decoded, isNotNull);
      expect(
        decoded!.barcodes.any((barcode) => barcode.rawValue == trace.link),
        true,
      );
      await push(const CloudScanPage());
      await until(() => find.byType(MobileScanner).evaluate().isNotEmpty);
      await capture('43-qr-scanner-entry');
      tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
        decoded,
      );
      await until(() => find.byType(CloudTaskPage).evaluate().isNotEmpty);
      await capture('44-decoded-authorized-task');
      await tester.runAsync(account.signOut);
      await tester.pumpAndSettle();
      await tester.binding.handlePushRoute(trace.link);
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskPage), findsNothing);
      await capture('45-trace-secondary-login');
      await tester.runAsync(() => account.signIn(demo: true));
      await until(() => find.byType(CloudTaskPage).evaluate().isNotEmpty);
      await tester.binding.handlePushRoute(
        'linesight://task/999999/${trace.jobId}',
      );
      await until(() => find.text('当前账户无法访问该任务').evaluate().isNotEmpty);
      expect(find.byType(CloudTaskPage), findsNothing);
      await capture('46-trace-membership-denied');
      final nextDay = DateTime.parse(
        '${day}T00:00:00Z',
      ).add(const Duration(days: 1));
      await push(
        CloudReportPage(
          filters: {
            'q': trace.jobId,
            'inspected_from': '${day}T00:00:00Z',
            'inspected_to': nextDay.toIso8601String(),
          },
        ),
      );
      await until(() => find.text('80.0%').evaluate().isNotEmpty);
      await capture('47-inspection-date-report-scope');
      await tap(day);
      await until(() => find.text('${job['part_name']}').evaluate().isNotEmpty);
      expect(
        tester
            .widget<CloudTaskListPage>(find.byType(CloudTaskListPage))
            .filters['first_day'],
        day,
      );
      await capture('48-first-inspection-day-drilldown');
      await tester.runAsync(account.signOut);
      await tester.pumpWidget(const SizedBox.shrink());
      account.dispose();
      store.dispose();
    },
  );
}

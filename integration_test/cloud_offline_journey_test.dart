import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_outbox.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class OfflineJourneyAccount extends CloudAccount {
  bool offlineUpload = true;
  List<int>? lastPhotoBytes;
  @override
  Future<Map<String, dynamic>> uploadPhoto(
    String path,
    List<int> bytes,
    String key,
    Map<String, String> fields,
  ) {
    lastPhotoBytes = bytes;
    if (offlineUpload) throw const CollaborationApiException(503, '网络连接失败，请重试');
    return super.uploadPhoto(path, bytes, key, fields);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'encrypted offline photo and inspection recovery with real cloud acknowledgment',
    (tester) async {
      final store = AppStore()
        ..ready = true
        ..preferences = {'language': 'zh', 'reduceMotion': true, 'glass': true};
      final account = OfflineJourneyAccount()..restoring = false;
      await tester.runAsync(() => account.signIn(demo: true));
      expect(account.error, isNull);
      expect(account.demoAccount, true);
      final base = 'workspaces/${account.activeWorkspace!['id']}/';
      final name = 'DEMO · 离线检验 ${DateTime.now().millisecondsSinceEpoch}';
      var sequence = 0;
      Future<dynamic> call(
        String method,
        String path,
        Map<String, dynamic> body,
      ) => account.request(
        method,
        path,
        body: body,
        idempotencyKey:
            'offline-journey-${DateTime.now().microsecondsSinceEpoch}-${sequence++}',
      );
      late Map<String, dynamic> job;
      await tester.runAsync(() async {
        job = Map<String, dynamic>.from(
          await call('POST', '${base}jobs/', {
                'part_name': name,
                'printer': 'A1',
                'quantity': 10,
                'batch_code': 'DEMO-OFFLINE',
                'template_id': account.templates.first['id'],
              })
              as Map,
        );
        for (final status in ['printing', 'inspection']) {
          job = Map<String, dynamic>.from(
            await call('PATCH', '${base}jobs/${job['id']}/', {
                  'version': job['version'],
                  'status': status,
                })
                as Map,
          );
        }
        await account.reload();
      });
      await tester.pumpWidget(LineSightApp(store: store, cloud: account));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      Future<void> ready() async {
        for (var i = 0; i < 500; i++) {
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

      Future<void> tap(String label) async {
        await hideKeyboard();
        final finder = find.text(label);
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
        await ready();
      }

      Future<void> capture(String name) async {
        await hideKeyboard();
        await ready();
        await binding.takeScreenshot(name);
      }

      Future<void> push(Widget page) async {
        Navigator.of(
          tester.element(find.byType(Scaffold).first),
        ).push(MaterialPageRoute<void>(builder: (_) => page));
        await ready();
      }

      Future<void> back() async {
        Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
        await ready();
      }

      final workspace = account.activeWorkspace!['id'] as int;
      await push(
        CloudTaskCommandPage(
          job: job,
          workspaceId: workspace,
          action: 'inspect',
        ),
      );
      for (final item in account.templates.first['items'] as List) {
        final label = find.text('${item['label']}');
        if (label.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            label,
            180,
            scrollable: find.byType(Scrollable).first,
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
      final note = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '检验备注',
      );
      if (note.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          note,
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(note);
      await tester.enterText(note, 'DEMO · 断网保存，恢复后提交');
      await hideKeyboard();
      final queue = CloudOutbox(account);
      late Map<String, dynamic> attachment;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xfff5f7fb), BlendMode.src);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(100, 100, 700, 450),
            const Radius.circular(45),
          ),
          Paint()..color = const Color(0xffc9d9e8),
        );
        final paint = Paint()
          ..color = const Color(0xffcc4352)
          ..strokeWidth = 10;
        canvas.drawLine(const Offset(400, 130), const Offset(470, 300), paint);
        canvas.drawLine(const Offset(470, 300), const Offset(430, 490), paint);
        final image = await recorder.endRecording().toImage(900, 650);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        attachment = await queue.enqueue(
          '${job['id']}',
          data!.buffer.asUint8List(),
        );
        try {
          await queue.retry('${attachment['key']}');
          fail('offline upload must fail');
        } on CollaborationApiException catch (failure) {
          expect(failure.status, 503);
        }
      });
      await back();
      await push(
        CloudTaskCommandPage(
          job: job,
          workspaceId: workspace,
          action: 'inspect',
        ),
      );
      if (note.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          note,
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(note);
      await ready();
      expect(find.text('DEMO · 断网保存，恢复后提交'), findsOneWidget);
      await capture('23-restored-inspection-draft');
      await tester.scrollUntilVisible(
        find.text('同步与草稿'),
        -220,
        scrollable: find.byType(Scrollable).first,
      );
      await tap('同步与草稿');
      for (
        var i = 0;
        i < 50 && find.textContaining('等待上传').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await capture('24-encrypted-photo-pending');
      account.offlineUpload = false;
      final queuedLabel = find.text('${job['id']}');
      if (queuedLabel.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          queuedLabel,
          180,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(queuedLabel);
      await tester.pumpAndSettle();
      final queuedPanel = find
          .ancestor(of: queuedLabel, matching: find.byType(GlassPanel))
          .first;
      final retryButton = find.descendant(
        of: queuedPanel,
        matching: find.widgetWithText(TextButton, '重试上传'),
      );
      await tester.ensureVisible(retryButton);
      await tester.pumpAndSettle();
      await tester.tap(retryButton);
      await tester.pump();
      for (var attempt = 0; attempt < 120; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump(const Duration(milliseconds: 250));
        final uploaded = find.descendant(
          of: queuedPanel,
          matching: find.textContaining('已上传'),
        );
        if (uploaded.evaluate().isNotEmpty) break;
      }
      await ready();
      expect(
        (await tester.runAsync(
          queue.list,
        ))!.where((p) => p['job_id'] == job['id']).single['state'],
        'uploaded',
      );
      await capture('25-photo-retry-acknowledged');
      await back();
      await tap('确认提交');
      final completed = account.jobs.firstWhere((j) => j['id'] == job['id']);
      expect(completed['status'], 'closed');
      expect(
        (await tester.runAsync(
          queue.list,
        ))!.where((p) => p['job_id'] == job['id']),
        isEmpty,
      );
      final photo = Map<String, dynamic>.from(
        (completed['evidence'] as List).single as Map,
      );
      await push(CloudEvidencePage(jobId: '${job['id']}', photo: photo));
      await capture('26-real-photo-evidence');
      await tap('边缘参考');
      await capture('27-edge-reference');
      await back();
      late Map<String, dynamic> notice;
      await tester.runAsync(() async {
        notice = Map<String, dynamic>.from(
          await call('POST', '${base}jobs/', {
                'part_name': 'DEMO · 通知已读验证',
                'printer': 'A1',
                'quantity': 1,
              })
              as Map,
        );
        for (final status in ['printing', 'inspection']) {
          notice = Map<String, dynamic>.from(
            await call('PATCH', '${base}jobs/${notice['id']}/', {
                  'version': notice['version'],
                  'status': status,
                })
                as Map,
          );
        }
        await account.reload();
      });
      await push(const CloudNotificationsPage());
      await tap('标为已读');
      for (var attempt = 0; attempt < 120; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)),
        );
        await tester.pump(const Duration(milliseconds: 250));
        if (account.notifications.any(
          (row) => row['task_id'] == notice['id'] && row['read'] == true,
        )) {
          break;
        }
      }
      expect(
        account.notifications.firstWhere(
          (row) => row['task_id'] == notice['id'],
        )['read'],
        true,
      );
      await capture('28-versioned-notification-read');
      // Leave a real encrypted pending attachment and draft for the normal-main
      // upgrade/process-death verification, without committing an inspection.
      await tester.runAsync(() async {
        await queue.enqueue('${notice['id']}', account.lastPhotoBytes!);
        await account.saveDraft(account.draftKey('inspect-${notice['id']}')!, {
          'request_key':
              'cold-restore-${DateTime.now().microsecondsSinceEpoch}',
          'job_id': notice['id'],
          'part_name': notice['part_name'],
          'action': 'inspect',
          'version': notice['version'],
          'note': 'DEMO · 杀进程恢复草稿',
          'verdict': 'pass',
          'passed': '1',
          'failed': '0',
          'scrapped': '0',
          'answers': <String, String>{},
          'answer_notes': <String, String>{},
          'serial_results': <String, String>{},
          'evidence': <int>[],
          'template': account.templates.first,
        });
      });
      await tester.runAsync(account.signOut);
      await tester.pumpWidget(const SizedBox.shrink());
      account.dispose();
      store.dispose();
    },
  );
}

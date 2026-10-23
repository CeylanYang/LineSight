import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_local_import.dart';
import 'package:linesight_flutter/cloud_outbox.dart';
import 'package:linesight_flutter/cloud_photo_recovery.dart';
import 'package:linesight_flutter/cloud_sync_diagnostics.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class RecoveredPicker extends ImagePicker {
  final XFile file;
  RecoveredPicker(this.file);
  @override
  Future<LostDataResponse> retrieveLostData() async =>
      LostDataResponse(files: [file]);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'authorized local import, deduplication, recovered photo upload and diagnostics',
    (tester) async {
      final folder = await Directory.systemTemp.createTemp(
        'linesight-sync-journey-',
      );
      final store = AppStore(), account = CloudAccount()..restoring = false;
      await tester.runAsync(() async {
        await store.init(path: '${folder.path}/source.sqlite');
        await store.register(
          'import.engineer',
          'Import engineer',
          'import-verify-2026',
          examples: false,
        );
      });
      store.preferences = {
        'language': 'zh',
        'reduceMotion': true,
        'glass': true,
      };
      final sourceId = 'DEMO-LOCAL-${DateTime.now().microsecondsSinceEpoch}';
      store.data.inspections.addAll([
        Inspection(
          id: sourceId,
          stationId: store.data.stations.first.id,
          recipeName: 'DEMO · 本机历史导入',
          serial: 'LOCAL-01',
          at: DateTime.now(),
          passed: true,
          defect: '',
          confidence: .95,
          operatorName: 'Import engineer',
          sample: false,
        ),
        Inspection(
          id: '$sourceId-sample',
          stationId: store.data.stations.first.id,
          recipeName: 'DEMO · 默认排除示例',
          serial: 'SAMPLE-01',
          at: DateTime.now(),
          passed: true,
          defect: '',
          confidence: .95,
          operatorName: 'Import engineer',
          sample: true,
        ),
      ]);
      await tester.runAsync(() => account.signIn(demo: true));
      expect(account.error, isNull);
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

      Future<void> tap(String label) async {
        final finder = find.text(label);
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            180,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(finder.last);
        await tester.pumpAndSettle();
        await tester.tap(finder.last);
        await tester.pump();
      }

      await push(const CloudLocalImportPage());
      expect(find.text('DEMO · 本机历史导入'), findsNothing);
      await capture('52-local-import-authorization');
      await tester.enterText(find.byType(TextField).at(0), 'import.engineer');
      await tester.enterText(
        find.byType(TextField).at(1),
        'import-verify-2026',
      );
      await tap('授权并预览');
      await until(() => find.text('记录数：1').evaluate().isNotEmpty);
      expect(find.textContaining('默认排除示例'), findsNothing);
      await capture('53-local-import-preview-excludes-samples');
      await tap('确认导入');
      await tap('确认');
      await until(() => find.text('已导入 1 条，跳过 0 条').evaluate().isNotEmpty);
      await capture('54-cloud-import-receipt');
      await tap('再次导入');
      await tap('确认');
      await until(() => find.text('已导入 0 条，跳过 1 条').evaluate().isNotEmpty);
      await capture('55-repeat-import-deduplicated');
      final imported = Map<String, dynamic>.from(
        await tester.runAsync(
              () => account.request(
                'GET',
                'workspaces/${account.activeWorkspace!['id']}/legacy-inspections/',
              ),
            )
            as Map,
      );
      expect(
        (imported['records'] as List).any((row) => row['id'] == sourceId),
        true,
      );
      expect(
        (imported['records'] as List).any(
          (row) => row['id'] == '$sourceId-sample',
        ),
        false,
      );

      var job = Map<String, dynamic>.from(
        await tester.runAsync(
              () => account.request(
                'POST',
                'workspaces/${account.activeWorkspace!['id']}/jobs/',
                body: {
                  'part_name': 'DEMO · 照片恢复批次验收',
                  'printer': 'A1',
                  'quantity': 1,
                  'profile_id': 'starter:a1',
                  'batch_code': 'DEMO-SYNC-20261023',
                },
                idempotencyKey: 'sync-${DateTime.now().microsecondsSinceEpoch}',
              ),
            )
            as Map,
      );
      for (final status in ['printing', 'inspection']) {
        job = Map<String, dynamic>.from(
          await tester.runAsync(
                () => account.request(
                  'PATCH',
                  'workspaces/${account.activeWorkspace!['id']}/jobs/${job['id']}/',
                  body: {'version': job['version'], 'status': status},
                  idempotencyKey:
                      'sync-$status-${DateTime.now().microsecondsSinceEpoch}',
                ),
              )
              as Map,
        );
      }
      final bytes = await rootBundle.load('assets/parts/part-mount-wide.webp');
      final file = await tester.runAsync(
        () => File(
          '${folder.path}/recovered.webp',
        ).writeAsBytes(bytes.buffer.asUint8List()),
      );
      final recovery = CloudPhotoRecovery(
        picker: RecoveredPicker(XFile(file!.path)),
      );
      await tester.runAsync(
        () => account.saveDraft(CloudPhotoRecovery.contextKey, {
          'scope': account.draftKey('outbox'),
          'job_id': job['id'],
          'stage': 'inspection',
        }),
      );
      expect(await tester.runAsync(() => recovery.recover(account)), 1);
      await push(const CloudSyncPage());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();
      final jobLabel = find.text('任务 ${job['id']}');
      await tester.scrollUntilVisible(
        jobLabel,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await capture('56-recovered-photo-encrypted-outbox');
      final progress = <double>[];
      void observe() {
        progress.addAll(account.uploadProgress.values);
      }

      account.addListener(observe);
      final photoCard = find
          .ancestor(of: jobLabel, matching: find.byType(GlassPanel))
          .first;
      final retry = find.descendant(of: photoCard, matching: find.text('重试上传'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      if (account.uploadProgress.isNotEmpty) {
        await binding.takeScreenshot('57a-actual-upload-progress');
      }
      await until(
        () => find
            .descendant(of: photoCard, matching: find.text('已上传，待关联检验'))
            .evaluate()
            .isNotEmpty,
      );
      account.removeListener(observe);
      expect(progress.any((value) => value > 0), true);
      final queue = await tester.runAsync(() => CloudOutbox(account).list());
      expect(
        queue!.singleWhere((row) => row['job_id'] == job['id'])['state'],
        'uploaded',
      );
      await capture('57-recovered-photo-cloud-receipt');
      await push(const CloudDiagnosticsPage());
      await until(() => find.text('连接正常').evaluate().isNotEmpty);
      await capture('58-sync-diagnostics-connected');
      await tap('复制诊断信息');
      final copied = await tester.runAsync(
        () => Clipboard.getData('text/plain'),
      );
      final diagnostics = jsonDecode(copied!.text!) as Map;
      expect(diagnostics.keys.toSet(), {
        'app_version',
        'platform',
        'checked_at',
        'workspace_id',
        'pending_photos',
        'acknowledged_photos',
        'drafts',
        'status',
      });
      expect(copied.text, isNot(contains(sourceId)));
      expect(copied.text, isNot(contains('Bearer')));
      expect(copied.text, isNot(contains('refresh_token')));
      await capture('59-redacted-support-diagnostics');
      binding.reportData ??= {};
      binding.reportData!.addAll({
        'workspace_id': account.activeWorkspace!['id'],
        'job_id': job['id'],
        'source_record_id': sourceId,
        'samples_excluded': true,
        'repeat_import_skipped': 1,
        'recovered_photo_acknowledged': true,
        'actual_transport_progress_samples': progress.length,
        'diagnostics_connected': true,
        'diagnostics_redacted_fields_verified': true,
      });
      await tester.runAsync(account.signOut);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await store.db.close();
        await folder.delete(recursive: true);
      });
      account.dispose();
      store.dispose();
    },
  );
}

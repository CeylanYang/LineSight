import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/audit.dart';
import 'package:linesight_flutter/screens/restore.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/screens/backup_transfer.dart';
import 'package:linesight_flutter/stream_backup.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

void main() {
  testWidgets(
    'restore and audit detail pages handle narrow large text and tablets',
    (tester) async {
      final s = AppStore()
        ..ready = true
        ..data = Workspace.seed()
        ..user = const LocalUser('a', 'admin', '管理员', 'admin', true);
      final incoming = Workspace.fromJson(s.data.toJson());
      incoming.inspections.first.note = '已重新核对完整检测结果与参数快照';
      incoming.inspections.removeLast();
      s.data.audits.add(
        AuditEntry(
          'audit',
          '管理员',
          '质量复核',
          '依据完整检测结果复核',
          DateTime.now(),
          targets: [s.recordTarget(s.data.inspections.first)],
          changes: [const AuditChange('复核结论', '未复核', '放行')],
        ),
      );
      final diff = RestoreComparison(s.data, incoming);
      final oldSource = jsonEncode(s.data.toJson()).replaceAll('Z"', '"');
      s.timeArchives = [
        TimeMigrationArchive(
          id: 'old-time',
          capturedAt: instantJson(DateTime.now()),
          zoneName: 'CST',
          offsetMinutes: 480,
          count: 100,
          originals: {'workspace': oldSource},
        ),
      ];
      final oldDocument = BackupDocument.parse(
        s.timeArchives.single.backupSource('workspace'),
      );
      final chosenDocument = oldDocument.resolveLegacyTimes(
        const LegacyTimeChoice.fixed(480),
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        for (final page in <Widget>[
          RestorePreviewPage(incoming: incoming, fileName: '测试备份.json'),
          RestorePreviewPage(
            incoming: oldDocument.workspace,
            document: oldDocument,
            fileName: '旧版备份.json',
          ),
          RestorePreviewPage(
            incoming: chosenDocument.workspace,
            document: chosenDocument,
            fileName: '已解释备份.json',
          ),
          const TimeStoragePage(),
          const BackupExportPage(),
          const DetailScaffold(
            title: '准备备份',
            children: [
              TransferProgress(
                progress: BackupProgress('正在准备完整备份…', .4, 23000000),
              ),
            ],
          ),
          RestoreChangesPage(changes: diff.changes, type: '检测记录'),
          RestoreChangeDetailPage(change: diff.changes.first),
          const AuditDetailPage(id: 'audit'),
        ]) {
          await tester.pumpWidget(
            AppScope(
              store: s,
              child: MaterialApp(
                key: UniqueKey(),
                theme: appTheme(width == 320),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('zh', 'CN')],
                locale: const Locale('zh', 'CN'),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!,
                ),
                home: page,
              ),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${page.runtimeType} at $width',
          );
          for (var i = 0; i < 4; i++) {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -600),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.runtimeType} scroll $i at $width',
            );
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
}

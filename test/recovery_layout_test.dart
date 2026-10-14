import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/recovery_storage.dart';
import 'package:linesight_flutter/screens/storage_recovery.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class _RecoveryLayoutStore extends AppStore {
  final RecoverySnapshot snapshot;
  _RecoveryLayoutStore(this.snapshot);
  @override
  LocalUser get recoveryUser =>
      const LocalUser('a', 'admin', '恢复管理员', 'admin', true);
  @override
  Future<List<RecoverySnapshot>> recoveryHistory() async => [snapshot];
}

void main() {
  testWidgets(
    'unavailable administrator shows help without verification fields',
    (tester) async {
      final s = AppStore()
        ..startupError = '无法读取本机数据库。'
        ..canRecoverStorage = false;
      await tester.pumpWidget(
        AppScope(
          store: s,
          child: MaterialApp(
            theme: appTheme(false),
            home: const StorageFailurePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂时无法验证管理员'), findsOneWidget);
      expect(find.textContaining('另一台设备建立工作区后导入'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('重试读取'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'storage recovery routes support narrow enlarged text and dark tablet layouts',
    (tester) async {
      final snapshot = RecoverySnapshot(
        id: 'restoration-example-12345',
        actor: '恢复管理员',
        sourceName: '生产线质量交接完整备份-2026-10-14.lsb',
        format: 'LSB 2',
        createdAt: DateTime.utc(2026, 10, 14),
        records: 96,
        bytes: 3500000,
      );
      final s = _RecoveryLayoutStore(snapshot)
        ..ready = true
        ..startupError = '本机工作区未通过校验，原始数据已保留。'
        ..canRecoverStorage = true;
      final doc = BackupDocument.parse(BackupDocument.encode(Workspace.seed()));
      final legacy = BackupDocument.parse(
        BackupDocument.encode(Workspace.seed()).replaceAll('Z"', '"'),
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final width in [320.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        for (final page in <Widget>[
          const StorageFailurePage(),
          const StorageRecoveryPage(),
          StorageRecoveryPreviewPage(
            document: doc,
            fileName: snapshot.sourceName,
            session: 0,
          ),
          StorageRecoveryPreviewPage(
            document: legacy,
            fileName: '旧备份.json',
            session: 0,
          ),
          const RecoveryHistoryPage(),
          RecoveryOriginalPage(snapshot: snapshot),
        ]) {
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
                home: page,
              ),
            ),
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

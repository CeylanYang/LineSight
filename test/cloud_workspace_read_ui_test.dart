import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_feedback.dart';
import 'package:linesight_flutter/cloud_workbench.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

class NewTeamAccount extends AccessAccount {
  NewTeamAccount() {
    activeWorkspace = null;
    workspaces = [];
  }
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'POST' && path == 'workspaces/create/') {
      writes++;
      return {'id': 9};
    }
    return <Map<String, dynamic>>[];
  }

  @override
  Future<void> reload() async {
    workspaces = [
      {'id': 9, 'role': 'owner', 'name': 'New team'},
    ];
  }

  @override
  Future<void> selectWorkspace(Map<String, dynamic> workspace) async {
    activeWorkspace = workspace;
    notifyListeners();
  }
}

void main() {
  testWidgets('first team can be created when signed in without a workspace', (
    tester,
  ) async {
    final account = NewTeamAccount();
    final store = AppStore()
      ..ready = true
      ..preferences = {'language': 'zh', 'haptic': false};
    addTearDown(account.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: const CloudTeamPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建团队'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New team');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(account.writes, 1);
    expect(account.activeWorkspace?['id'], 9);
    expect(tester.takeException(), isNull);
  });
  testWidgets('profile never labels unread data as zero notifications', (
    tester,
  ) async {
    final account = AccessAccount()
      ..workspaceDataLoaded = false
      ..workspaceFailure = const CollaborationApiException(
        0,
        '无法连接服务，请检查地址和网络后重试',
      );
    final store = AppStore()
      ..ready = true
      ..preferences = {'language': 'zh', 'haptic': false, 'glass': false};
    addTearDown(account.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: const CloudShell(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法连接服务，请检查地址和网络后重试'), findsNothing);
    expect(find.text('检查网络连接后重试，当前筛选条件会保留。'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.person_outline_rounded).last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('待办与通知').first,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('0 条提醒'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final locale in ['zh', 'en']) {
    for (final state in ['loading', 'failure', 'empty', 'no-team']) {
      testWidgets(
        '$locale workspace $state distinguishes unavailable from empty',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final font = FontLoader('EvidenceFont')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
                ),
              ),
            );
          await font.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
          final account = AccessAccount();
          final store = AppStore()
            ..ready = true
            ..preferences = {
              'language': locale,
              'reduceMotion': true,
              'haptic': false,
            };
          addTearDown(account.dispose);
          addTearDown(store.dispose);
          account.workspaceDataLoaded = state == 'empty' || state == 'no-team';
          account.workspaceLoading = state == 'loading';
          account.workspaceFailure = state == 'failure'
              ? const CollaborationApiException(
                  503,
                  'internal transport details',
                )
              : null;
          if (state == 'no-team') account.activeWorkspace = null;
          Future<void> show(Widget child) async {
            await tester.pumpWidget(
              MaterialApp(
                locale: Locale(locale),
                supportedLocales: const [Locale('zh'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: ThemeData(fontFamily: 'EvidenceFont'),
                builder: (context, child) => AppScope(
                  store: store,
                  child: CloudScope(account: account, child: child!),
                ),
                home: Scaffold(
                  body: child is CloudWorkbenchSummary
                      ? SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: child,
                          ),
                        )
                      : child,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }

          await show(CloudWorkbenchSummary(account: account));
          expect(
            find.byType(CloudSummaryMetric),
            state == 'empty' ? findsNWidgets(3) : findsNothing,
          );
          expect(find.text('internal transport details'), findsNothing);
          if (state == 'loading') {
            expect(find.byType(CloudLoadingPanel), findsOneWidget);
          }
          if (state == 'failure') {
            expect(find.byType(CloudFailurePanel), findsOneWidget);
          }
          await expectLater(
            find.byType(Scaffold).first,
            matchesGoldenFile(
              '../docs/product/linesight/acceptance/ui80-batch/read-state-batch/png/128-workspace-$state-$locale-desktop-render.png',
            ),
          );
          await show(const CloudTemplatesPage());
          expect(
            find.text(locale == 'zh' ? '暂无检查模板' : 'No checklists'),
            state == 'empty' ? findsOneWidget : findsNothing,
          );
          await show(const CloudNotificationsPage());
          expect(
            find.text(locale == 'zh' ? '已清空' : 'Cleared'),
            state == 'empty' ? findsOneWidget : findsNothing,
          );
        },
      );
    }
  }
}

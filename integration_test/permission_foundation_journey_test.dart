import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/team_workspace.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';

/// Requires the isolated local Django API, never a production workspace.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('DEMO local import gate and real member revocation', (
    tester,
  ) async {
    const server = String.fromEnvironment(
      'PRODUCT_TEST_API',
      defaultValue: 'http://10.0.2.2:19843/api/v1/',
    );
    final nonce = DateTime.now().millisecondsSinceEpoch;
    final password = 'Demo-${uid()}';
    final ownerName = 'manager.$nonce';
    final workerName = 'worker.$nonce';
    final public = CollaborationApi(server);
    await public.register(ownerName, password);
    await public.register(workerName, password);
    final owner = CollaborationApi(
      server,
      token: await public.login(ownerName, password),
    );
    final worker = CollaborationApi(
      server,
      token: await public.login(workerName, password),
    );
    final workspace = await owner.createWorkspace('DEMO · 权限验收');
    final workspaceId = workspace['id'] as int;
    await worker.redeem(await owner.invite(workspaceId, 'operator'));
    await owner.createJob(workspaceId, {
      'part_name': 'DEMO · 支架批次',
      'printer': 'A1',
      'quantity': 10,
    }, 'permission-demo-$nonce');
    final store = AppStore();
    final dbPath = '${await getDatabasesPath()}/permissions-${uid()}.db';
    await store.init(path: dbPath);
    await store.register(
      'local.manager',
      'DEMO 本机管理员',
      password,
      examples: true,
    );
    CollaborationSession.token = owner.token;
    CollaborationSession.serviceUrl = server;

    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Widget page() => AppScope(
      store: store,
      child: MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: appTheme(false),
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const TeamWorkspacePage(),
      ),
    );
    try {
      await tester.pumpWidget(page());
      await waitFor(find.text('DEMO · 权限验收'));
      await tap(find.text('DEMO · 权限验收'));
      final importButton = find.textContaining('导入本机质检记录 ·');
      await waitFor(importButton);
      await binding.convertFlutterSurfaceToImage();
      await tap(importButton);
      final denied = find.text('请先登录本机工程师或管理员账户，再导入。');
      await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(denied, findsOneWidget);
      expect(find.textContaining('记录数：'), findsNothing);
      await tester.ensureVisible(denied);
      await capture('SEC-01-cloud-login-local-access-denied');

      await store.login('local.manager', password);
      await tap(importButton);
      expect(find.text('包含示例记录'), findsOneWidget);
      expect(find.text('记录数：0'), findsOneWidget);
      await capture('SEC-01-authorized-preview-samples-excluded');
      await tap(find.text('包含示例记录'));
      expect(find.text('记录数：96'), findsOneWidget);
      store.lock();
      await tester.pumpAndSettle();
      expect(find.text('本机授权已失效'), findsOneWidget);
      expect(find.text('记录数：96'), findsNothing);
      await capture('SEC-01-preview-revoked-on-local-lock');
      await tap(find.text('取消'));

      Future<void> memberAction(String action) async {
        final row = find.ancestor(
          of: find.text(workerName),
          matching: find.byType(ListTile),
        );
        final menu = find.descendant(
          of: row,
          matching: find.byType(PopupMenuButton<String>),
        );
        await tap(menu);
        await tap(find.text(action).last);
      }

      await memberAction('只读成员');
      await capture('COL-01-member-role-confirmation');
      await tap(find.text('确认'));
      for (
        var i = 0;
        i < 100 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(
        (await owner.members(
          workspaceId,
        )).singleWhere((r) => r['username'] == workerName)['role'],
        'viewer',
      );
      await expectLater(
        worker.createJob(workspaceId, {
          'part_name': 'Forbidden',
          'printer': 'A1',
          'quantity': 1,
        }, 'forbidden-$nonce'),
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.status,
            'status',
            403,
          ),
        ),
      );
      await memberAction('移除成员');
      await tap(find.text('确认'));
      for (
        var i = 0;
        i < 100 && find.text(workerName).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(workerName), findsNothing);
      await capture('COL-01-member-removed');
      await expectLater(
        worker.jobs(workspaceId),
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.status,
            'status',
            404,
          ),
        ),
      );
      await tap(find.text('离开团队'));
      await tap(find.widgetWithText(FilledButton, '离开团队'));
      await tester.drag(find.byType(ListView).first, const Offset(0, 1500));
      await tester.pumpAndSettle();
      final lastAdmin = find.text('请先将另一位成员设为管理员，再离开团队');
      await waitFor(lastAdmin);
      await tester.ensureVisible(lastAdmin);
      await capture('COL-01-last-administrator-protected');

      CollaborationSession.token = 'expired-invalid-token';
      await tester.pumpWidget(page());
      final expired = find.text('团队登录已过期，请重新登录。');
      await waitFor(expired);
      await capture('SEC-02-invalid-token-reauthentication');
      expect(CollaborationSession.token, isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await store.db.close();
      store.dispose();
      await deleteDatabase(dbPath);
      CollaborationSession.clear();
    }
  });
}

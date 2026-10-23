import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real cloud demo login, profile, members, restore and logout', (
    tester,
  ) async {
    final local = AppStore()
      ..ready = true
      ..preferences = {'language': 'zh', 'reduceMotion': true, 'glass': true};
    final account = CloudAccount()..restoring = false;
    Future<void> idle() async {
      for (var i = 0; i < 450 && account.busy; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(account.busy, false);
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    await tester.pumpWidget(LineSightApp(store: local, cloud: account));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await capture('01-cloud-visitor-workbench');
    await tester.tap(find.byIcon(Icons.login).first);
    await tester.pumpAndSettle();
    expect(find.byType(CloudLoginPage), findsOneWidget);
    await capture('02-unified-secondary-login');
    await tester.tap(find.text('进入演示团队'));
    await idle();
    expect(account.error, isNull);
    expect(account.demoAccount, true);
    expect(account.activeWorkspace?['kind'], 'demo');
    expect(account.workspaces.every((w) => w['kind'] == 'demo'), true);
    await capture('03-cloud-demo-workbench');
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await capture('04-cloud-account-workspace');
    await tester.tap(find.text(account.displayName));
    await tester.pumpAndSettle();
    await capture('05-cloud-account-security');
    expect(find.text('修改密码'), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('团队成员'));
    for (
      var i = 0;
      i < 200 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await capture('06-cloud-team-members');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    final restored = CloudAccount();
    await tester.runAsync(restored.restore);
    expect(restored.demoAccount, true);
    expect(restored.activeWorkspace?['id'], account.activeWorkspace?['id']);
    restored.dispose();
    await tester.ensureVisible(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认').last);
    await idle();
    expect(account.error, isNull);
    expect(account.signedIn, false);
    expect(account.jobs, isEmpty);
    await capture('07-cloud-logout');
    final signedOut = CloudAccount();
    await tester.runAsync(signedOut.restore);
    expect(signedOut.signedIn, false);
    signedOut.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    account.dispose();
    local.dispose();
  });
}

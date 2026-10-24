import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/cloud_feedback.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/liquid_glass_bar.dart';

Future<void> showShell(WidgetTester tester) async {
  final store = AppStore()
    ..ready = true
    ..preferences = {
      'language': 'zh',
      'reduceMotion': true,
      'haptic': false,
      'glass': false,
    };
  final account = CloudAccount()..restoring = false;
  addTearDown(store.dispose);
  addTearDown(account.dispose);
  await tester.pumpWidget(LineSightApp(store: store, cloud: account));
  await tester.pumpAndSettle();
}

int selectedTab(WidgetTester tester) =>
    tester.widget<LiquidGlassBar>(find.byType(LiquidGlassBar)).selectedIndex;

Future<void> chooseTab(WidgetTester tester, int index) async {
  const icons = [
    Icons.space_dashboard_outlined,
    Icons.precision_manufacturing_outlined,
    Icons.fact_check_outlined,
    Icons.layers_outlined,
    Icons.person_outline_rounded,
  ];
  await tester.tap(
    find
        .descendant(
          of: find.byType(LiquidGlassBar),
          matching: find.byIcon(icons[index]),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Android back goes from each main tab to workbench', (
    tester,
  ) async {
    await showShell(tester);
    for (final tab in [1, 2, 3, 4]) {
      await chooseTab(tester, tab);
      expect(selectedTab(tester), tab);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      expect(find.byType(CloudShell), findsOneWidget);
    }
  });

  testWidgets('ordinary secondary back preserves origin tab', (tester) async {
    await showShell(tester);
    for (final tab in [2, 3, 4]) {
      await chooseTab(tester, tab);
      final context = tester.element(find.byType(CloudShell));
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const CloudLoginPage()));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CloudLoginPage), findsNothing);
      expect(selectedTab(tester), tab);
    }
  });

  for (final tab in [1, 2, 3, 4]) {
    for (final kind in ['scope', 'access', 'draft', '404', '403', '413']) {
      testWidgets(
        'explicit workbench from tab $tab via $kind clears nested routes',
        (tester) async {
          await showShell(tester);
          await chooseTab(tester, tab);
          final navigator = Navigator.of(
            tester.element(find.byType(CloudShell)),
          );
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Parent route')),
            ),
          );
          await tester.pumpAndSettle();
          navigator.push(
            MaterialPageRoute<void>(
              builder: (context) => switch (kind) {
                'scope' => cloudScopeChanged(context),
                'access' => cloudAccessRequired(context),
                'draft' => cloudDraftRecoveryFailure(
                  context,
                  const CollaborationApiException(503, '服务暂不可用'),
                  () async {},
                ),
                _ => Scaffold(
                  body: CloudFailurePanel(
                    failure: CollaborationApiException(
                      int.parse(kind),
                      'fixture',
                    ),
                    onRetry: () async {},
                  ),
                ),
              },
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('返回工作台').last);
          await tester.pumpAndSettle();
          expect(find.text('Parent route'), findsNothing);
          expect(selectedTab(tester), 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'login methods are directly visible in narrow Chinese and English UI',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final language in ['zh', 'en']) {
        final store = AppStore()
          ..ready = true
          ..preferences = {
            'language': language,
            'reduceMotion': true,
            'glass': false,
          };
        final cloud = CloudAccount()..restoring = false;
        await tester.pumpWidget(
          LineSightApp(key: UniqueKey(), store: store, cloud: cloud),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CloudLoginPanel), findsOneWidget);
        expect(find.byType(CloudLoginPage), findsNothing);
        expect(find.byIcon(Icons.login).hitTestable(), findsOneWidget);
        expect(find.byIcon(Icons.nfc).hitTestable(), findsOneWidget);
        expect(
          find.byIcon(Icons.explore_outlined).hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        cloud.dispose();
      }
    },
  );
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/special/special_workbench.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/presentation/aurora_glow.dart';
import 'package:linesight_flutter/presentation/presentation_controller.dart';
import 'package:linesight_flutter/store.dart';
import 'cloud_layout80_test.dart' show Layout80Account;

void main() {
  setUpAll(() async {
    for (final family in ['sans-serif', 'Roboto']) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'bundled Aurora renders over current workspace; back and ad skip retain workspace',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var milliseconds = 0;
      final presentation = PresentationController(
        elapsedMilliseconds: () => milliseconds,
      );
      final account = Layout80Account();
      final store = AppStore()
        ..ready = true
        ..preferences = {
          'specialEdition': true,
          'reduceMotion': true,
          'haptics': false,
          'glass': false,
        };
      addTearDown(presentation.dispose);
      addTearDown(account.dispose);
      addTearDown(store.dispose);
      // Exercise the real bundled shader as well as the Canvas fallback contract.
      await tester.runAsync(() async {
        final program = await ui.FragmentProgram.fromAsset(
          'shaders/aurora_glow.frag',
        );
        program.fragmentShader().dispose();
      });
      await tester.pumpWidget(
        LineSightApp(
          store: store,
          cloud: account,
          showBrandReveal: false,
          presentationController: presentation,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      final workspace = tester.state(find.byType(SpecialWorkbenchPage));
      presentation.showAurora();
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AuroraGlow), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/aurora84-overlay.png'),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(presentation.auroraVisible, false);
      expect(tester.state(find.byType(SpecialWorkbenchPage)), same(workspace));
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/checkcheck/backgrounds/ad_ai_assistant.png'),
          tester.element(find.byType(SpecialWorkbenchPage)),
        );
      });
      account.interactiveLoginRevision++;
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('special-login-ad')), findsOneWidget);
      expect(presentation.adRemaining, 5);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/aurora84-login-ad.png'),
      );
      await tester.tap(find.byKey(const ValueKey('skip-login-ad')));
      await tester.pump();
      expect(presentation.adVisible, false);
      expect(tester.state(find.byType(SpecialWorkbenchPage)), same(workspace));
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('startup presentation in light and reduced-motion dark mode', (
    tester,
  ) async {
    var surfaceReady = false;
    // Hold the presentation state for deterministic captures; timing is measured
    // separately by startup_profile_test.dart against a real SQLite database.
    for (final dark in [false, true]) {
      final store = AppStore()
        ..startupStage = dark ? '检查工作区与还原点' : '读取检测记录与本机设置'
        ..preferences = {'dark': dark, 'reduceMotion': dark};
      await tester.pumpWidget(LineSightApp(key: UniqueKey(), store: store));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2900));
      await tester.pump();
      expect(find.text(store.startupStage), findsOneWidget);
      expect(find.text('LineSight'), findsOneWidget);
      if (dark) {
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      }
      if (!surfaceReady) {
        await binding.convertFlutterSurfaceToImage();
        surfaceReady = true;
      }
      for (var i = 0; i < 4; i++) {
        binding.scheduleForcedFrame();
        await tester.pump(const Duration(milliseconds: 250));
      }
      var done = false;
      final shot = binding
          .takeScreenshot(dark ? 'startup-dark' : 'startup-light')
          .whenComplete(() => done = true);
      for (var i = 0; i < 100 && !done; i++) {
        binding.scheduleForcedFrame();
        await tester.pump(const Duration(milliseconds: 100));
      }
      await shot.timeout(const Duration(seconds: 15));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    }
  });
}

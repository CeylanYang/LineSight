import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/brand_reveal.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/auth.dart';
import 'package:linesight_flutter/screens/startup.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'cold reveal overlaps real SQLite initialization and opens login',
    (tester) async {
      final store = AppStore();
      final path = '${await getDatabasesPath()}/brand-boot-${uid()}.db';
      await tester.pumpWidget(
        LineSightApp(
          store: store,
          showBrandReveal: true,
          revealStartAfter: binding.waitUntilFirstFrameRasterized,
        ),
      );
      await tester.pump();
      expect(find.byType(StartupPage), findsOneWidget);
      await store.init(path: path);
      await tester.pumpAndSettle();
      expect(store.ready, isTrue);
      expect(store.startupError, isNull);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(find.byType(StartupPage), findsNothing);
      expect(tester.takeException(), isNull);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('brand-boot-login');
      await tester.pumpWidget(const SizedBox.shrink());
      await store.db.close();
      store.dispose();
      await deleteDatabase(path);
    },
  );

  testWidgets(
    'approved particle phases render with native Android haptics channel',
    (tester) async {
      final bytes = await rootBundle.load('assets/brand/reveal_logo.png');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final logo = (await codec.getNextFrame()).image;
      codec.dispose();
      for (final ms in [0, 700, 1700, 2470, 2800]) {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: BrandRevealPainter(
                      timeline: AlwaysStoppedAnimation(ms / 2800),
                      logo: logo,
                    ),
                  ),
                  if (ms >= 2470)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 102,
                      child: Column(
                        children: [
                          Text(
                            'LineSight',
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: ms == 2800 ? 1 : .35,
                              ),
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'PRECISION LOCKED IN FOCUS',
                            style: TextStyle(
                              color: Color(0xCCEEF5FF),
                              fontSize: 9,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (ms == 0) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pumpAndSettle();
        }
        await binding.takeScreenshot('brand-phase-$ms');
        expect(tester.takeException(), isNull);
      }
      // A channel smoke check exercises waveform/fallback construction on Android.
      const channel = MethodChannel('linesight/brand-haptics');
      await channel.invokeMethod<void>('play', {'elapsedMs': 1700});
      await channel.invokeMethod<void>('cancel');
      await tester.pumpWidget(const SizedBox.shrink());
      logo.dispose();
    },
  );
}

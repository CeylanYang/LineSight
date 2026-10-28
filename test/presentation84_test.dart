import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/editions/special/special_interaction.dart';
import 'package:linesight_flutter/presentation/aurora_glow.dart';
import 'package:linesight_flutter/presentation/aurora_input.dart';
import 'package:linesight_flutter/presentation/presentation_config.dart';
import 'package:linesight_flutter/presentation/presentation_controller.dart';
import 'package:linesight_flutter/presentation/presentation_layer.dart';

void update(
  PresentationController c, {
  bool signedIn = false,
  bool special = false,
  int revision = 0,
  bool ready = true,
  PresentationConfig config = const PresentationConfig(),
}) => c.update(
  settings: config,
  ready: ready,
  special: special,
  signedIn: signedIn,
  interactiveLoginRevision: revision,
);

void main() {
  testWidgets(
    'only interactive special login shows one skippable five second ad',
    (tester) async {
      var milliseconds = 0;
      final c = PresentationController(elapsedMilliseconds: () => milliseconds);
      addTearDown(c.dispose);
      update(c);
      update(c, signedIn: true, special: true, revision: 1);
      expect(c.adVisible, true);
      expect(c.adRemaining, 5);
      update(
        c,
        signedIn: true,
        special: true,
        revision: 1,
      ); // reload/token refresh
      milliseconds = 2000;
      await tester.pump(const Duration(seconds: 2));
      expect(c.adRemaining, 3);
      expect(c.adVisible, true);
      milliseconds = 5000;
      await tester.pump(const Duration(seconds: 3));
      expect(c.adVisible, false);
      update(c, signedIn: true, special: true, revision: 1);
      expect(c.adVisible, false);
      update(c, signedIn: false, special: true, revision: 1);
      update(c, signedIn: true, special: true, revision: 2);
      expect(c.adVisible, true);
      c.skipAd();
      expect(c.adVisible, false);
    },
  );

  test(
    'restoring a session, ordinary login and enabling the edition do not replay ad',
    () {
      final c = PresentationController();
      addTearDown(c.dispose);
      update(c, signedIn: true, special: true); // restored
      expect(c.adVisible, false);
      update(c, signedIn: false);
      update(c, signedIn: true, revision: 1);
      expect(c.adVisible, false);
      update(c, signedIn: true, special: true, revision: 1);
      expect(c.adVisible, false);
    },
  );

  testWidgets('special off, logout and signed feature disable cancel the ad', (
    tester,
  ) async {
    final c = PresentationController();
    addTearDown(c.dispose);
    update(c);
    update(c, signedIn: true, special: true, revision: 1);
    update(c, signedIn: true, special: false, revision: 1);
    expect(c.adVisible, false);
    update(c, signedIn: true, special: true, revision: 2);
    expect(c.adVisible, true);
    update(
      c,
      signedIn: true,
      special: true,
      revision: 2,
      config: const PresentationConfig(loginAdEnabled: false),
    );
    expect(c.adVisible, false);
    update(c, signedIn: true, special: true, revision: 3);
    update(c, signedIn: false, special: true, revision: 3);
    expect(c.adVisible, false);
  });

  test(
    'aurora is available in both editions and obeys lifecycle and remote kill switch',
    () {
      final c = PresentationController();
      addTearDown(c.dispose);
      update(c);
      expect(c.showAurora(), true);
      expect(c.lastTrigger, AuroraTrigger.appInterface);
      c.setForeground(false);
      expect(c.auroraVisible, false);
      expect(c.showAurora(), false);
      c.setForeground(true);
      expect(c.showAurora(trigger: AuroraTrigger.volumeDoublePress), true);
      update(c, config: const PresentationConfig(auroraEnabled: false));
      expect(c.auroraVisible, false);
      expect(c.showAurora(), false);
    },
  );

  testWidgets(
    'aurora dismiss gesture also clicks the underlying button without a wait',
    (tester) async {
      final c = PresentationController();
      final waits = SpecialInteractionController()..configure(true);
      addTearDown(c.dispose);
      addTearDown(waits.dispose);
      update(c);
      var clicks = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => PresentationLayer(
            controller: c,
            reduceMotion: true,
            onPassThroughInteraction: () =>
                waits.suppressFor(const Duration(milliseconds: 700)),
            child: SpecialInteractionLayer(controller: waits, child: child!),
          ),
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => clicks++,
                child: const Text('业务按钮'),
              ),
            ),
          ),
        ),
      );
      c.showAurora();
      await tester.pump();
      expect(find.byType(AuroraGlow), findsOneWidget);
      await tester.tap(find.text('业务按钮'));
      await tester.pump();
      expect(clicks, 1);
      expect(c.auroraVisible, false);
      expect(waits.percent, 0);
      expect(
        find.byKey(const ValueKey('special-loading-overlay')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'light swipe dismisses aurora and still scrolls the original page',
    (tester) async {
      final c = PresentationController();
      final scroll = ScrollController();
      addTearDown(c.dispose);
      addTearDown(scroll.dispose);
      update(c);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => PresentationLayer(
            controller: c,
            reduceMotion: true,
            onPassThroughInteraction: () {},
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              controller: scroll,
              children: const [SizedBox(height: 2000)],
            ),
          ),
        ),
      );
      c.showAurora();
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(c.auroraVisible, false);
      expect(scroll.offset, greaterThan(0));
      expect(find.byType(Navigator), findsOneWidget);
    },
  );

  testWidgets(
    'hardware key dismisses aurora and still reaches the focused control',
    (tester) async {
      final c = PresentationController();
      final text = TextEditingController();
      addTearDown(c.dispose);
      addTearDown(text.dispose);
      update(c);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => PresentationLayer(
            controller: c,
            reduceMotion: true,
            onPassThroughInteraction: () {},
            child: child!,
          ),
          home: Scaffold(body: TextField(controller: text, autofocus: true)),
        ),
      );
      await tester.pump();
      c.showAurora();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(c.auroraVisible, false);
      expect(FocusManager.instance.primaryFocus, isNotNull);
    },
  );

  testWidgets(
    'ad uses supplied bundled poster, 45 percent skip button and returns to page',
    (tester) async {
      final c = PresentationController();
      addTearDown(c.dispose);
      update(c);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => PresentationLayer(
            controller: c,
            onPassThroughInteraction: () {},
            child: child!,
          ),
          home: const Scaffold(body: Text('原工作台')),
        ),
      );
      update(c, signedIn: true, special: true, revision: 1);
      await tester.pump();
      expect(find.byKey(const ValueKey('special-login-ad')), findsOneWidget);
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('skip-login-ad')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 0.45);
      await tester.tap(find.byKey(const ValueKey('skip-login-ad')));
      await tester.pump();
      expect(find.byKey(const ValueKey('special-login-ad')), findsNothing);
      expect(find.text('原工作台').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'native channel triggers visual only and synchronizes disable state',
    (tester) async {
      final c = PresentationController();
      update(c);
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AuroraInputBridge.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      var dismissals = 0;
      final bridge = AuroraInputBridge(
        c,
        onDismissInteraction: () => dismissals++,
      );
      addTearDown(() {
        bridge.dispose();
        c.dispose();
        messenger.setMockMethodCallHandler(AuroraInputBridge.channel, null);
      });
      Future<void> incoming(String name) async {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          AuroraInputBridge.channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(name)),
          (ByteData? _) => done.complete(),
        );
        await done.future;
      }

      await incoming('show');
      expect(c.auroraVisible, true);
      expect(c.lastTrigger, AuroraTrigger.volumeDoublePress);
      await incoming('dismiss');
      expect(c.auroraVisible, false);
      expect(dismissals, 1);
      update(c, config: const PresentationConfig(auroraEnabled: false));
      await incoming('show');
      expect(c.auroraVisible, false);
      expect((calls.last.arguments as Map)['enabled'], false);
    },
  );
}

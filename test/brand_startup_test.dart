import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/auth.dart';
import 'package:linesight_flutter/screens/startup.dart';
import 'package:linesight_flutter/store.dart';

class BootStore extends AppStore {
  void loaded({bool haptics = true, bool reduced = false}) {
    ready = true;
    preferences = {'haptics': haptics, 'reduceMotion': reduced};
    notifyListeners();
  }

  void fail() {
    startupError = '无法读取本机数据库';
    notifyListeners();
  }

  void update() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('linesight/brand-haptics'),
          (call) async {
            calls.add(call);
            return null;
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('linesight/brand-haptics'),
          null,
        );
  });

  testWidgets('GPU startup cannot consume the reveal while storage preloads', (
    tester,
  ) async {
    final surface = Completer<void>();
    final s = BootStore();
    await tester.pumpWidget(
      LineSightApp(store: s, revealStartAfter: surface.future),
    );
    await tester.pump(const Duration(seconds: 4));
    s.loaded();
    await tester.pump();
    expect(find.byType(AuthPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(AuthPage), findsNothing);
    expect(calls.where((c) => c.method == 'play'), isEmpty);
    surface.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byType(StartupPage), findsOneWidget);
    expect(
      (calls.firstWhere((c) => c.method == 'play').arguments
          as Map)['elapsedMs'],
      0,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });

  testWidgets(
    'production reveal still runs when storage finishes before first mount',
    (tester) async {
      final s = BootStore()..loaded(haptics: false);
      await tester.pumpWidget(LineSightApp(store: s, showBrandReveal: true));
      await tester.pump();
      expect(find.byType(StartupPage), findsOneWidget);
      expect(find.byType(AuthPage), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(AuthPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'ready early prebuilds login without exposing it or restarting reveal',
    (tester) async {
      final s = BootStore();
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      s.loaded();
      await tester.pump();
      expect(find.byType(AuthPage), findsNothing);
      expect(find.byType(AuthPage, skipOffstage: false), findsOneWidget);
      expect(calls.where((c) => c.method == 'play'), hasLength(1));
      expect(
        (calls.firstWhere((c) => c.method == 'play').arguments
            as Map)['elapsedMs'],
        500,
      );
      await tester.pump(const Duration(milliseconds: 1500));
      s.update();
      await tester.pump();
      expect(find.byType(StartupPage), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 850));
      await tester.pump();
      expect(find.byType(StartupPage), findsNothing);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets(
    'slow storage holds final logo, announces work, then opens login',
    (tester) async {
      final s = BootStore();
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2900));
      await tester.pump();
      expect(find.byType(StartupPage), findsOneWidget);
      expect(find.text('打开本机存储'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(calls.where((c) => c.method == 'play'), isEmpty);
      s.loaded();
      await tester.pumpAndSettle();
      expect(find.byType(AuthPage), findsOneWidget);
      expect(calls.where((c) => c.method == 'play'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );

  testWidgets('saved haptics off and reduced motion suppress brand vibration', (
    tester,
  ) async {
    for (final reduced in [false, true]) {
      calls.clear();
      final s = BootStore();
      await tester.pumpWidget(LineSightApp(key: UniqueKey(), store: s));
      await tester.pump(const Duration(milliseconds: 100));
      s.loaded(haptics: reduced, reduced: reduced);
      await tester.pumpAndSettle();
      expect(find.byType(AuthPage), findsOneWidget);
      expect(calls.where((c) => c.method == 'play'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    }
  });

  testWidgets('background pauses visual clock and cancels native effects', (
    tester,
  ) async {
    final s = BootStore();
    await tester.pumpWidget(LineSightApp(store: s));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    s.loaded();
    await tester.pump();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(seconds: 5));
    expect(calls.last.method, 'cancel');
    expect(find.byType(StartupPage), findsOneWidget);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(calls.last.method, 'play');
    expect((calls.last.arguments as Map)['elapsedMs'], 300);
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });

  testWidgets(
    'storage error bypasses brand immediately for existing recovery',
    (tester) async {
      final s = BootStore();
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pump(const Duration(milliseconds: 100));
      s.fail();
      await tester.pumpAndSettle();
      expect(find.byType(StartupPage), findsNothing);
      expect(find.byType(AuthPage), findsNothing);
      expect(find.text('无法读取本机数据库'), findsOneWidget);
      expect(calls.last.method, 'cancel');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_task_ui_test.dart' show TaskAccount;

class FeedbackAccount extends TaskAccount {
  final gate = Completer<void>();
  bool deny = false;
  final states =
      jsonDecode(
            File(
              'docs/product/linesight/acceptance/closure-batch/live-workflow.json',
            ).readAsStringSync(),
          )['states']
          as Map;
  FeedbackAccount() {
    task
      ..clear()
      ..addAll(Map<String, dynamic>.from(states['inspection'] as Map));
  }
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'GET') {
      return super.request(
        method,
        path,
        body: body,
        idempotencyKey: idempotencyKey,
      );
    }
    submitted = Map<String, dynamic>.from(body as Map);
    await gate.future;
    if (deny) throw const CollaborationApiException(409, '任务已更新，请刷新后重试');
    task
      ..clear()
      ..addAll(
        Map<String, dynamic>.from(
          states[submitted!['verdict'] == 'fail' ? 'exception' : 'closed']
              as Map,
        ),
      );
    return task;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final effects = <String>[];
  late AppStore store;
  setUp(() {
    effects.clear();
    store = AppStore()
      ..ready = true
      ..preferences = {'haptics': true, 'reduceMotion': true, 'glass': false};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            effects.add(call.arguments as String);
          }
          return null;
        });
  });
  tearDown(() {
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  test(
    'selection, confirmed success and warning are distinct and haptics off is silent',
    () async {
      store.feedback();
      store.feedback(kind: AppFeedback.success);
      store.feedback(kind: AppFeedback.warning);
      await Future<void>.delayed(Duration.zero);
      expect(effects, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
      store.preferences['haptics'] = false;
      store.feedback(kind: AppFeedback.success);
      store.feedback(kind: AppFeedback.warning);
      await Future<void>.delayed(Duration.zero);
      expect(effects, hasLength(3));
      final record = File(
        'docs/product/linesight/acceptance/access2-batch/haptic-platform-calls.json',
      );
      record.parent.createSync(recursive: true);
      record.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'source': 'Captured Flutter SystemChannels.platform calls in a test messenger', 'effects': effects, 'haptics_disabled_additional_calls': 0, 'physical_vibration_verified': false})}\n',
      );
    },
  );
  test(
    'missing native haptic support cannot turn a completed action into an error',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            throw PlatformException(code: 'unavailable');
          });
      store.feedback(kind: AppFeedback.success);
      await Future<void>.delayed(Duration.zero);
    },
  );

  Future<void> show(
    WidgetTester tester,
    FeedbackAccount account, {
    String language = 'zh',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: 'EvidenceFont',
          colorScheme: appTheme(false).colorScheme,
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: CloudTaskPage(job: account.task, workspaceId: 1),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(
    WidgetTester tester, {
    bool failing = false,
    String language = 'zh',
  }) async {
    final label = language == 'zh' ? '登记检验' : 'Record inspection';
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(
      tester.element(find.byType(CloudTaskCommandPage)),
    )!;
    expect(route, isA<PageRouteBuilder<void>>());
    expect((route as PageRoute<void>).transitionDuration, Duration.zero);
    if (failing) {
      await tester.tap(find.text(language == 'zh' ? '异常' : 'Issue').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'DEMO · surface mark',
      );
    }
    final submit = language == 'zh' ? '确认提交' : 'Submit';
    await tester.scrollUntilVisible(
      find.text(submit),
      250,
      scrollable: find
          .descendant(
            of: find.byType(CloudTaskCommandPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text(submit));
    await tester.pump();
  }

  testWidgets('no success feedback while pending or after a server rejection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = FeedbackAccount()..deny = true;
    addTearDown(account.dispose);
    await show(tester, account);
    effects.clear();
    await enter(tester);
    expect(account.submitted, isNotNull);
    expect(effects, isEmpty);
    expect(find.text('检验已提交'), findsNothing);
    account.gate.complete();
    await tester.pumpAndSettle();
    expect(effects, ['HapticFeedbackType.heavyImpact']);
    expect(find.byType(CloudTaskCommandPage), findsOneWidget);
    expect(find.text('检验已提交'), findsNothing);
  });
  testWidgets(
    'identity change while submitting suppresses feedback for the old identity',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = FeedbackAccount();
      addTearDown(account.dispose);
      await show(tester, account);
      effects.clear();
      await enter(tester);
      account.profile = {'id': 'other-user'};
      account.notifyListeners();
      await tester.pump();
      account.gate.complete();
      await tester.pumpAndSettle();
      expect(effects, isEmpty);
      expect(find.text('检验已提交'), findsNothing);
    },
  );
  for (final modes in [(true, false), (false, true), (false, false)]) {
    testWidgets(
      'page routes honor preference ${modes.$1} and system ${modes.$2} without losing return values',
      (tester) async {
        store.preferences['reduceMotion'] = modes.$1;
        String? result;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => AppScope(
              store: store,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: modes.$2),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push(
                      appPageRoute<String>(
                        context,
                        const Scaffold(body: Text('Destination')),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final context = tester.element(find.text('Destination'));
        final route = ModalRoute.of(context)! as PageRoute<String>;
        expect(
          route.transitionDuration,
          Duration(milliseconds: modes.$1 || modes.$2 ? 0 : 240),
        );
        Navigator.of(context).pop('card-or-photo-result');
        await tester.pumpAndSettle();
        expect(result, 'card-or-photo-result');
      },
    );
  }
  for (final language in ['zh', 'en']) {
    for (final failing in [false, true]) {
      testWidgets(
        'confirmed ${failing ? 'issue' : 'pass'} $language returns to task and records feedback PNG',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 1500));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await (FontLoader('EvidenceFont')..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
                  ),
                ),
              ))
              .load();
          await (FontLoader('Roboto')..addFont(
                Future.value(
                  ByteData.sublistView(
                    File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
                  ),
                ),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final account = FeedbackAccount();
          addTearDown(account.dispose);
          await show(tester, account, language: language);
          effects.clear();
          await enter(tester, failing: failing, language: language);
          expect(effects, isEmpty);
          account.gate.complete();
          await tester.pumpAndSettle();
          expect(effects, [
            failing
                ? 'HapticFeedbackType.heavyImpact'
                : 'HapticFeedbackType.lightImpact',
          ]);
          expect(find.byType(CloudTaskCommandPage), findsNothing);
          expect(find.byType(CloudTaskPage), findsOneWidget);
          expect(tester.takeException(), isNull);
          // Keep the snackbar visible at the confirmed result frame.
          await expectLater(
            find.byType(Scaffold).first,
            matchesGoldenFile(
              '../docs/product/linesight/acceptance/ui80-batch/access2-batch/png/79-${failing ? 'issue' : 'pass'}-$language-desktop-render.png',
            ),
          );
        },
      );
    }
  }
}

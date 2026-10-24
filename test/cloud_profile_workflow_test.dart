import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_profiles.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_task_ui_test.dart' show DraftTaskAccount;

const printerProfile = <String, dynamic>{
  'id': 'starter:a1',
  'name': 'Bambu Lab A1',
  'version': 'starter-v1',
  'source': 'https://bambulab.com/en/a1',
  'note': 'Reference profile',
};

class ProfileAccount extends DraftTaskAccount {
  int reads = 0;
  Object? failure;
  Completer<List<Map<String, dynamic>>>? pending;
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'GET') {
      if (path.endsWith('printer-profiles/')) {
        reads++;
        if (failure != null) throw failure!;
        return pending == null ? [printerProfile] : pending!.future;
      }
      if (path.contains('/jobs/')) {
        return super.request(method, path);
      }
      return [];
    }
    return super.request(
      method,
      path,
      body: body,
      idempotencyKey: idempotencyKey,
    );
  }
}

void main() {
  late ProfileAccount account;
  late AppStore store;
  setUp(() {
    account = ProfileAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false, 'haptic': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> show(
    WidgetTester tester,
    Widget page, {
    String language = 'en',
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(false).copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style:
                (appTheme(false).filledButtonTheme.style ?? const ButtonStyle())
                    .copyWith(
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(
                          fontFamily: 'EvidenceFont',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style:
                (appTheme(false).outlinedButtonTheme.style ??
                        const ButtonStyle())
                    .copyWith(
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(
                          fontFamily: 'EvidenceFont',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
          ),
          textButtonTheme: TextButtonThemeData(
            style:
                (appTheme(false).textButtonTheme.style ?? const ButtonStyle())
                    .copyWith(
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(
                          fontFamily: 'EvidenceFont',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
          ),

          textTheme: appTheme(
            false,
          ).textTheme.apply(fontFamily: 'EvidenceFont'),
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: appTheme(false).segmentedButtonTheme.style!.copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(
                  fontFamily: 'EvidenceFont',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          appBarTheme: appTheme(false).appBarTheme.copyWith(
            titleTextStyle: appTheme(
              false,
            ).appBarTheme.titleTextStyle!.copyWith(fontFamily: 'EvidenceFont'),
          ),
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openPage(context, page),
              child: const Text('Origin'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Origin'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> tap(WidgetTester tester, String text) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(text),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'picker round trip preserves task fields and submits selected profile',
    (tester) async {
      await show(tester, const CloudCreateTaskPage());
      await tester.enterText(field('Part name'), 'Bracket');
      await tap(tester, 'Choose printer profile');
      await tap(tester, 'Bambu Lab A1');
      await tap(tester, 'Use this profile');
      expect(find.text('New job'), findsWidgets);
      expect(
        tester.widget<TextField>(field('Part name')).controller!.text,
        'Bracket',
      );
      expect(
        tester.widget<TextField>(field('Printer')).controller!.text,
        'Bambu Lab A1',
      );
      expect(account.reads, 1);
      await tap(tester, 'Create job');
      expect(account.submitted?['profile_id'], 'starter:a1');
      expect(account.submitted?['printer'], 'Bambu Lab A1');
      expect(find.byType(CloudTaskPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
    },
  );
  testWidgets(
    'cancel picker leaves manual device unchanged and sends no write',
    (tester) async {
      await show(tester, const CloudCreateTaskPage());
      await tester.enterText(field('Printer'), 'Manual device');
      await tap(tester, 'Choose printer profile');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Printer')).controller!.text,
        'Manual device',
      );
      expect(account.submitted, isNull);
    },
  );
  testWidgets(
    'preselected configuration preserves existing draft fields and can be detached',
    (tester) async {
      account.saved[account.draftKey('create')!] = {
        'name': 'Saved part',
        'printer': 'Old printer',
        'quantity': '3',
      };
      await show(
        tester,
        const CloudCreateTaskPage(initialProfile: printerProfile),
      );
      expect(
        tester.widget<TextField>(field('Part name')).controller!.text,
        'Saved part',
      );
      expect(
        tester.widget<TextField>(field('Printer')).controller!.text,
        'Bambu Lab A1',
      );
      await tester.tap(find.byTooltip('Enter printer manually'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Printer'), 'Other device');
      await tap(tester, 'Create job');
      expect(account.submitted!.containsKey('profile_id'), isFalse);
      expect(account.submitted?['printer'], 'Other device');
    },
  );
  testWidgets('profile selection survives restoring a saved task draft', (
    tester,
  ) async {
    account.saved[account.draftKey('create')!] = {
      'name': 'Saved part',
      'printer': 'Bambu Lab A1',
      'quantity': '2',
      'profile': printerProfile,
    };
    await show(tester, const CloudCreateTaskPage());
    expect(find.byTooltip('Enter printer manually'), findsOneWidget);
    await tap(tester, 'Create job');
    expect(account.submitted?['profile_id'], 'starter:a1');
  });
  testWidgets('read failure retry never writes and recovers catalogue', (
    tester,
  ) async {
    account.failure = const CollaborationApiException(503, 'Unavailable');
    await show(tester, const CloudProfilesPage());
    expect(find.text('Bambu Lab A1'), findsNothing);
    account.failure = null;
    await tap(tester, 'Retry');
    expect(account.reads, 2);
    expect(account.submitted, isNull);
    expect(find.text('Bambu Lab A1'), findsOneWidget);
  });
  testWidgets('late catalogue response is hidden after switching workspace', (
    tester,
  ) async {
    account.pending = Completer();
    await show(tester, const CloudProfilesPage());
    account.activeWorkspace = {'id': 2, 'role': 'owner'};
    account.notifyListeners();
    account.pending!.complete([printerProfile]);
    await tester.pumpAndSettle();
    expect(find.text('Bambu Lab A1'), findsNothing);
    expect(account.submitted, isNull);
  });
  testWidgets('viewer can inspect configuration without create action', (
    tester,
  ) async {
    account.activeWorkspace = {'id': 1, 'role': 'viewer'};
    await show(tester, const CloudProfileDetailPage(profile: printerProfile));
    expect(find.text('https://bambulab.com/en/a1'), findsOneWidget);
    expect(find.text('Create task with this profile'), findsNothing);
    expect(account.submitted, isNull);
  });
  testWidgets(
    'detail starts a task and back returns to the same configuration',
    (tester) async {
      await show(tester, const CloudProfileDetailPage(profile: printerProfile));
      await tap(tester, 'Create task with this profile');
      expect(
        tester.widget<TextField>(field('Printer')).controller!.text,
        'Bambu Lab A1',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Create task with this profile'), findsOneWidget);
      expect(account.submitted, isNull);
    },
  );
  testWidgets(
    'cloud authentication does not reveal local modules without local login',
    (tester) async {
      await show(tester, const LocalConfigurationGate());
      expect(
        find.text('Search recipe name, material or version'),
        findsNothing,
      );
      expect(find.text('Local recipes and stations'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    },
  );
  testWidgets(
    'locking local identity removes the entire nested configuration stack',
    (tester) async {
      const engineer = LocalUser('e', 'engineer', 'Engineer', 'engineer', true);
      store.user = engineer;
      store.users = [engineer];
      await show(tester, const LocalConfigurationGate());
      final nested = tester.state<NavigatorState>(find.byType(Navigator).last);
      nested.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Private station editor')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private station editor'), findsOneWidget);
      store.user = null;
      store.session++;
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Private station editor'), findsNothing);
      store.user = engineer;
      store.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Private station editor'), findsNothing);
      expect(find.text('Local recipes and stations'), findsOneWidget);
    },
  );
  testWidgets(
    'historical checklist detail opens task with exact selected template',
    (tester) async {
      account.templates = [
        {
          'id': 10,
          'name': 'Bracket',
          'version': 1,
          'built_in': true,
          'items': [],
        },
        {
          'id': 11,
          'name': 'Bracket',
          'version': 2,
          'built_in': true,
          'items': [],
        },
      ];
      await show(
        tester,
        CloudTemplateDetailPage(template: account.templates.first),
      );
      await tap(tester, 'Create task with this checklist');
      await tester.enterText(field('Part name'), 'Historical checklist task');
      await tester.enterText(field('Printer'), 'Manual device');
      await tap(tester, 'Create job');
      expect(account.submitted?['template_id'], 10);
    },
  );
  for (final language in ['zh', 'en']) {
    for (final state in ['hub', 'catalogue', 'detail', 'task', 'local']) {
      testWidgets('$language profile $state component PNG', (tester) async {
        await (FontLoader('EvidenceFont')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
                ),
              ),
            ))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        if (state == 'local') {
          store.user = const LocalUser(
            'e',
            'engineer',
            'Engineer',
            'engineer',
            true,
          );
        }
        await show(tester, switch (state) {
          'hub' => const Scaffold(body: CloudConfigurationPage()),
          'catalogue' => const CloudProfilesPage(),
          'detail' => const CloudProfileDetailPage(profile: printerProfile),
          'local' => const LocalConfigurationGate(),
          _ => const CloudCreateTaskPage(initialProfile: printerProfile),
        }, language: language);
        await tester.binding.setSurfaceSize(const Size(360, 1100));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).last,
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/ui80-batch/profile-batch/png/190-profile-$state-$language-component.png',
          ),
        );
      });
    }
  }
}

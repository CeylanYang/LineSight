import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/cloud_profiles.dart';
import 'package:linesight_flutter/screens/cloud_profile_editor.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/screens/modules.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_profile_workflow_test.dart' show ProfileAccount;

const pinnedChecklist = <String, dynamic>{
  'id': 77,
  'name': 'Assembly check',
  'version': 2,
  'built_in': true,
  'items': [
    {'id': 'size', 'label': 'Dimensions', 'required': true, 'allow_na': false},
    {'id': 'surface', 'label': 'Surface', 'required': true, 'allow_na': true},
    {'id': 'fit', 'label': 'Fit', 'required': false, 'allow_na': true},
  ],
};
const managedProfile = <String, dynamic>{
  'id': 'workspace:42',
  'name': 'Station printer',
  'version': 'v1',
  'source': 'https://example.com/profile',
  'note': 'PLA',
  'override': true,
  'revision': 1,
  'default_template_id': 77,
  'default_template': pinnedChecklist,
};

class ManageAccount extends ProfileAccount {
  final posts = <({Map<String, dynamic> body, String? key})>[];
  Object? writeFailure;
  Completer<List<Map<String, dynamic>>>? readGate;
  Completer<Map<String, dynamic>>? writeGate;
  List<Map<String, dynamic>> rows = [managedProfile];
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (path.endsWith('printer-profiles/')) {
      if (method == 'GET') {
        reads++;
        return readGate == null ? rows : readGate!.future;
      }
      final payload = Map<String, dynamic>.from(body as Map);
      posts.add((body: payload, key: idempotencyKey));
      if (writeFailure != null) throw writeFailure!;
      if (writeGate != null) return writeGate!.future;
      final result = {
        ...payload,
        'id': payload['id'] ?? 'workspace:43',
        'override': true,
        'revision': (payload['revision'] as int? ?? 0) + 1,
        'default_template': payload['default_template_id'] == 77
            ? pinnedChecklist
            : null,
      };
      rows = [...rows.where((p) => p['id'] != result['id']), result];
      return result;
    }
    return super.request(
      method,
      path,
      body: body,
      idempotencyKey: idempotencyKey,
    );
  }
}

Map<String, dynamic> profileAt(int revision, String version) => {
  ...managedProfile,
  'revision': revision,
  'version': version,
};

void main() {
  late ManageAccount account;
  late AppStore store;
  setUp(() {
    account = ManageAccount()..templates = [pinnedChecklist];
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
    Size size = const Size(700, 1300),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = appTheme(false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme.copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: (theme.filledButtonTheme.style ?? const ButtonStyle())
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
            style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
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
            style: (theme.textButtonTheme.style ?? const ButtonStyle())
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

          textTheme: theme.textTheme.apply(fontFamily: 'EvidenceFont'),
          appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle!.copyWith(
              fontFamily: 'EvidenceFont',
            ),
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

  Finder input(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> tap(WidgetTester tester, String text) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    if (find.text(text).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(text),
        250,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pump();
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'edit pins checklist version and posts revision; receipt returns to updated detail',
    (tester) async {
      await show(tester, const CloudProfileDetailPage(profile: managedProfile));
      await tap(tester, 'Edit printer profile');
      expect(tester.widget<TextField>(input('Profile name')).readOnly, isTrue);
      await tester.enterText(input('Profile version'), 'v2');
      await tap(tester, 'Save printer profile');
      expect(account.posts.single.body['revision'], 1);
      expect(account.posts.single.body['default_template_id'], 77);
      expect(find.text('Printer profile saved'), findsOneWidget);
      await tap(tester, 'Done');
      expect(find.text('Team profile · v2'), findsOneWidget);
      await tap(tester, 'Edit printer profile');
      await tester.enterText(input('Profile version'), 'v3');
      await tap(tester, 'Save printer profile');
      expect(account.posts.last.body['revision'], 2);
    },
  );
  testWidgets('copy is a new named profile and keeps source checklist', (
    tester,
  ) async {
    await show(
      tester,
      const CloudProfileEditor(profile: managedProfile, copy: true),
    );
    expect(
      tester.widget<TextField>(input('Profile name')).controller!.text,
      'Station printer Copy',
    );
    await tap(tester, 'Save printer profile');
    expect(account.posts.single.body.containsKey('id'), isFalse);
    expect(account.posts.single.body['default_template_id'], 77);
    expect(managedProfile['revision'], 1);
  });
  testWidgets('required and malformed URL validation blocks requests', (
    tester,
  ) async {
    await show(tester, const CloudProfileEditor());
    await tap(tester, 'Save printer profile');
    expect(account.posts, isEmpty);
    await tester.enterText(input('Profile name'), 'Test');
    await tester.enterText(input('HTTPS profile source'), 'http://example.com');
    await tap(tester, 'Save printer profile');
    expect(account.posts, isEmpty);
    expect(find.text('Enter a valid HTTPS address'), findsOneWidget);
  });
  testWidgets('manual retry reuses key and changed edits receive a new key', (
    tester,
  ) async {
    account.writeFailure = const CollaborationApiException(
      503,
      'Private details',
    );
    await show(tester, const CloudProfileEditor(profile: managedProfile));
    await tap(tester, 'Save printer profile');
    await tap(tester, 'Save printer profile');
    expect(account.posts[0].key, account.posts[1].key);
    await tester.enterText(input('Profile version'), 'v2');
    await tap(tester, 'Save printer profile');
    expect(account.posts[2].key, isNot(account.posts[1].key));
    expect(find.text('Private details'), findsNothing);
  });
  testWidgets(
    'conflict requires explicit continuation and retains edits without automatic replay',
    (tester) async {
      account.writeFailure = CollaborationApiException(
        409,
        'Private',
        details: {
          'code': 'profile_version_conflict',
          'current': profileAt(3, 'v3'),
        },
      );
      await show(tester, const CloudProfileEditor(profile: managedProfile));
      await tester.enterText(input('Profile note'), 'Retained note');
      await tap(tester, 'Save printer profile');
      expect(account.posts.length, 1);
      await tap(tester, 'Continue from latest, keeping edits');
      expect(account.posts.length, 1);
      expect(
        tester.widget<TextField>(input('Profile note')).controller!.text,
        'Retained note',
      );
      account.writeFailure = null;
      await tap(tester, 'Save printer profile');
      expect(account.posts.last.body['revision'], 3);
      expect(account.posts.last.body['note'], 'Retained note');
    },
  );
  testWidgets(
    'dirty back cancellation keeps text and explicit discard leaves',
    (tester) async {
      await show(tester, const CloudProfileEditor(profile: managedProfile));
      await tester.enterText(input('Profile note'), 'Draft note');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('Profile note')).controller!.text,
        'Draft note',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard and go back'));
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect(account.posts, isEmpty);
    },
  );
  testWidgets(
    'late save after switching workspaces cannot update parent or expose receipt',
    (tester) async {
      account.writeGate = Completer();
      int callbacks = 0;
      await show(
        tester,
        CloudProfileEditor(
          profile: managedProfile,
          onSaved: (_) => callbacks++,
        ),
      );
      await tap(tester, 'Save printer profile');
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifyListeners();
      account.writeGate!.complete({...managedProfile, 'revision': 2});
      await tester.pumpAndSettle();
      expect(callbacks, 0);
      expect(find.text('Printer profile saved'), findsNothing);
      expect(find.text('Workspace changed'), findsOneWidget);
    },
  );
  testWidgets(
    'a delayed catalogue read cannot erase an acknowledged new profile',
    (tester) async {
      account.readGate = Completer();
      await show(tester, const CloudProfilesPage());
      await tester.tap(find.byTooltip('Create printer profile'));
      await tester.pumpAndSettle();
      await tester.enterText(input('Profile name'), 'New printer');
      await tester.enterText(
        input('HTTPS profile source'),
        'https://example.com/new',
      );
      await tap(tester, 'Save printer profile');
      account.readGate!.complete([]);
      await tester.pumpAndSettle();
      await tap(tester, 'Done');
      expect(find.text('New printer'), findsOneWidget);
      expect(account.posts.length, 1);
    },
  );
  testWidgets('viewer and operator have no maintenance actions', (
    tester,
  ) async {
    for (final role in ['viewer', 'operator']) {
      account.activeWorkspace = {'id': 1, 'role': role};
      await show(tester, const CloudProfileDetailPage(profile: managedProfile));
      expect(find.text('Edit printer profile'), findsNothing);
      expect(find.text('Copy printer profile'), findsNothing);
    }
  });
  testWidgets(
    'profile default checklist is available even if main template catalogue is stale',
    (tester) async {
      account.templates = [];
      await show(
        tester,
        const CloudCreateTaskPage(initialProfile: managedProfile),
      );
      await tester.enterText(input('Part name'), 'Pinned task');
      expect(find.text('Assembly check · v2'), findsWidgets);
      await tap(tester, 'Create job');
      expect(account.submitted?['template_id'], 77);
      expect(account.submitted?['profile_revision'], 1);
    },
  );
  testWidgets(
    'choosing an unbound profile preserves the draft explicit checklist',
    (tester) async {
      account.templates = [
        {...pinnedChecklist, 'id': 78, 'version': 3},
        pinnedChecklist,
      ];
      account.saved[account.draftKey('create')!] = {
        'name': 'Saved task',
        'quantity': '1',
        'templateId': 77,
      };
      final unbound = Map<String, dynamic>.from(managedProfile)
        ..['default_template_id'] = null
        ..['default_template'] = null;
      await show(tester, CloudCreateTaskPage(initialProfile: unbound));
      await tap(tester, 'Create job');
      expect(account.submitted?['template_id'], 77);
    },
  );
  for (final language in ['zh', 'en']) {
    for (final state in [
      'create',
      'edit',
      'copy',
      'detail',
      'receipt',
      'conflict',
      'changeover',
    ]) {
      testWidgets('$language managed profile $state PNG', (tester) async {
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
        if (state == 'changeover') {
          store.user = const LocalUser(
            'e',
            'engineer',
            'Engineer',
            'engineer',
            true,
          );
        }
        await show(
          tester,
          switch (state) {
            'create' => const CloudProfileEditor(),
            'detail' => const CloudProfileDetailPage(profile: managedProfile),
            'changeover' => ChangeoverPage(
              recipeId: store.data.recipes.last.id,
            ),
            'copy' => const CloudProfileEditor(
              profile: managedProfile,
              copy: true,
            ),
            _ => const CloudProfileEditor(profile: managedProfile),
          },
          language: language,
          size: const Size(360, 1100),
        );
        if (state == 'receipt') {
          await tap(
            tester,
            language == 'zh' ? '保存打印配置' : 'Save printer profile',
          );
        }
        if (state == 'conflict') {
          account.writeFailure = CollaborationApiException(
            409,
            'private',
            details: {
              'code': 'profile_version_conflict',
              'current': profileAt(2, 'v2'),
            },
          );
          await tap(
            tester,
            language == 'zh' ? '保存打印配置' : 'Save printer profile',
          );
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).last,
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/profile-management-batch/png/200-profile-$state-$language-component.png',
          ),
        );
      });
    }
  }
}

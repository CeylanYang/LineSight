import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_profiles.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/screens/cloud_templates.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_task_ui_test.dart' show DraftTaskAccount;
import 'cloud_profile_workflow_test.dart' show printerProfile;

class CreateNavigationAccount extends DraftTaskAccount {
  int writes = 0, refreshes = 0;
  Completer<Map<String, dynamic>?>? draftGate;
  bool draftReadFails = false, draftSaveFails = false;
  @override
  Future<void> saveDraft(String key, Map<String, dynamic> value) async {
    if (draftSaveFails) throw StateError('storage unavailable');
    await super.saveDraft(key, value);
  }

  @override
  Future<Map<String, dynamic>?> readDraft(String key) async {
    if (draftReadFails) throw StateError('storage unavailable');
    if (draftGate != null) return draftGate!.future;
    return super.readDraft(key);
  }

  Completer<Map<String, dynamic>>? postGate;
  final reloadGate = Completer<void>();
  Object? writeFailure;
  bool detailUnavailable = false, cleanupFails = false;
  final receipt = <String, dynamic>{
    'id': 'created-42',
    'version': 1,
    'status': 'queued',
    'part_name': 'Valve bracket',
    'printer': 'Bambu Lab A1',
    'quantity': 3,
    'batch_code': 'BATCH-20261024',
    'note': '',
    'tracking_mode': 'batch',
    'created_at': '2026-10-24T00:00:00Z',
    'updated_at': '2026-10-24T00:00:00Z',
    'inspections': [],
    'exceptions': [],
    'evidence': [],
  };
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'POST' && path.endsWith('/jobs/')) {
      writes++;
      submitted = Map<String, dynamic>.from(body as Map);
      submittedKey = idempotencyKey;
      if (writeFailure != null) throw writeFailure!;
      return postGate == null ? receipt : postGate!.future;
    }
    if (method == 'GET' && path.contains('/jobs/')) {
      if (detailUnavailable) {
        throw const CollaborationApiException(503, '服务暂不可用，请稍后重试');
      }
      return path.endsWith('/history/') ? [] : receipt;
    }
    return [];
  }

  @override
  Future<void> reload() async {
    refreshes++;
    await reloadGate.future;
  }

  @override
  Future<void> deleteDraft(String key) async {
    if (cleanupFails) {
      throw const FileSystemException('test storage unavailable');
    }
    await super.deleteDraft(key);
  }
}

void main() {
  late CreateNavigationAccount account;
  late AppStore store;
  setUp(() {
    account = CreateNavigationAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false, 'haptic': false};
  });
  tearDown(() {
    if (!account.reloadGate.isCompleted) account.reloadGate.complete();
    account.dispose();
    store.dispose();
  });
  Future<void> show(
    WidgetTester tester, {
    Widget page = const CloudCreateTaskPage(),
    String language = 'en',
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = appTheme(false);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'EvidenceFont'),
          appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle!.copyWith(
              fontFamily: 'EvidenceFont',
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: theme.filledButtonTheme.style!.copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontFamily: 'EvidenceFont', fontSize: 14),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: theme.outlinedButtonTheme.style!.copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontFamily: 'EvidenceFont', fontSize: 14),
              ),
            ),
          ),
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: theme.segmentedButtonTheme.style!.copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontFamily: 'EvidenceFont', fontSize: 12),
              ),
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets(
    'slow draft restore blocks editing until original data is ready',
    (tester) async {
      account.draftGate = Completer<Map<String, dynamic>?>();
      await show(tester, settle: false);
      expect(find.byType(TextFormField), findsNothing);
      expect(account.writes, 0);
      expect(account.saved, isEmpty);
      account.draftGate!.complete({
        'name': 'Recovered bracket',
        'quantity': '7',
        'request_key': 'stable-request',
      });
      await tester.pumpAndSettle();
      expect(find.text('Recovered bracket'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
    },
  );

  testWidgets('failed restore cannot overwrite old draft and supports retry', (
    tester,
  ) async {
    final key = account.draftKey('create')!;
    account.saved[key] = {
      'name': 'Saved bracket',
      'quantity': '3',
      'request_key': 'old-key',
    };
    account.draftReadFails = true;
    await show(tester, language: 'zh');
    expect(find.byType(TextFormField), findsNothing);
    expect(account.saved[key]?['name'], 'Saved bracket');
    account.draftReadFails = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('Saved bracket'), findsOneWidget);
    expect(account.writes, 0);
  });

  testWidgets(
    'manual draft retry clears stale error and confirms durable save',
    (tester) async {
      await show(tester, language: 'zh');
      account.draftSaveFails = true;
      await tester.enterText(find.byType(TextFormField).first, 'Bracket draft');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存草稿'));
      await tester.pumpAndSettle();
      expect(find.text('草稿保存失败，请重试'), findsOneWidget);
      expect(find.text('草稿已保存'), findsNothing);
      expect(account.saved, isEmpty);
      account.draftSaveFails = false;
      await tester.tap(find.text('保存草稿'));
      await tester.pumpAndSettle();
      expect(find.text('草稿保存失败，请重试'), findsNothing);
      expect(find.text('草稿已保存'), findsOneWidget);
      expect(
        account.saved[account.draftKey('create')]?['name'],
        'Bracket draft',
      );
      expect(account.writes, 0);
    },
  );

  Future<void> tap(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    if (find.text(label).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(label),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> fill(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Valve bracket');
    await tester.enterText(fields.at(1), 'Bambu Lab A1');
    await tester.enterText(fields.at(2), '3');
  }

  testWidgets(
    'confirmed create opens receipt immediately while list reload is pending; back skips form',
    (tester) async {
      await show(tester);
      await fill(tester);
      await tap(tester, 'Create job');
      expect(account.writes, 1);
      expect(account.refreshes, 1);
      expect(find.byType(CloudTaskPage), findsOneWidget);
      expect(find.byType(CloudCreateTaskPage), findsNothing);
      expect(find.text('Valve bracket'), findsWidgets);
      expect(account.saved, isEmpty);
      expect(account.reloadGate.isCompleted, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect(account.writes, 1);
    },
  );
  testWidgets(
    'task read failure preserves confirmed receipt and retry never repeats creation',
    (tester) async {
      account.detailUnavailable = true;
      await show(tester);
      await fill(tester);
      await tap(tester, 'Create job');
      expect(find.byType(CloudTaskPage), findsOneWidget);
      expect(find.text('Valve bracket'), findsWidgets);
      expect(find.byType(CloudCreateTaskPage), findsNothing);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(account.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'local draft cleanup failure does not turn successful creation into a failed form',
    (tester) async {
      account.cleanupFails = true;
      await show(tester);
      await fill(tester);
      await tap(tester, 'Create job');
      expect(find.byType(CloudTaskPage), findsOneWidget);
      expect(account.writes, 1);
      expect(account.saved.values.single['request_key'], account.submittedKey);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'rejected create keeps form and draft without opening any result',
    (tester) async {
      account.writeFailure = const CollaborationApiException(
        409,
        'SN已属于其他任务，不可重复统计',
      );
      await show(tester);
      await fill(tester);
      await tap(tester, 'Create job');
      expect(find.byType(CloudCreateTaskPage), findsOneWidget);
      expect(find.byType(CloudTaskPage), findsNothing);
      expect(account.refreshes, 0);
      expect(account.saved.values.single['name'], 'Valve bracket');
    },
  );
  testWidgets(
    'late create receipt after team change cannot navigate, delete draft, or refresh new team',
    (tester) async {
      account.postGate = Completer<Map<String, dynamic>>();
      await show(tester);
      await fill(tester);
      await tap(tester, 'Create job', settle: false);
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifyListeners();
      await tester.pumpAndSettle();
      account.postGate!.complete(account.receipt);
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskPage), findsNothing);
      expect(account.refreshes, 0);
      expect(account.saved, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'late create receipt after leaving form does not redirect caller',
    (tester) async {
      account.postGate = Completer<Map<String, dynamic>>();
      await show(tester);
      await fill(tester);
      await tap(tester, 'Create job', settle: false);
      await tester.pageBack();
      await tester.pumpAndSettle();
      account.postGate!.complete(account.receipt);
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect(find.byType(CloudTaskPage), findsNothing);
      expect(account.refreshes, 0);
      expect(account.saved, isNotEmpty);
    },
  );
  testWidgets(
    'create from profile returns from result to original profile detail',
    (tester) async {
      await show(
        tester,
        page: const CloudProfileDetailPage(profile: printerProfile),
      );
      await tap(tester, 'Create task with this profile');
      await tester.enterText(find.byType(TextFormField).first, 'Valve bracket');
      await tap(tester, 'Create job');
      expect(find.byType(CloudTaskPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Create task with this profile'), findsOneWidget);
      expect(find.byType(CloudCreateTaskPage), findsNothing);
      expect(account.writes, 1);
    },
  );
  testWidgets(
    'create from checklist returns from result to selected checklist',
    (tester) async {
      await show(
        tester,
        page: const CloudTemplateDetailPage(
          template: {
            'id': 7,
            'name': 'Assembly',
            'version': 2,
            'built_in': true,
            'items': [],
          },
        ),
      );
      await tap(tester, 'Create task with this checklist');
      await fill(tester);
      await tap(tester, 'Create job');
      expect(account.submitted?['template_id'], 7);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Create task with this checklist'), findsOneWidget);
      expect(find.byType(CloudCreateTaskPage), findsNothing);
    },
  );
  for (final language in ['zh', 'en']) {
    testWidgets('$language confirmed task navigation PNG', (tester) async {
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
      await show(tester, language: language);
      await fill(tester);
      await tap(tester, language == 'zh' ? '创建任务' : 'Create job');
      await tester.binding.setSurfaceSize(const Size(360, 1100));
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold).last,
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/ui80-batch/create-navigation-batch/png/290-created-task-$language-component.png',
        ),
      );
    });
  }
}

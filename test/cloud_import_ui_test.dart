import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_feedback.dart';
import 'package:linesight_flutter/cloud_local_import.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_local_import_test.dart' show record;

class LocalImportStore extends AppStore {
  Completer<void>? loginGate;
  Object? loginFailure;
  int captures = 0;
  LocalImportStore({bool authorized = true}) {
    ready = true;
    preferences = {'reduceMotion': true, 'glass': false};
    if (authorized) user = engineerUser;
    data.inspections.addAll([
      record('REAL-01'),
      record('SAMPLE-01', sample: true),
    ]);
  }
  static const engineerUser = LocalUser(
    'e',
    'engineer',
    'Engineer',
    'engineer',
    true,
  );
  @override
  Future<void> login(String username, String password) async {
    await loginGate?.future;
    if (loginFailure != null) throw loginFailure!;
    user = engineerUser;
    session++;
    notifyListeners();
  }

  @override
  List<Inspection> captureTeamImport() {
    captures++;
    return super.captureTeamImport();
  }
}

class ImportUiAccount extends CloudAccount {
  int posts = 0, gets = 0;
  final sent = <Map>[];
  final seen = <String>{};
  Completer<dynamic>? historyGate;
  Completer<void>? postGate;
  Object? historyFailure;
  ImportUiAccount() {
    restoring = false;
    profile = {'id': 'import-user'};
    activeWorkspace = {
      'id': 5,
      'name': 'DEMO · Import team',
      'role': 'operator',
    };
  }
  @override
  bool get signedIn => true;
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'GET') {
      gets++;
      if (historyGate != null) return historyGate!.future;
      if (historyFailure != null) throw historyFailure!;
      return {
        'count': seen.length,
        'records': [
          for (final id in seen)
            {
              'id': id,
              'recipe': 'Imported part',
              'serial': id,
              'at': '2026-10-23',
              'passed': true,
              'sample': id.startsWith('SAMPLE'),
            },
        ],
      };
    }
    posts++;
    await postGate?.future;
    final data = body as Map;
    sent.add(data);
    var imported = 0, skipped = 0;
    for (final row in data['records'] as List) {
      if (seen.add('${row['id']}')) {
        imported++;
      } else {
        skipped++;
      }
    }
    return {'imported': imported, 'skipped': skipped};
  }
}

void main() {
  late LocalImportStore local;
  late ImportUiAccount cloud;
  setUp(() {
    local = LocalImportStore();
    cloud = ImportUiAccount();
  });
  tearDown(() {
    local.dispose();
    cloud.dispose();
  });
  Future<void> show(WidgetTester tester, {String language = 'zh'}) async {
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
          store: local,
          child: CloudScope(account: cloud, child: child!),
        ),
        home: const CloudLocalImportPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, {String language = 'zh'}) async {
    await tester.tap(
      find.text(language == 'zh' ? '授权并预览' : 'Authorize and preview'),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, {String language = 'zh'}) async {
    await tester.tap(find.text(language == 'zh' ? '确认导入' : 'Confirm import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(language == 'zh' ? '确认' : 'Confirm'));
    await tester.pumpAndSettle();
  }

  testWidgets('cloud login alone exposes no local count or records', (
    tester,
  ) async {
    local.user = null;
    await show(tester);
    expect(local.captures, 0);
    expect(find.textContaining('REAL-01'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(cloud.posts, 0);
  });
  testWidgets('preview excludes samples and cancellation sends no import', (
    tester,
  ) async {
    await show(tester);
    await preview(tester);
    expect(find.textContaining('REAL-01'), findsOneWidget);
    expect(find.textContaining('SAMPLE-01'), findsNothing);
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(cloud.posts, 0);
    expect(find.textContaining('REAL-01'), findsOneWidget);
  });
  testWidgets('local lock immediately removes preview and successful history', (
    tester,
  ) async {
    await show(tester);
    await preview(tester);
    await submit(tester);
    expect(find.text('已导入 1 条，跳过 0 条'), findsOneWidget);
    local.lock();
    await tester.pumpAndSettle();
    expect(find.textContaining('REAL-01'), findsNothing);
    expect(find.text('已导入 1 条，跳过 0 条'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });
  testWidgets('history failure preserves import success; recovery only reads', (
    tester,
  ) async {
    cloud.historyFailure = const CollaborationApiException(503, 'secret-html');
    await show(tester);
    await preview(tester);
    await submit(tester);
    expect(find.text('已导入 1 条，跳过 0 条'), findsOneWidget);
    expect(find.byType(CloudFailurePanel), findsOneWidget);
    expect(find.textContaining('secret-html'), findsNothing);
    cloud.historyFailure = null;
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(cloud.posts, 1);
    expect(cloud.gets, 2);
    expect(find.text('团队历史记录'), findsOneWidget);
    expect(find.byType(CloudFailurePanel), findsNothing);
  });
  testWidgets('late history after team switch cannot show source records', (
    tester,
  ) async {
    cloud.historyGate = Completer<dynamic>();
    await show(tester);
    await preview(tester);
    await submit(tester);
    cloud.activeWorkspace = {'id': 6, 'name': 'Other team', 'role': 'owner'};
    cloud.notifyListeners();
    await tester.pumpAndSettle();
    cloud.historyGate!.complete({
      'count': 1,
      'records': [
        {'recipe': 'Secret old record', 'serial': 'HIDDEN', 'passed': true},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Secret old record'), findsNothing);
    expect(find.textContaining('REAL-01'), findsNothing);
    expect(find.text('已导入 1 条，跳过 0 条'), findsNothing);
  });
  testWidgets('team switch during local login prevents capturing records', (
    tester,
  ) async {
    local.user = null;
    local.loginGate = Completer<void>();
    await show(tester);
    await preview(tester);
    cloud.activeWorkspace = {'id': 6, 'name': 'Other team', 'role': 'owner'};
    cloud.notifyListeners();
    await tester.pumpAndSettle();
    local.loginGate!.complete();
    await tester.pumpAndSettle();
    expect(local.captures, 0);
    expect(cloud.posts, 0);
    expect(find.textContaining('REAL-01'), findsNothing);
  });
  testWidgets('unknown local authorization errors hide internal content', (
    tester,
  ) async {
    local.user = null;
    local.loginFailure = StateError('secret-db-path');
    await show(tester);
    await preview(tester);
    expect(find.textContaining('secret-db-path'), findsNothing);
    expect(find.text('操作未完成，请重试。'), findsOneWidget);
    expect(local.captures, 0);
  });
  testWidgets(
    'pending import disables repeat submission and hides late results after lock',
    (tester) async {
      cloud.postGate = Completer<void>();
      await show(tester);
      await preview(tester);
      await submit(tester);
      expect(cloud.posts, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认导入'))
            .onPressed,
        isNull,
      );
      local.lock();
      await tester.pumpAndSettle();
      cloud.postGate!.complete();
      await tester.pumpAndSettle();
      expect(cloud.posts, 1);
      expect(cloud.gets, 0);
      expect(find.text('已导入 1 条，跳过 0 条'), findsNothing);
      expect(find.textContaining('REAL-01'), findsNothing);
    },
  );
  test(
    'role or cloud identity changes invalidate an import preview before sending',
    () async {
      final plan = CloudImportPlan.capture(local, cloud);
      cloud.activeWorkspace = {...cloud.activeWorkspace!, 'role': 'owner'};
      await expectLater(
        plan.upload(),
        throwsA(isA<CollaborationApiException>()),
      );
      final second = CloudImportPlan.capture(local, cloud);
      cloud.profile = {'id': 'another-user'};
      await expectLater(
        second.upload(),
        throwsA(isA<CollaborationApiException>()),
      );
      expect(cloud.posts, 0);
    },
  );
  testWidgets('samples require opt in and remain labelled in cloud history', (
    tester,
  ) async {
    await show(tester);
    await preview(tester);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await submit(tester);
    expect(cloud.sent.single['include_samples'], true);
    expect(cloud.seen, {'REAL-01', 'SAMPLE-01'});
    expect(find.text('演示数据'), findsOneWidget);
  });

  for (final language in ['zh', 'en']) {
    for (final state in [
      'authorize',
      'preview',
      'success',
      'history-failure',
    ]) {
      testWidgets('$language import $state PNG', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
        if (state == 'authorize') local.user = null;
        if (state == 'history-failure') {
          cloud.historyFailure = const CollaborationApiException(
            503,
            'private',
          );
        }
        await show(tester, language: language);
        if (state != 'authorize') await preview(tester, language: language);
        if (state == 'success' || state == 'history-failure') {
          await submit(tester, language: language);
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/import-batch/png/150-local-import-$state-$language-desktop-render.png',
          ),
        );
      });
    }
  }
}

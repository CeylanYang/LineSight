import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

class TeamAccount extends AccessAccount {
  final calls = <({String method, String path, Object? body})>[];
  Completer<dynamic>? readGate;
  Object? readFailure, writeFailure;
  final rows = <Map<String, dynamic>>[
    {
      'id': 31,
      'username': 'oidc_self',
      'display_name': '林晓',
      'role': 'owner',
      'is_self': true,
    },
    {
      'id': 32,
      'username': 'oidc_other',
      'display_name': '陈晨',
      'role': 'owner',
      'is_self': false,
    },
    {
      'id': 33,
      'username': 'worker+test@example.com',
      'display_name': '王工',
      'role': 'operator',
      'is_self': false,
    },
  ];
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    calls.add((method: method, path: path, body: body));
    if (method == 'GET') {
      if (readGate != null) return readGate!.future;
      if (readFailure != null) throw readFailure!;
      return rows;
    }
    if (writeFailure != null) throw writeFailure!;
    if (path.endsWith('/invite/')) {
      return {
        'code': 'LS-TEAM-${calls.where((c) => c.method == 'POST').length}',
      };
    }
    return {};
  }

  @override
  Future<void> reload() async {}
  Iterable<({String method, String path, Object? body})> get mutations =>
      calls.where((c) => c.method != 'GET');
}

void main() {
  late TeamAccount account;
  late AppStore store;
  setUp(() {
    account = TeamAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false, 'haptic': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> show(
    WidgetTester tester, {
    String language = 'en',
    double textScale = 1,
    bool routed = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: 'EvidenceFont',
          colorScheme: appTheme(false).colorScheme,
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(
            account: account,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
        home: routed
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => openPage(context, const CloudTeamPage()),
                    child: const Text('Origin'),
                  ),
                ),
              )
            : const CloudTeamPage(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> chooseViewer(
    WidgetTester tester, {
    String language = 'en',
  }) async {
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.text(language == 'en' ? 'View only' : '只读成员').last);
  }

  Future<void> menu(WidgetTester tester, String name, String label) async {
    final tile = find.ancestor(
      of: find.text(name),
      matching: find.byType(ListTile),
    );
    await tap(
      tester,
      find.descendant(of: tile, matching: find.byType(PopupMenuButton<String>)),
    );
    await tap(tester, find.text(label).last);
  }

  testWidgets(
    'role selection is read-only; repeated generation retains selected role and clears old code',
    (tester) async {
      await show(tester);
      await chooseViewer(tester);
      expect(account.mutations, isEmpty);
      await tap(tester, find.text('Create invitation'));
      expect(account.mutations.single.body, {'role': 'viewer'});
      expect(find.text('LS-TEAM-1'), findsOneWidget);
      await tap(tester, find.text('Create invitation'));
      expect(account.mutations.last.body, {'role': 'viewer'});
      await tap(tester, find.byType(DropdownButtonFormField<String>));
      await tap(tester, find.text('Operator').last);
      expect(find.text('LS-TEAM-2'), findsNothing);
      expect(account.mutations.length, 2);
    },
  );
  testWidgets(
    'server self flag hides own menu and permits another owner menu',
    (tester) async {
      await show(tester);
      expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));
      final self = find.ancestor(
        of: find.text('林晓'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: self,
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );
      expect(find.text('oidc_self'), findsNothing);
      await menu(tester, '陈晨', 'View only');
      expect(account.mutations, isEmpty);
      await tap(tester, find.text('Confirm'));
      expect(account.mutations.single.path, 'workspaces/1/members/oidc_other/');
      expect(account.mutations.single.body, {'role': 'viewer'});
    },
  );
  testWidgets(
    'cancel removal makes no write and confirmed target is URI encoded',
    (tester) async {
      await show(tester);
      await menu(tester, '王工', 'Remove member');
      await tap(tester, find.text('Cancel'));
      expect(account.mutations, isEmpty);
      await menu(tester, '王工', 'Remove member');
      await tap(tester, find.text('Confirm'));
      expect(account.mutations.single.method, 'DELETE');
      expect(
        account.mutations.single.path,
        'workspaces/1/members/worker%2Btest%40example.com/',
      );
    },
  );
  testWidgets(
    'switching team while confirmation is open cannot write to either team',
    (tester) async {
      await show(tester);
      await menu(tester, '王工', 'Remove member');
      account.activeWorkspace = {
        'id': 2,
        'role': 'owner',
        'name': 'Other team',
        'kind': 'team',
      };
      account.notifyListeners();
      await tester.pump();
      await tap(tester, find.text('Confirm'));
      expect(account.mutations, isEmpty);
    },
  );
  testWidgets(
    'pending and failed reads do not assert zero members; retry is GET only',
    (tester) async {
      account.readGate = Completer();
      await show(tester);
      expect(find.textContaining('0 members'), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      account.readGate!.completeError(StateError('private transport host'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private transport host'), findsNothing);
      expect(find.textContaining('0 members'), findsNothing);
      account.readGate = null;
      await tap(tester, find.text('Retry'));
      expect(find.text('林晓'), findsOneWidget);
      expect(account.mutations, isEmpty);
    },
  );
  testWidgets(
    'failed mutation recovery reads members without replaying write',
    (tester) async {
      await show(tester);
      account.writeFailure = const CollaborationApiException(503, 'private');
      await tap(tester, find.text('Create invitation'));
      expect(account.mutations.length, 1);
      await tester.drag(find.byType(ListView).first, const Offset(0, 900));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Retry'));
      expect(account.mutations.length, 1);
      expect(account.calls.last.method, 'GET');
    },
  );
  for (final title in ['Create team', 'Join team']) {
    testWidgets(
      'identity change while $title prompt is open prevents submission',
      (tester) async {
        await show(tester);
        await tap(tester, find.text(title));
        await tester.enterText(find.byType(TextField), 'draft');
        account.profile = {'id': 'other-person', 'username': 'other'};
        account.notifyListeners();
        await tester.pump();
        await tap(tester, find.text('Confirm'));
        expect(account.mutations, isEmpty);
      },
    );
  }
  testWidgets('viewer role has no member management or invitation controls', (
    tester,
  ) async {
    account.activeWorkspace!['role'] = 'viewer';
    await show(tester);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Create invitation'), findsNothing);
  });
  for (final fails in [true, false]) {
    testWidgets(
      'leave team returns to origin only after success: failure=$fails',
      (tester) async {
        await show(tester, routed: true);
        await tap(tester, find.text('Origin'));
        if (fails) {
          account.writeFailure = const CollaborationApiException(
            409,
            '任务已更新，请刷新后重试',
          );
        }
        await tester.scrollUntilVisible(find.text('Leave team'), 300);
        await tap(tester, find.text('Leave team'));
        await tap(tester, find.text('Confirm'));
        expect(account.mutations.single.path, 'workspaces/1/leave/');
        expect(
          find.byType(CloudTeamPage),
          fails ? findsOneWidget : findsNothing,
        );
        if (!fails) expect(find.text('Origin'), findsOneWidget);
      },
    );
  }
  for (final language in ['zh', 'en']) {
    for (final state in ['ready', 'invitation', 'failure', 'pending']) {
      testWidgets('$language team $state component PNG', (tester) async {
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
        if (state == 'failure') {
          account.readFailure = const CollaborationApiException(503, 'private');
        }
        if (state == 'pending') account.readGate = Completer();
        await show(tester, language: language);
        if (state != 'pending') await tester.pumpAndSettle();
        if (state == 'invitation') {
          await chooseViewer(tester, language: language);
          await tap(
            tester,
            find.text(language == 'en' ? 'Create invitation' : '生成邀请码'),
          );
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/team-batch/png/170-team-$state-$language-desktop-render.png',
          ),
        );
        if (state == 'pending') {
          account.readGate!.complete(account.rows);
          await tester.pumpAndSettle();
        }
      });
    }
    testWidgets('$language team small large-text layout', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await show(tester, language: language, textScale: 1.6);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

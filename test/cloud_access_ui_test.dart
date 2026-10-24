import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class AccessAccount extends CloudAccount {
  final pending = <int, Completer<List<Map<String, dynamic>>>>{};
  int writes = 0;
  bool passwordAction = false;
  Completer<List<int>>? photo;
  @override
  bool get signedIn => true;
  AccessAccount() {
    restoring = false;
    workspaceDataLoaded = true;
    profile = {
      'id': 'user-a',
      'display_name': 'Quality Engineer',
      'username': 'quality.engineer',
    };
    activeWorkspace = {
      'id': 1,
      'role': 'owner',
      'name': 'Quality team',
      'kind': 'team',
    };
  }
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method != 'GET') {
      writes++;
      return {};
    }
    if (path.endsWith('members/')) {
      final id = int.parse(path.split('/')[1]);
      if (pending.containsKey(id)) return pending[id]!.future;
      return [
        {
          'id': 10,
          'display_name': 'Quality Engineer',
          'username': 'quality.engineer',
          'role': 'owner',
        },
      ];
    }
    return [];
  }

  @override
  Future<List<int>> download(String path) async => photo!.future;
  @override
  Future<void> signIn({bool demo = false, bool changePassword = false}) async {
    passwordAction = changePassword;
  }
}

void main() {
  late AccessAccount account;
  late AppStore store;
  setUp(() {
    account = AccessAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'haptic': false, 'glass': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> show(
    WidgetTester tester,
    Widget page, {
    String locale = 'en',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(fontFamily: 'EvidenceFont'),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: page,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'profile replaces the old identity draft and password uses hosted action',
    (tester) async {
      await show(tester, const CloudProfilePage());
      await tester.enterText(find.byType(TextField), 'Old draft name');
      account.profile = {
        'id': 'user-b',
        'display_name': 'New colleague',
        'username': 'colleague',
      };
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'New colleague',
      );
      expect(find.text('Old draft name'), findsNothing);
      await tester.ensureVisible(find.text('Change password'));
      await tester.tap(find.text('Change password'));
      expect(account.passwordAction, isTrue);
      expect(account.writes, 0);
    },
  );

  for (final team in [false, true]) {
    testWidgets(
      'late member response cannot cross team switch: management=$team',
      (tester) async {
        account.pending[1] = Completer();
        account.pending[2] = Completer();
        await show(
          tester,
          team ? const CloudTeamPage() : const CloudMembersPage(),
        );
        account.activeWorkspace = {
          'id': 2,
          'role': 'viewer',
          'name': 'Second team',
          'kind': 'team',
        };
        account.notifyListeners();
        await tester.pump();
        account.pending[2]!.complete([
          {'id': 22, 'display_name': 'Second team member', 'role': 'viewer'},
        ]);
        await tester.pumpAndSettle();
        account.pending[1]!.complete([
          {'id': 11, 'display_name': 'Old team secret', 'role': 'owner'},
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Second team member'), findsOneWidget);
        expect(find.text('Old team secret'), findsNothing);
        expect(find.text('Generate invitation'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an old template callback cannot publish into a different team', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, const CloudTemplateEditor());
    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton).last,
    );
    expect(button.onPressed, isNotNull);
    account.activeWorkspace = {'id': 2, 'role': 'owner'};
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(account.writes, 0);
    expect(find.text('Workspace changed'), findsOneWidget);
  });

  testWidgets(
    'a transition form without a draft is bound to its original team',
    (tester) async {
      await show(
        tester,
        const CloudTaskCommandPage(
          workspaceId: 1,
          action: 'printing',
          job: {
            'id': 'task-a',
            'quantity': 1,
            'part_name': 'Bracket',
            'status': 'queued',
            'version': 1,
          },
        ),
      );
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Workspace changed'), findsOneWidget);
      expect(find.text('Confirm submission'), findsNothing);
      expect(account.writes, 0);
    },
  );

  testWidgets('late image bytes cannot appear after switching teams', (
    tester,
  ) async {
    account.photo = Completer();
    await show(
      tester,
      const CloudEvidencePage(jobId: 'task-a', photo: {'id': 8}),
    );
    account.activeWorkspace = {'id': 2, 'role': 'viewer'};
    account.notifyListeners();
    await tester.pump();
    account.photo!.complete([1, 2, 3]);
    await tester.pumpAndSettle();
    expect(find.text('Workspace changed'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['zh', 'en']) {
    testWidgets(
      'account and viewer team $locale fit 360px and provide PNG evidence',
      (tester) async {
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
        await show(tester, const CloudProfilePage(), locale: locale);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/ui80-batch/closure-batch/png/77-account-$locale-desktop-render.png',
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        account.activeWorkspace = {
          'id': 1,
          'role': 'viewer',
          'name': 'Quality team',
          'kind': 'team',
        };
        await show(tester, const CloudTeamPage(), locale: locale);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.vpn_key_outlined), findsNothing);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/ui80-batch/team-batch/png/172-viewer-team-$locale-desktop-render.png',
          ),
        );
      },
    );
  }
}

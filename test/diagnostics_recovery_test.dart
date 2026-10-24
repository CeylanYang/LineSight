import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_sync_diagnostics.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/screens/dashboard.dart';
import 'package:linesight_flutter/models.dart';
import 'cloud_navigation_test.dart' show chooseTab;
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_task_ui_test.dart' show DraftTaskAccount;

class DiagnosticAccount extends DraftTaskAccount {
  Object? failure;
  bool localFailure = false;
  int refreshes = 0;
  final reads = <String>[];
  Completer<dynamic>? pending;
  Completer<Map<String, dynamic>?>? localPending;
  DiagnosticAccount() {
    workspaceDataLoaded = true;
    activeWorkspace = {'id': 1, 'role': 'owner', 'name': 'Quality team'};
  }
  @override
  Future<Map<String, dynamic>?> readDraft(String key) async {
    if (localFailure) throw StateError('private local path secret-marker');
    if (localPending != null) return localPending!.future;
    return {
      'items': [
        {'state': 'uploaded'},
        {'state': 'failed'},
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listDrafts() async => [
    {'note': 'private draft secret-marker'},
  ];
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    expect(method, 'GET');
    reads.add(path);
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return {};
  }

  @override
  Future<void> reload() async {
    refreshes++;
  }
}

DateTime fixedNow() => DateTime.utc(2026, 10, 24, 4);
void main() {
  late DiagnosticAccount account;
  late AppStore store;
  String? copied;
  setUp(() {
    account = DiagnosticAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'haptic': false, 'glass': false};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    account.dispose();
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  Future<void> show(
    WidgetTester tester, {
    String language = 'en',
    Widget? page,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 1100));
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
          textButtonTheme: const TextButtonThemeData(
            style: ButtonStyle(
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontFamily: 'EvidenceFont', fontSize: 14),
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
              onPressed: () => openPage(
                context,
                page ?? const CloudDiagnosticsPage(now: fixedNow),
              ),
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'diagnostics exports only approved fields and returns to origin',
    (tester) async {
      await show(tester);
      expect(account.reads, ['workspaces/1/metrics/']);
      await tap(tester, 'Copy diagnostics');
      final data = jsonDecode(copied!) as Map;
      expect(data.keys.toSet(), {
        'app_version',
        'platform',
        'checked_at',
        'workspace_id',
        'pending_photos',
        'acknowledged_photos',
        'drafts',
        'status',
        'local_storage',
      });
      expect(data['pending_photos'], 1);
      expect(data['acknowledged_photos'], 1);
      expect(data['drafts'], 1);
      expect(copied, isNot(contains('secret-marker')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
    },
  );
  testWidgets('service failure offers read-only retry and hides raw response', (
    tester,
  ) async {
    account.failure = const CollaborationApiException(
      503,
      'Bearer secret-marker <html>',
    );
    await show(tester);
    expect(find.text('Service temporarily unavailable'), findsOneWidget);
    expect(find.textContaining('secret-marker'), findsNothing);
    account.failure = null;
    await tap(tester, 'Retry');
    expect(account.reads.length, 2);
    expect(find.text('Service temporarily unavailable'), findsNothing);
  });
  testWidgets('forbidden refreshes permissions without invoking login', (
    tester,
  ) async {
    account.failure = const CollaborationApiException(
      403,
      'private secret-marker',
    );
    await show(tester);
    await tap(tester, 'Refresh access');
    expect(account.refreshes, 1);
    expect(account.reads.length, 2);
    expect(find.text('Sign in'), findsNothing);
  });
  testWidgets(
    'unauthorized opens secondary login and back returns to diagnostics',
    (tester) async {
      account.failure = const CollaborationApiException(
        401,
        'private secret-marker',
      );
      await show(tester);
      await tap(tester, 'Sign in');
      expect(find.byType(CloudDiagnosticsPage), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CloudDiagnosticsPage), findsOneWidget);
    },
  );
  testWidgets(
    'local storage failure still checks cloud and reports unknown counts',
    (tester) async {
      account.localFailure = true;
      await show(tester);
      expect(account.reads.length, 1);
      expect(find.text('—'), findsNWidgets(3));
      await tap(tester, 'Copy diagnostics');
      final data = jsonDecode(copied!) as Map;
      expect(data['status'], 200);
      expect(data['local_storage'], 'unavailable');
      expect(data.containsKey('drafts'), false);
    },
  );
  testWidgets('no workspace never requests a null workspace path', (
    tester,
  ) async {
    account.activeWorkspace = null;
    await show(tester);
    expect(account.reads, isEmpty);
    expect(find.textContaining('null/metrics'), findsNothing);
  });
  testWidgets('late network result cannot overwrite the newly selected team', (
    tester,
  ) async {
    final gate = Completer<dynamic>();
    account.pending = gate;
    await show(tester, settle: false);
    account.activeWorkspace = {'id': 2, 'role': 'owner', 'name': 'Second team'};
    account.pending = null;
    account.notifyListeners();
    await tester.pumpAndSettle();
    gate.completeError(const CollaborationApiException(503, 'old response'));
    await tester.pumpAndSettle();
    expect(account.reads, ['workspaces/1/metrics/', 'workspaces/2/metrics/']);
    expect(find.text('Service temporarily unavailable'), findsNothing);
    await tap(tester, 'Copy diagnostics');
    expect((jsonDecode(copied!) as Map)['workspace_id'], 2);
  });
  testWidgets('late local read cannot send request for previous team', (
    tester,
  ) async {
    final gate = Completer<Map<String, dynamic>?>();
    account.localPending = gate;
    await show(tester, settle: false);
    account.activeWorkspace = {
      'id': 2,
      'role': 'viewer',
      'name': 'Second team',
    };
    account.localPending = null;
    account.notifyListeners();
    await tester.pumpAndSettle();
    gate.complete({'items': []});
    await tester.pumpAndSettle();
    expect(account.reads, ['workspaces/2/metrics/']);
  });
  testWidgets('cloud account exposes help and returns to same account tab', (
    tester,
  ) async {
    await show(tester, page: const CloudShell());
    await chooseTab(tester, 4);
    await tap(tester, 'Guide and app information');
    expect(find.byType(HelpPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Guide and app information'), findsOneWidget);
  });
  testWidgets('help describes cloud accounts and separate local data', (
    tester,
  ) async {
    await show(tester, page: const HelpPage(), language: 'zh');
    await tap(tester, '06  数据与隐私');
    expect(find.textContaining('团队账户、任务与检验记录由云端服务管理'), findsOneWidget);
    expect(find.textContaining('应用没有云账户'), findsNothing);
    await tap(tester, '05  登录与团队');
    expect(find.textContaining('普通用户与团队成员使用同一登录入口'), findsOneWidget);
  });
  testWidgets('local station labels synthetic record generation as examples', (
    tester,
  ) async {
    store.data = Workspace.seed();
    store.user = const LocalUser('a', 'admin', 'Operator', 'admin', true);
    await show(
      tester,
      page: const StationPage(id: 's1'),
      language: 'zh',
    );
    expect(find.text('添加示例记录'), findsOneWidget);
    expect(find.text('开始检测'), findsNothing);
  });
  for (final language in ['zh', 'en']) {
    for (final state in ['healthy', 'offline', 'help']) {
      testWidgets('$language $state diagnostics component PNG', (tester) async {
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
        if (state == 'offline') {
          account.failure = const CollaborationApiException(
            503,
            'private secret-marker',
          );
        }
        await show(
          tester,
          language: language,
          page: state == 'help' ? const HelpPage() : null,
        );
        if (state == 'help') {
          if (language == 'en') {
            expect(
              find.text(
                'Track inspection results, production tasks and quality reviews.',
              ),
              findsOneWidget,
            );
          }
          await tester.tap(
            find.text(
              language == 'zh' ? '01  任务与检验' : '01  Tasks and inspections',
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).last,
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/version-components/$appVersion/293-$state-$language-component.png',
          ),
        );
      });
    }
  }
}

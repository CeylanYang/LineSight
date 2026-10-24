import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_feedback.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

class FeedbackAccount extends AccessAccount {
  Object? failure;
  Completer<dynamic>? pendingRead;
  final reads = <String>[];
  int refreshes = 0;
  @override
  Future<void> reload() async {
    refreshes++;
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
    reads.add(path);
    if (failure != null) throw failure!;
    if (pendingRead != null) return pendingRead!.future;
    if (path.contains('metrics/')) return <String, dynamic>{};
    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<int>> download(String path) async {
    if (failure != null) throw failure!;
    return <int>[];
  }
}

void main() {
  late FeedbackAccount account;
  late AppStore store;
  setUp(() {
    account = FeedbackAccount();
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
        theme: ThemeData(
          fontFamily: 'EvidenceFont',
          colorScheme: appTheme(false).colorScheme,
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontFamily: 'EvidenceFont',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fonts() async {
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
  }

  testWidgets('task retry retains filters and failure is not an empty result', (
    tester,
  ) async {
    account.failure = const CollaborationApiException(
      503,
      'Internal server error: Bearer secret-marker',
    );
    await show(
      tester,
      const CloudTaskListPage(
        filters: {'q': 'BATCH-007', 'status': 'inspection'},
      ),
    );
    expect(find.byType(CloudFailurePanel), findsOneWidget);
    expect(find.text('No production tasks'), findsNothing);
    expect(find.textContaining('secret-marker'), findsNothing);
    expect(find.byType(CloudLoadingPanel), findsNothing);
    final initial = account.reads.single;
    account.failure = null;
    await tester.tap(
      find.descendant(
        of: find.byType(CloudFailurePanel),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(account.reads.last, initial);
    expect(initial, contains('q=BATCH-007'));
    expect(initial, contains('status=inspection'));
    expect(find.byType(CloudFailurePanel), findsNothing);
    expect(account.writes, 0);
  });

  testWidgets(
    '403 refreshes permissions without signing in or replaying a write',
    (tester) async {
      var retried = 0;
      await show(
        tester,
        Scaffold(
          body: CloudFailurePanel(
            failure: const CollaborationApiException(
              403,
              'Unknown backend access detail',
            ),
            onRetry: () async {
              retried++;
            },
          ),
        ),
      );
      await tester.tap(find.text('Refresh access'));
      await tester.pumpAndSettle();
      expect(account.refreshes, 1);
      expect(retried, 1);
      expect(find.byType(CloudLoginPage), findsNothing);
      expect(account.writes, 0);
    },
  );

  testWidgets('401 opens the unified secondary login without replaying work', (
    tester,
  ) async {
    var retried = 0;
    await show(
      tester,
      Scaffold(
        body: CloudFailurePanel(
          failure: const CollaborationApiException(401, 'expired'),
          onRetry: () async {
            retried++;
          },
        ),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(CloudFailurePanel),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CloudLoginPage), findsOneWidget);
    expect(retried, 0);
    expect(account.writes, 0);
  });

  testWidgets(
    '409 refreshes read state and unavailable report has no false zero cards',
    (tester) async {
      account.failure = const CollaborationApiException(
        409,
        'Task version conflict',
      );
      await show(tester, const CloudReportPage(filters: {'q': 'task-7'}));
      expect(find.byType(CloudFailurePanel), findsOneWidget);
      expect(find.byType(StatCard), findsNothing);
      final initial = account.reads.single;
      account.failure = null;
      await tester.tap(find.text('Refresh current status'));
      await tester.pumpAndSettle();
      expect(account.reads.last, initial);
      expect(find.byType(StatCard), findsWidgets);
      expect(account.writes, 0);
    },
  );

  testWidgets(
    'loading records uses a stable skeleton and does not claim emptiness',
    (tester) async {
      account.pendingRead = Completer();
      await show(tester, const Scaffold(body: CloudRecordsPage()));
      expect(find.byType(CloudLoadingPanel), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      account.pendingRead!.complete(<Map<String, dynamic>>[]);
      await tester.pumpAndSettle();
      expect(find.byType(CloudLoadingPanel), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
    },
  );

  testWidgets(
    'record and photo failures provide recovery without raw exceptions',
    (tester) async {
      account.failure = const CollaborationApiException(
        404,
        'private internal path marker',
      );
      await show(tester, const Scaffold(body: CloudRecordsPage()));
      expect(find.byType(CloudFailurePanel), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      await show(
        tester,
        const CloudEvidencePage(jobId: 'task-a', photo: {'id': 1}),
      );
      expect(find.text('Record unavailable'), findsOneWidget);
      expect(find.textContaining('private internal'), findsNothing);
      expect(find.byType(Image), findsNothing);
    },
  );

  for (final locale in ['zh', 'en']) {
    testWidgets('recovery states $locale fit 360px and save desktop PNGs', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await fonts();
      await show(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const CloudLoadingPanel(),
                  for (final status in [0, 401, 403, 404, 409, 503])
                    CloudFailurePanel(
                      failure: CollaborationApiException(
                        status,
                        'raw-backend-marker',
                      ),
                      onRetry: () async {},
                    ),
                ],
              ),
            ),
          ),
        ),
        locale: locale,
      );
      expect(find.textContaining('raw-backend-marker'), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/ui80-batch/feedback-batch/png/66-recovery-states-$locale-desktop-render.png',
        ),
      );
      account.failure = const CollaborationApiException(0, '网络连接失败，请重试');
      account.activeWorkspace = {...account.activeWorkspace!, 'role': 'viewer'};
      await show(
        tester,
        const CloudTaskListPage(
          filters: {'q': 'BATCH-007', 'status': 'inspection'},
        ),
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/ui80-batch/conflict-batch/png/100-task-retry-$locale-desktop-render.png',
        ),
      );
    });
  }
}

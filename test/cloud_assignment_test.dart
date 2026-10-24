import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_history.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_assignment.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_task_ui_test.dart' show DraftTaskAccount;

class AssignmentAccount extends DraftTaskAccount {
  final posts = <({Map<String, dynamic> body, String? key})>[];
  List<Map<String, dynamic>> members = [
    {'id': 1, 'display_name': 'Alice', 'role': 'owner'},
    {'id': 2, 'display_name': 'Bob', 'role': 'operator'},
    {'id': 3, 'display_name': 'Carol', 'role': 'viewer'},
    {'id': 4, 'display_name': 'Dormant', 'role': 'operator', 'active': false},
  ];
  final job = <String, dynamic>{
    'id': 'task-42',
    'version': 4,
    'part_name': 'Valve bracket',
    'printer': 'A1',
    'quantity': 3,
    'status': 'inspection',
    'assignee_id': 1,
    'assignee': 'Alice',
    'created_at': '2026-10-24T00:00:00Z',
    'inspections': [],
    'exceptions': [],
    'evidence': [],
  };
  Object? readFailure, writeFailure;
  Completer<Map<String, dynamic>>? postGate;
  bool staleReads = false;
  int refreshes = 0;
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'GET') {
      if (path.endsWith('/members/')) {
        if (readFailure != null) throw readFailure!;
        return members;
      }
      if (path.endsWith('/history/')) return [];
      return staleReads
          ? {...job, 'version': 4, 'assignee_id': 1, 'assignee': 'Alice'}
          : job;
    }
    final payload = Map<String, dynamic>.from(body as Map);
    posts.add((body: payload, key: idempotencyKey));
    if (writeFailure != null) throw writeFailure!;
    if (postGate != null) return postGate!.future;
    job.addAll({
      'version': (payload['version'] as int) + 1,
      'assignee_id': payload['assignee_id'],
      'assignee': payload['assignee_id'] == null
          ? ''
          : members.firstWhere(
              (m) => m['id'] == payload['assignee_id'],
            )['display_name'],
    });
    return Map<String, dynamic>.from(job);
  }

  @override
  Future<void> reload() async {
    refreshes++;
  }
}

void main() {
  late AssignmentAccount account;
  late AppStore store;
  setUp(() {
    account = AssignmentAccount();
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
    Widget? page,
    String language = 'en',
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
                page ?? CloudAssignmentPage(job: account.job, workspaceId: 1),
              ),
              child: const Text('Origin'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Origin'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
    'only active writers are eligible; save returns confirmed version to detail despite stale GET',
    (tester) async {
      account.staleReads = true;
      await show(tester, page: CloudTaskPage(job: account.job, workspaceId: 1));
      await tester.tap(find.byTooltip('Change assignee'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(find.text('Carol'), findsNothing);
      expect(find.text('Dormant'), findsNothing);
      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();
      await tap(tester, 'Confirm assignee');
      expect(find.byType(CloudAssignmentPage), findsNothing);
      expect(find.byType(CloudTaskPage), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(account.posts.single.body, {
        'version': 4,
        'assignee_id': 2,
        'note': '',
      });
      expect(account.refreshes, 1);
    },
  );
  testWidgets(
    'exception handoff requires note and sends explicit nullable assignee',
    (tester) async {
      account.job['status'] = 'exception';
      await show(tester);
      await choose(tester, 'Unassigned');
      await tap(tester, 'Confirm assignee');
      expect(find.text('Enter a handover note'), findsOneWidget);
      expect(account.posts, isEmpty);
      await tester.enterText(
        find.byType(TextFormField),
        'Continue crack repair',
      );
      await tap(tester, 'Confirm assignee');
      expect(account.posts.single.body, {
        'version': 4,
        'assignee_id': null,
        'note': 'Continue crack repair',
      });
      expect(find.text('Origin'), findsOneWidget);
    },
  );
  testWidgets(
    'read retry never writes and manual save reuses key for unchanged failed payload',
    (tester) async {
      account.writeFailure = const CollaborationApiException(
        503,
        '服务暂不可用，请稍后重试',
      );
      await show(tester);
      await choose(tester, 'Bob');
      await tap(tester, 'Confirm assignee');
      final first = account.posts.single;
      await tap(tester, 'Retry');
      expect(account.posts.length, 1);
      account.writeFailure = null;
      await tap(tester, 'Confirm assignee');
      expect(account.posts.length, 2);
      expect(account.posts.last.key, first.key);
      expect(account.posts.last.body, first.body);
    },
  );
  testWidgets(
    'conflict requires review and manual resubmit with latest version and a new key',
    (tester) async {
      account.writeFailure = CollaborationApiException(
        409,
        '任务已更新，请刷新后重试',
        details: {
          'code': 'version_conflict',
          'current': {...account.job, 'version': 5},
        },
      );
      await show(tester);
      await choose(tester, 'Bob');
      await tap(tester, 'Confirm assignee');
      final first = account.posts.single;
      expect(
        find.text('Task updated; review the latest version'),
        findsOneWidget,
      );
      await tap(tester, 'Continue with latest task');
      expect(account.posts.length, 1);
      account.writeFailure = null;
      await tap(tester, 'Confirm assignee');
      expect(account.posts.last.body['version'], 5);
      expect(account.posts.last.key, isNot(first.key));
    },
  );
  testWidgets(
    'dirty back confirmation cancellation retains selection and discard does not write',
    (tester) async {
      await show(tester);
      await choose(tester, 'Bob');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Assignee changes are not saved.'), findsOneWidget);
      await tap(tester, 'Cancel');
      expect(find.text('Bob'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, 'Discard and go back');
      expect(find.text('Origin'), findsOneWidget);
      expect(account.posts, isEmpty);
    },
  );
  testWidgets('scope change hides form and ignores late successful save', (
    tester,
  ) async {
    account.postGate = Completer<Map<String, dynamic>>();
    await show(tester);
    await choose(tester, 'Bob');
    await tap(tester, 'Confirm assignee', settle: false);
    account.activeWorkspace = {'id': 2, 'role': 'owner'};
    account.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsNothing);
    account.postGate!.complete({
      ...account.job,
      'version': 5,
      'assignee_id': 2,
      'assignee': 'Bob',
    });
    await tester.pumpAndSettle();
    expect(find.text('Origin'), findsNothing);
    expect(find.text('Bob'), findsNothing);
    expect(account.refreshes, 0);
  });
  testWidgets('viewer and closed task have no assignment action', (
    tester,
  ) async {
    account.activeWorkspace = {'id': 1, 'role': 'viewer'};
    await show(tester, page: CloudTaskPage(job: account.job, workspaceId: 1));
    expect(find.byTooltip('Change assignee'), findsNothing);
    account.activeWorkspace = {'id': 1, 'role': 'owner'};
    account.job['status'] = 'closed';
    account.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Change assignee'), findsNothing);
    expect(account.posts, isEmpty);
  });
  testWidgets(
    'empty and failed member catalogs show recoverable states without writes',
    (tester) async {
      account.members = [];
      await show(tester);
      expect(find.text('No available assignees'), findsOneWidget);
      expect(account.posts, isEmpty);
      account.readFailure = const CollaborationApiException(
        503,
        '服务暂不可用，请稍后重试',
      );
      await tap(tester, 'Refresh');
      expect(find.text('Retry'), findsOneWidget);
      expect(account.posts, isEmpty);
    },
  );
  for (final language in ['zh', 'en']) {
    for (final state in ['form', 'handoff', 'conflict', 'history']) {
      testWidgets('$language assignment $state PNG', (tester) async {
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
        if (state == 'handoff') account.job['status'] = 'exception';
        if (state == 'conflict') {
          account.writeFailure = CollaborationApiException(
            409,
            '任务已更新，请刷新后重试',
            details: {
              'code': 'version_conflict',
              'current': {
                ...account.job,
                'version': 5,
                'assignee': 'Bob',
                'assignee_id': 2,
              },
            },
          );
        }
        await show(
          tester,
          language: language,
          page: state == 'history'
              ? const DetailScaffold(
                  title: 'Valve bracket',
                  children: [
                    CloudHistoryEvent(
                      event: {
                        'action': 'job.assigned',
                        'actor': 'Alice',
                        'object_id': 'task-42',
                        'version': 5,
                        'created_at': '2026-10-24T00:00:00Z',
                        'details': {
                          'previous_assignee': 'Alice',
                          'assignee': 'Bob',
                          'note': 'Continue crack repair',
                        },
                      },
                    ),
                  ],
                )
              : null,
        );
        if (state != 'history') {
          await choose(tester, 'Bob');
          if (state == 'handoff') {
            await tester.enterText(
              find.byType(TextFormField),
              'Continue crack repair',
            );
          }
          if (state == 'conflict') {
            await tap(
              tester,
              language == 'zh' ? '确认更改负责人' : 'Confirm assignee',
            );
          }
        } else {
          await tester.tap(find.byType(ExpansionTile));
          await tester.pumpAndSettle();
        }
        await tester.binding.setSurfaceSize(const Size(360, 1100));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).last,
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/assignment-batch/png/291-assignment-$state-$language-component.png',
          ),
        );
      });
    }
  }
}

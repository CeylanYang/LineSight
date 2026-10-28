import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_notifications.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

class SyncAccount extends AccessAccount {
  Completer<void>? gate;
  bool fail = false;
  int calls = 0;
  String? malformedEndpoint;
  List<Map<String, dynamic>> templateRows = [
    {
      'id': 3,
      'name': 'Remote checklist',
      'items': [
        {'label': 'Remote checkpoint'},
      ],
    },
  ];
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('offline');
    if (malformedEndpoint != null && path.endsWith(malformedEndpoint!)) {
      return malformedEndpoint == 'metrics/' ? <dynamic>[] : {'invalid': true};
    }
    if (path.endsWith('templates/')) return templateRows;
    if (path.endsWith('metrics/')) return {'total': 2};
    if (path.endsWith('notifications/')) {
      return [
        {
          'id': 'bulletin-1',
          'task_id': 'bulletin-1',
          'version': 1,
          'bulletin': true,
          'kind': 'notice',
          'part_name': '班前点检安排',
          'body': '2号工位抽检 6 件，核对批次。',
          'read': false,
          'updated_at': '2026-10-25T09:00:00+08:00',
        },
      ];
    }
    return [
      {'id': 2, 'part_name': '云端任务'},
    ];
  }
}

void main() {
  Future<void> openBulletin(WidgetTester t, SyncAccount a) async {
    final store = AppStore();
    addTearDown(store.dispose);
    addTearDown(a.dispose);
    await a.syncWorkspace();
    a.templates = [
      {
        'id': 3,
        'name': 'Private checklist',
        'items': [
          {'label': 'Private checkpoint'},
        ],
      },
    ];
    a.notifications.first['template_id'] = 3;
    await t.pumpWidget(
      AppScope(
        store: store,
        child: CloudScope(
          account: a,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      openCloudNotification(context, a.notifications.first),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  testWidgets('bulletin read waits once then disables completed action', (
    t,
  ) async {
    final a = SyncAccount();
    await openBulletin(t, a);
    a.gate = Completer<void>();
    final button = find.widgetWithText(TextButton, 'Mark read');
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pump();
    expect(t.widget<TextButton>(button).onPressed, isNull);
    expect(a.calls, 6);
    a.gate!.complete();
    await t.pumpAndSettle();
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, 'Read')).onPressed,
      isNull,
    );
    expect(find.text('Marked as read'), findsOneWidget);
    expect(a.calls, 7);
  });

  testWidgets('bulletin read failure stays actionable and can retry', (
    t,
  ) async {
    final a = SyncAccount();
    await openBulletin(t, a);
    a.fail = true;
    final button = find.widgetWithText(TextButton, 'Mark read');
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.text('Sync failed. Please retry.'), findsOneWidget);
    expect(t.widget<TextButton>(button).onPressed, isNotNull);
    a.fail = false;
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Read'), findsOneWidget);
  });

  testWidgets('open checklist hides content when workspace changes', (t) async {
    final a = SyncAccount();
    await openBulletin(t, a);
    await t.tap(find.text('View checklist'));
    await t.pumpAndSettle();
    expect(find.text('Private checkpoint'), findsOneWidget);
    a.activeWorkspace = {...a.activeWorkspace!, 'id': 2};
    a.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('Private checkpoint'), findsNothing);
    expect(find.text('Private checklist'), findsNothing);
    Navigator.of(t.element(find.text('Workspace changed').last)).pop();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('uncached bulletin checklist loads in place; failure can retry', (
    t,
  ) async {
    final a = SyncAccount();
    await openBulletin(t, a);
    a.templates = [];
    a.fail = true;
    await t.tap(find.text('View checklist'));
    await t.pumpAndSettle();
    expect(
      find.text('Unable to load checklist. Please retry.'),
      findsOneWidget,
    );
    expect(find.text('Remote checkpoint'), findsNothing);
    a.fail = false;
    await t.tap(find.text('View checklist'));
    await t.pumpAndSettle();
    expect(find.text('Remote checkpoint'), findsOneWidget);
    expect(a.calls, 7);
  });

  testWidgets(
    'unavailable checklist remains on bulletin and reports next action',
    (t) async {
      final a = SyncAccount();
      await openBulletin(t, a);
      a.templates = [];
      a.templateRows = [];
      await t.tap(find.text('View checklist'));
      await t.pumpAndSettle();
      expect(
        find.text('This checklist is unavailable. Contact your team admin.'),
        findsOneWidget,
      );
      expect(find.byType(CloudBulletinPage), findsOneWidget);
    },
  );

  testWidgets('late checklist fetch cannot open after workspace change', (
    t,
  ) async {
    final a = SyncAccount();
    await openBulletin(t, a);
    a.templates = [];
    a.gate = Completer<void>();
    await t.tap(find.text('View checklist'));
    await t.pump();
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'View checklist'),
          )
          .onPressed,
      isNull,
    );
    a.activeWorkspace = {...a.activeWorkspace!, 'id': 2};
    a.notifyListeners();
    a.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Remote checkpoint'), findsNothing);
    expect(find.text('Workspace changed'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('silent sync coalesces and applies complete cloud snapshot', () async {
    final a = SyncAccount();
    addTearDown(a.dispose);
    a.jobs = [
      {'id': 1},
    ];
    a.gate = Completer<void>();
    final first = a.syncWorkspace(), second = a.syncWorkspace();
    expect(identical(first, second), true);
    expect(a.jobs.first['id'], 1);
    a.gate!.complete();
    await first;
    expect(a.calls, 5);
    expect(a.jobs.first['id'], 2);
    expect(a.notifications.first['bulletin'], true);
    expect(a.workspaceDataReady, true);
  });
  test('failed sync preserves all previous content', () async {
    final a = SyncAccount()
      ..fail = true
      ..jobs = [
        {'id': 1},
      ]
      ..templates = [
        {'id': 3},
      ];
    addTearDown(a.dispose);
    await a.syncWorkspace();
    expect(a.jobs.first['id'], 1);
    expect(a.templates.first['id'], 3);
    expect(a.error, isNull);
  });
  test('malformed snapshot keeps all old data and retries', () async {
    for (final endpoint in [
      'templates/',
      'records/',
      'metrics/',
      'notifications/',
    ]) {
      final a = SyncAccount()..malformedEndpoint = endpoint;
      addTearDown(a.dispose);
      a.jobs = [
        {'id': 'old-job'},
      ];
      a.templates = [
        {'id': 'old-template'},
      ];
      a.records = [
        {'id': 'old-record'},
      ];
      a.metrics = {'total': 99};
      a.notifications = [
        {'id': 'old-notice'},
      ];
      var changes = 0;
      a.addListener(() => changes++);
      await a.syncWorkspace();
      expect(a.jobs.single['id'], 'old-job', reason: endpoint);
      expect(a.templates.single['id'], 'old-template', reason: endpoint);
      expect(a.records.single['id'], 'old-record', reason: endpoint);
      expect(a.metrics['total'], 99, reason: endpoint);
      expect(a.notifications.single['id'], 'old-notice', reason: endpoint);
      expect(changes, 0);
      a.malformedEndpoint = null;
      await a.syncWorkspace();
      expect(a.jobs.single['id'], 2);
      expect(a.metrics['total'], 2);
      expect(changes, 1);
    }
  });
  test('workspace switch rejects an older in-flight snapshot', () async {
    final a = SyncAccount();
    addTearDown(a.dispose);
    a.gate = Completer<void>();
    final pending = a.syncWorkspace();
    a.activeWorkspace = {...a.activeWorkspace!, 'id': 2};
    a.jobs = [
      {'id': 'workspace-2'},
    ];
    a.gate!.complete();
    await pending;
    expect(a.jobs.first['id'], 'workspace-2');
  });
  testWidgets('announcement opens full cloud text without requesting a task', (
    t,
  ) async {
    final a = SyncAccount();
    final s = AppStore();
    addTearDown(a.dispose);
    addTearDown(s.dispose);
    await a.syncWorkspace();
    await t.pumpWidget(
      AppScope(
        store: s,
        child: CloudScope(
          account: a,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      openCloudNotification(context, a.notifications.first),
                  child: const Text('打开通知'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('打开通知'));
    await t.pumpAndSettle();
    expect(find.byType(CloudBulletinPage), findsOneWidget);
    expect(find.text('2号工位抽检 6 件，核对批次。'), findsOneWidget);
    expect(a.calls, 5);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('打开通知'), findsOneWidget);
  });
}

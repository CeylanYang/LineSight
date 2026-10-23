import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_feedback.dart';
import 'package:linesight_flutter/cloud_trace.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;
import 'cloud_trace_test.dart' show TraceAccount, taskId;

class NoticeAccount extends AccessAccount {
  final reads = <String>[];
  List<Map<String, dynamic>> serverRows = [];
  Completer<void>? postGate;
  Completer<dynamic>? taskGate;
  final getGates = <Completer<dynamic>>[];
  Object? postFailure;
  bool advanceWhileReading = false;
  int reloads = 0;
  NoticeAccount() {
    notifications = [notice()];
    serverRows = [notice()];
    jobs = [];
  }
  static Map<String, dynamic> notice({bool read = false, int version = 1}) => {
    'id': taskId,
    'task_id': taskId,
    'part_name': 'DEMO · Assigned bracket',
    'status': 'queued',
    'read': read,
    'version': version,
    'reinspection': false,
  };
  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'POST') {
      writes++;
      await postGate?.future;
      if (postFailure != null) throw postFailure!;
      serverRows = [
        notice(
          read: !advanceWhileReading,
          version: advanceWhileReading ? 2 : 1,
        ),
      ];
      return {'read': !advanceWhileReading, 'version': 1};
    }
    reads.add(path);
    if (path.endsWith('notifications/')) {
      if (getGates.isNotEmpty) return getGates.removeAt(0).future;
      return serverRows.map((row) => Map<String, dynamic>.from(row)).toList();
    }
    if (path.endsWith('history/')) return [];
    if (path.contains('/jobs/$taskId/')) {
      if (taskGate != null) return taskGate!.future;
      final fixture = TraceAccount();
      final row = Map<String, dynamic>.from(fixture.task)
        ..['part_name'] = 'DEMO · Assigned bracket';
      fixture.dispose();
      return row;
    }
    return [];
  }
}

void main() {
  late NoticeAccount account;
  late AppStore store;
  setUp(() {
    account = NoticeAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'haptic': false, 'glass': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> show(WidgetTester tester, {String locale = 'zh'}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(fontFamily: 'EvidenceFont'),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: const CloudNotificationsPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'duplicate marks share a request and refresh only notifications',
    () async {
      account.postGate = Completer<void>();
      final scope = account.accessScope!;
      final a = account.markNotificationRead(
        account.notifications.single,
        scope,
      );
      final b = account.markNotificationRead(
        account.notifications.single,
        scope,
      );
      expect(account.writes, 1);
      account.postGate!.complete();
      await Future.wait([a, b]);
      expect(account.notifications.single['read'], true);
      expect(account.reads, ['workspaces/1/notifications/']);
      expect(account.reloads, 0);
    },
  );
  test(
    'late read completion cannot refresh or populate another team',
    () async {
      account.postGate = Completer<void>();
      final old = account.markNotificationRead(
        account.notifications.single,
        account.accessScope!,
      );
      final result = expectLater(
        old,
        throwsA(
          isA<CollaborationApiException>().having(
            (e) => e.status,
            'status',
            403,
          ),
        ),
      );
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifications = [
        {'task_id': 'new-team'},
      ];
      account.postGate!.complete();
      await result;
      expect(account.reads, isEmpty);
      expect(account.notifications.single['task_id'], 'new-team');
    },
  );
  test('a slower notification refresh cannot undo newer read state', () async {
    final first = Completer<dynamic>(), second = Completer<dynamic>();
    account.getGates.addAll([first, second]);
    final scope = account.accessScope!;
    final a = account.reloadNotifications(scope),
        b = account.reloadNotifications(scope);
    second.complete([NoticeAccount.notice(read: true)]);
    await b;
    first.complete([NoticeAccount.notice()]);
    await a;
    expect(account.notifications.single['read'], true);
  });
  testWidgets(
    'notification opens missing cached task and back returns to notifications',
    (tester) async {
      await show(tester);
      expect(account.jobs, isEmpty);
      await tester.tap(find.text('DEMO · Assigned bracket'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskPage), findsOneWidget);
      expect(find.byType(CloudTracePage), findsOneWidget);
      expect(account.reads, contains('workspaces/1/jobs/$taskId/'));
      expect(account.writes, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CloudNotificationsPage), findsOneWidget);
      expect(find.text('标为已读'), findsOneWidget);
    },
  );
  testWidgets('mark read disables duplicate taps then updates the same page', (
    tester,
  ) async {
    account.postGate = Completer<void>();
    await show(tester);
    await tester.tap(find.text('标为已读'));
    await tester.pump();
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '正在加载'),
    );
    expect(button.onPressed, isNull);
    expect(account.writes, 1);
    account.postGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('标为已读'), findsNothing);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(account.reloads, 0);
    expect(find.byType(CloudNotificationsPage), findsOneWidget);
  });
  testWidgets(
    'a newer task version remains unread after marking an old notice',
    (tester) async {
      account.advanceWhileReading = true;
      await show(tester);
      await tester.tap(find.text('标为已读'));
      await tester.pumpAndSettle();
      expect(account.notifications.single['version'], 2);
      expect(account.notifications.single['read'], false);
      expect(find.text('标为已读'), findsOneWidget);
    },
  );
  testWidgets(
    'failed mark stays unread and recovery refresh never repeats the write',
    (tester) async {
      account.postFailure = const CollaborationApiException(
        503,
        'private-token-marker',
      );
      await show(tester);
      await tester.tap(find.text('标为已读'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudFailurePanel), findsOneWidget);
      expect(find.text('private-token-marker'), findsNothing);
      expect(account.notifications.single['read'], false);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(account.writes, 1);
      expect(account.reads, ['workspaces/1/notifications/']);
      expect(find.byType(CloudFailurePanel), findsNothing);
    },
  );
  testWidgets(
    'late notification task lookup cannot switch back to an old team',
    (tester) async {
      account.taskGate = Completer<dynamic>();
      await show(tester);
      await tester.tap(find.text('DEMO · Assigned bracket'));
      await tester.pump();
      account.activeWorkspace = {'id': 2, 'role': 'viewer'};
      account.notifyListeners();
      await tester.pump();
      account.taskGate!.complete({
        'id': taskId,
        'part_name': 'Old secret part',
      });
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskPage), findsNothing);
      expect(find.text('Old secret part'), findsNothing);
      expect(find.byType(CloudFailurePanel), findsOneWidget);
      expect(account.activeWorkspace!['id'], 2);
    },
  );
  for (final locale in ['zh', 'en']) {
    for (final state in ['unread', 'read', 'pending', 'failure']) {
      testWidgets('$locale notification $state PNG', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final font = FontLoader('EvidenceFont')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
              ),
            ),
          );
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        if (state == 'pending') account.postGate = Completer<void>();
        if (state == 'failure') {
          account.postFailure = const CollaborationApiException(
            503,
            'private-server-marker',
          );
        }
        await show(tester, locale: locale);
        if (state != 'unread') {
          await tester.tap(find.text(locale == 'zh' ? '标为已读' : 'Mark read'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/notification-batch/png/140-notification-$state-$locale-desktop-render.png',
          ),
        );
        if (account.postGate != null) {
          account.postGate!.complete();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

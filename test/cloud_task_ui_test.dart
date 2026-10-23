import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';

class TaskAccount extends CloudAccount {
  bool authenticated = true;
  @override
  bool get signedIn => authenticated;
  Map<String, dynamic>? submitted;
  String? submittedKey;
  bool conflict = false;
  final task = <String, dynamic>{
    'id': 'task-1',
    'version': 2,
    'status': 'inspection',
    'part_name': 'Bracket',
    'printer': 'A1',
    'quantity': 10,
    'note': '',
    'created_at': '2026-10-23T00:00:00Z',
    'inspections': [],
    'exceptions': [],
  };
  TaskAccount() {
    restoring = false;
    activeWorkspace = {'id': 1, 'role': 'owner'};
  }
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'GET') return path.endsWith('history/') ? [] : task;
    submitted = Map<String, dynamic>.from(body as Map);
    submittedKey = idempotencyKey;
    if (conflict) {
      throw CollaborationApiException(
        409,
        '任务已更新，请刷新后重试',
        details: {
          'code': 'version_conflict',
          'current': {...task, 'version': 3, 'status': 'closed'},
        },
      );
    }
    return task;
  }

  @override
  Future<void> reload() async {}
}

void main() {
  late AppStore store;
  late TaskAccount account;
  setUp(() {
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false};
    account = TaskAccount();
  });
  tearDown(() {
    store.dispose();
    account.dispose();
  });
  Future<void> open(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(LineSightApp(store: store, cloud: account));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inspection requires issue note and sends stable versioned command',
    (tester) async {
      await open(
        tester,
        CloudTaskCommandPage(
          job: account.task,
          workspaceId: 1,
          action: 'inspect',
        ),
      );
      await tester.tap(find.text('异常'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(account.submitted, isNull);
      expect(find.text('请填写处理或异常说明'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Crack on edge');
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(account.submitted, {
        'version': 2,
        'verdict': 'fail',
        'note': 'Crack on edge',
      });
      expect(account.submittedKey!.length, greaterThanOrEqualTo(16));
    },
  );
  testWidgets(
    'version conflict retains notes and disables silent resubmission',
    (tester) async {
      account.conflict = true;
      await open(
        tester,
        CloudTaskCommandPage(
          job: account.task,
          workspaceId: 1,
          action: 'inspect',
        ),
      );
      await tester.enterText(find.byType(TextField), 'Inspector notes');
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(find.text('Inspector notes'), findsOneWidget);
      expect(find.text('返回并刷新任务'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认提交'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('expired identity hides task detail and cached history', (
    tester,
  ) async {
    await open(tester, CloudTaskPage(job: account.task, workspaceId: 1));
    expect(find.text('Bracket'), findsOneWidget);
    account.authenticated = false;
    account.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Bracket'), findsNothing);
    expect(find.text('task-1'), findsNothing);
    expect(find.text('返回工作台'), findsOneWidget);
  });

  testWidgets('task sections fit a narrow screen in both languages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final language in ['zh', 'en']) {
      store.preferences['language'] = language;
      await open(tester, CloudTaskPage(job: account.task, workspaceId: 1));
      for (final value in [1, 2, 3, 0]) {
        final segmented = tester.widget<SegmentedButton<int>>(
          find.byType(SegmentedButton<int>),
        );
        segmented.onSelectionChanged!({value});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$language/$value');
      }
      Navigator.of(tester.element(find.byType(CloudTaskPage))).pop();
      await tester.pumpAndSettle();
    }
  });
}

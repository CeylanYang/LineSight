import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_feedback.dart';
import 'package:linesight_flutter/cloud_trace.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'cloud_task_ui_test.dart' show DraftTaskAccount;

class ReauthAccount extends DraftTaskAccount {
  int generation = 0, writes = 0, taskReads = 0;
  String loginOwner = 'draft-owner', loginRole = 'owner';
  bool anotherHome = false,
      failRead = false,
      partialLogin = false,
      closeOnWrite = false;
  Map<String, dynamic>? latest;
  final team = <String, dynamic>{
    'id': 1,
    'role': 'owner',
    'name': 'Production',
  };
  @override
  String? get identityScope =>
      signedIn ? '$generation/${profile?['id']}' : null;
  void expire() {
    generation++;
    authenticated = false;
    profile = null;
    activeWorkspace = null;
    notifyListeners();
  }

  @override
  Future<void> signIn({bool demo = false, bool changePassword = false}) async {
    generation++;
    authenticated = true;
    profile = {'id': loginOwner, 'display_name': 'Quality operator'};
    workspaces = [
      {...team, 'role': loginRole},
      {'id': 2, 'role': 'owner', 'name': 'Personal'},
    ];
    activeWorkspace = workspaces[anotherHome ? 1 : 0];
    error = partialLogin ? '服务暂不可用' : null;
    notifyListeners();
  }

  @override
  Future<void> selectWorkspace(Map<String, dynamic> workspace) async {
    activeWorkspace = workspace;
    notifyListeners();
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method != 'GET') writes++;
    if (method == 'GET' && path.endsWith('members/')) {
      return <Map<String, dynamic>>[];
    }
    if (method == 'GET' && path.endsWith('jobs/${task['id']}/')) {
      taskReads++;
      if (failRead) throw const CollaborationApiException(503, '服务暂不可用');
      return latest ?? task;
    }
    final result = await super.request(
      method,
      path,
      body: body,
      idempotencyKey: idempotencyKey,
    );
    if (method == 'POST' && closeOnWrite) {
      latest = {...task, 'status': 'closed', 'version': 3};
    }
    return result;
  }
}

void main() {
  late ReauthAccount account;
  late AppStore store;
  setUp(() {
    account = ReauthAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false, 'haptic': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> open(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(LineSightApp(store: store, cloud: account));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    await tester.pumpAndSettle();
  }

  Future<void> inspection(WidgetTester tester) async {
    await open(
      tester,
      CloudTaskCommandPage(
        job: account.task,
        workspaceId: 1,
        action: 'inspect',
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'Measured 12.05 mm');
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.byType(CloudLoginPage), findsOneWidget);
    await tester.ensureVisible(find.text('进入演示团队'));
    await tester.tap(find.text('进入演示团队'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'same account reauthentication restores inspection and never replays its write',
    (tester) async {
      await inspection(tester);
      final originalKey = account.saved.values.single['request_key'];
      account.expire();
      await tester.pumpAndSettle();
      expect(find.text('Measured 12.05 mm'), findsNothing);
      await login(tester);
      expect(find.byType(CloudLoginPage), findsNothing);
      expect(find.text('Measured 12.05 mm'), findsOneWidget);
      expect(account.taskReads, 1);
      expect(account.writes, 0);
      await tester.ensureVisible(find.text('确认提交'));
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(account.writes, 1);
      expect(account.submittedKey, originalKey);
      expect(account.submitted?['note'], 'Measured 12.05 mm');
    },
  );

  testWidgets(
    'task changed during login resumes into version comparison with retained note',
    (tester) async {
      await inspection(tester);
      account.expire();
      await tester.pumpAndSettle();
      account.latest = {...account.task, 'version': 3, 'status': 'closed'};
      await login(tester);
      expect(find.text('Measured 12.05 mm'), findsOneWidget);
      await tester.ensureVisible(find.text('查看最新任务'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskConflictComparison), findsOneWidget);
      expect(account.writes, 0);
      expect(account.saved.values.single['version'], 2);
    },
  );

  for (final changedOwner in [true, false]) {
    testWidgets(
      '${changedOwner ? 'different account' : 'viewer'} cannot restore or submit another writable draft',
      (tester) async {
        await inspection(tester);
        account.expire();
        await tester.pumpAndSettle();
        if (changedOwner) {
          account.loginOwner = 'someone-else';
        } else {
          account.loginRole = 'viewer';
        }
        await login(tester);
        expect(find.text('Measured 12.05 mm'), findsNothing);
        expect(find.byType(CloudFailurePanel), findsOneWidget);
        expect(account.taskReads, 0);
        expect(account.writes, 0);
        expect(account.saved.values.single['note'], 'Measured 12.05 mm');
      },
    );
  }

  testWidgets(
    'cancelled secondary login leaves original protected draft intact',
    (tester) async {
      await inspection(tester);
      account.expire();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(account.signedIn, isFalse);
      expect(account.writes, 0);
      expect(account.saved.values.single['note'], 'Measured 12.05 mm');
    },
  );

  testWidgets(
    'login with a failed workspace load stays open until retry succeeds',
    (tester) async {
      await inspection(tester);
      account.expire();
      await tester.pumpAndSettle();
      account.partialLogin = true;
      await login(tester);
      expect(find.byType(CloudLoginPage), findsOneWidget);
      expect(account.taskReads, 0);
      expect(account.writes, 0);
      account.partialLogin = false;
      await tester.tap(find.text('进入演示团队'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudLoginPage), findsNothing);
      expect(find.text('Measured 12.05 mm'), findsOneWidget);
      expect(account.writes, 0);
    },
  );

  testWidgets(
    'recovery read failure offers retry and restores draft without writing',
    (tester) async {
      await inspection(tester);
      account.expire();
      await tester.pumpAndSettle();
      account.failRead = true;
      await login(tester);
      expect(find.byType(CloudFailurePanel), findsOneWidget);
      expect(account.writes, 0);
      account.failRead = false;
      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();
      expect(find.text('Measured 12.05 mm'), findsOneWidget);
      expect(account.taskReads, 2);
      expect(account.writes, 0);
    },
  );

  testWidgets(
    'new task draft returns to original accessible workspace after login at personal home',
    (tester) async {
      await open(tester, const CloudCreateTaskPage());
      await tester.enterText(find.byType(TextFormField).first, 'Valve batch');
      await tester.pumpAndSettle();
      final before = Map<String, dynamic>.from(account.saved.values.single);
      account.expire();
      await tester.pumpAndSettle();
      account.anotherHome = true;
      await login(tester);
      expect(find.text('Valve batch'), findsOneWidget);
      expect(account.activeWorkspace?['id'], 1);
      expect(account.saved.values.single['request_key'], before['request_key']);
      expect(account.writes, 0);
    },
  );

  testWidgets(
    'return from a recovered inspection refreshes its original task parent',
    (tester) async {
      account.closeOnWrite = true;
      await open(tester, CloudTaskPage(job: account.task, workspaceId: 1));
      await tester.ensureVisible(find.text('登记检验'));
      await tester.tap(find.text('登记检验'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Measured 12.05 mm');
      account.expire();
      await tester.pumpAndSettle();
      await login(tester);
      await tester.ensureVisible(find.text('确认提交'));
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskCommandPage), findsNothing);
      expect(find.text('工作区已切换'), findsNothing);
      expect(find.text('登记检验'), findsNothing);
      expect(account.taskReads, 3);
      expect(account.writes, 1);
    },
  );

  testWidgets(
    'trace-link parent rebuilt during login refreshes after restored inspection closes',
    (tester) async {
      account.closeOnWrite = true;
      account.task['id'] = 'c2836956-7784-42a1-a719-f34228b55c92';
      await open(
        tester,
        CloudTracePage(link: TaskTrace(1, account.task['id'] as String).link),
      );
      await tester.ensureVisible(find.text('登记检验'));
      await tester.tap(find.text('登记检验'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Measured 12.05 mm');
      account.expire();
      await tester.pumpAndSettle();
      await login(tester);
      await tester.ensureVisible(find.text('确认提交'));
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskCommandPage), findsNothing);
      expect(find.text('工作区已切换'), findsNothing);
      expect(find.text('登记检验'), findsNothing);
      expect(account.writes, 1);
    },
  );

  testWidgets('read-only member can reauthenticate directly in task detail', (
    tester,
  ) async {
    await open(tester, CloudTaskPage(job: account.task, workspaceId: 1));
    account.expire();
    await tester.pumpAndSettle();
    account.loginRole = 'viewer';
    await login(tester);
    expect(find.text('工作区已切换'), findsNothing);
    expect(find.text('登记检验'), findsNothing);
    expect(account.taskReads, 2);
    expect(account.writes, 0);
  });

  testWidgets(
    '401 read recovery reloads only after a successful secondary login',
    (tester) async {
      var reads = 0;
      await open(
        tester,
        Scaffold(
          body: CloudFailurePanel(
            failure: const CollaborationApiException(401, 'expired'),
            onRetry: () async {
              reads++;
            },
          ),
        ),
      );
      await login(tester);
      expect(reads, 1);
      expect(account.writes, 0);
    },
  );
}

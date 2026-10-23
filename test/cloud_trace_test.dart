import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_trace.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/liquid_glass_bar.dart';

const taskId = 'af04e1fb-168c-465e-b77a-fec1d1854653';

class TraceAccount extends CloudAccount {
  bool authenticated = false, denied = false;
  final reads = <String>[];
  final task = <String, dynamic>{
    'id': taskId,
    'version': 2,
    'part_name': 'Trace part',
    'printer': 'A1',
    'quantity': 1,
    'status': 'closed',
    'note': '',
    'created_at': '2026-10-23T00:00:00Z',
    'inspections': [],
    'exceptions': [],
    'evidence': [],
  };
  TraceAccount() {
    restoring = false;
    activeWorkspace = {'id': 1, 'role': 'viewer'};
    profile = {'id': 'trace-person'};
  }
  @override
  bool get signedIn => authenticated;
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    reads.add(path);
    if (path.contains('/jobs/$taskId/')) {
      if (denied) throw const CollaborationApiException(404, 'Not found');
      return path.endsWith('history/') ? [] : task;
    }
    if (path.endsWith('metrics/')) return <String, dynamic>{};
    return [];
  }
}

void main() {
  test(
    'trace payload validates authority, workspace and UUID without accepting remote endpoints',
    () {
      final trace = TaskTrace.parse('linesight://task/12/$taskId')!;
      expect(trace.workspaceId, 12);
      expect(trace.jobId, taskId);
      expect(TaskTrace.parse(taskId, workspaceId: 12)!.link, trace.link);
      for (final invalid in [
        'https://evil.example/12/$taskId',
        'linesight://task/0/$taskId',
        'linesight://task/12/$taskId?token=secret',
        'linesight://task/12/../../users',
        'linesight://task/12/not-a-task',
      ]) {
        expect(TaskTrace.parse(invalid), isNull);
      }
    },
  );
  testWidgets(
    'deep link uses secondary login and reads the task only after authentication',
    (tester) async {
      final store = AppStore()
        ..ready = true
        ..preferences = {
          'language': 'zh',
          'reduceMotion': true,
          'glass': false,
        };
      final account = TraceAccount();
      await tester.pumpWidget(LineSightApp(store: store, cloud: account));
      await tester.pumpAndSettle();
      await tester.binding.handlePushRoute('linesight://task/1/$taskId');
      await tester.pumpAndSettle();
      expect(find.byType(CloudTracePage), findsOneWidget);
      expect(find.byType(CloudTaskPage), findsNothing);
      expect(account.reads, isEmpty);
      account.authenticated = true;
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskPage), findsOneWidget);
      expect(find.text('Trace part'), findsWidgets);
      expect(account.reads, contains('workspaces/1/jobs/$taskId/'));
      await tester.pumpWidget(const SizedBox.shrink());
      account.dispose();
      store.dispose();
    },
  );
  testWidgets('unauthorized task link never displays task data', (
    tester,
  ) async {
    final store = AppStore()
      ..ready = true
      ..preferences = {'language': 'zh', 'reduceMotion': true, 'glass': false};
    final account = TraceAccount()
      ..authenticated = true
      ..denied = true;
    await tester.pumpWidget(LineSightApp(store: store, cloud: account));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline_rounded).last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<LiquidGlassBar>(find.byType(LiquidGlassBar)).selectedIndex,
      3,
    );
    await tester.binding.handlePushRoute('linesight://task/1/$taskId');
    await tester.pumpAndSettle();
    expect(find.text('记录暂不可访问'), findsOneWidget);
    expect(find.byType(CloudTaskPage), findsNothing);
    expect(find.text('Trace part'), findsNothing);
    expect(find.text('Not found'), findsNothing);
    await tester.tap(find.text('返回工作台'));
    await tester.pumpAndSettle();
    expect(find.byType(CloudTracePage), findsNothing);
    expect(
      tester.widget<LiquidGlassBar>(find.byType(LiquidGlassBar)).selectedIndex,
      0,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    account.dispose();
    store.dispose();
  });
}

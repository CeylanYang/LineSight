import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/screens/cloud_shell.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_task_ui_test.dart' show DraftTaskAccount;

class ReviewAccount extends DraftTaskAccount {
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) {
    if (method == 'GET' && path.endsWith('jobs/task-1/')) {
      return Future.value(conflictCurrent ?? task);
    }
    return super.request(
      method,
      path,
      body: body,
      idempotencyKey: idempotencyKey,
    );
  }
}

void main() {
  late ReviewAccount account;
  late AppStore store;
  setUp(() {
    account = ReviewAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false, 'haptic': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(LineSightApp(store: store, cloud: account));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(Scaffold).first)).push(
      appPageRoute<void>(
        tester.element(find.byType(Scaffold).first),
        CloudTaskCommandPage(
          job: account.task,
          workspaceId: 1,
          action: 'inspect',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('确认提交'));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'review latest task and return without losing the conflicting draft',
    (tester) async {
      account.conflict = true;
      account.conflictCurrent = {
        ...account.task,
        'version': 3,
        'part_name': 'Updated bracket',
        'status': 'closed',
        'inspections': [
          {'round_no': 1},
        ],
      };
      await open(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Keep my inspection note',
      );
      await submit(tester);
      expect(find.text('编辑时'), findsOneWidget);
      expect(find.text('任务更新后'), findsOneWidget);
      expect(find.text('Updated bracket'), findsOneWidget);
      expect(find.text('按当前任务继续'), findsNothing);
      await tester.ensureVisible(find.text('查看最新任务'));
      await tester.tap(find.text('查看最新任务'));
      await tester.pumpAndSettle();
      expect(find.byType(CloudTaskPage), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Keep my inspection note'), findsOneWidget);
      expect(find.text('任务更新后'), findsOneWidget);
      expect(account.saved.values.single['note'], 'Keep my inspection note');
      expect(account.saved.values.single['task_snapshot']['version'], 2);
    },
  );

  testWidgets(
    'changed checklist and serials are reviewed afresh after explicit continuation',
    (tester) async {
      final oldTemplate = {
        'id': 10,
        'name': 'Old checklist',
        'version': 1,
        'items': [
          {'id': 'a', 'label': 'Old dimension', 'required': true},
        ],
      };
      final nextTemplate = {
        'id': 11,
        'name': 'Updated checklist',
        'version': 2,
        'items': [
          {'id': 'a', 'label': 'Revised dimension', 'required': true},
        ],
      };
      account.task.addAll({
        'template': oldTemplate,
        'quantity': 2,
        'serial_numbers': ['SN-001', 'SN-002'],
      });
      account.conflict = true;
      account.conflictCurrent = {
        ...account.task,
        'version': 3,
        'template': nextTemplate,
        'serial_numbers': ['SN-001', 'SN-003'],
      };
      account.saved[account.draftKey('inspect-task-1')!] = {
        'version': 2,
        'task_snapshot': cloudTaskSnapshot(account.task),
        'template': oldTemplate,
        'note': 'Keep my explanation',
        'answers': {'a': 'fail'},
        'answer_notes': {'a': 'Old tolerance'},
        'serial_results': {'SN-001': 'pass', 'SN-002': 'fail'},
        'verdict': 'fail',
        'passed': '1',
        'failed': '1',
        'scrapped': '0',
      };
      await open(tester);
      await submit(tester);
      final firstKey = account.submittedKey;
      await tester.ensureVisible(find.text('按当前任务继续'));
      await tester.tap(find.text('按当前任务继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(
        account.submittedKey,
        firstKey,
      ); // Reviewing never replays a write.
      expect(find.text('Revised dimension'), findsOneWidget);
      expect(find.text('Old dimension'), findsNothing);
      expect(find.text('SN-002'), findsNothing);
      expect(find.text('SN-003'), findsOneWidget);
      expect(find.text('检查模板已更新，请重新逐项核对。'), findsOneWidget);
      final draft = account.saved.values.single;
      expect(draft['answers'], isEmpty);
      expect(draft['answer_notes'], isEmpty);
      expect(draft['task_snapshot']['version'], 3);
      expect(draft['note'], 'Keep my explanation');
      final passChip = find.widgetWithText(ChoiceChip, '合格');
      await tester.ensureVisible(passChip);
      await tester.tap(passChip);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SegmentedButton<String>));
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<String>),
          matching: find.text('合格'),
        ),
      );
      await tester.pumpAndSettle();
      account.conflict = false;
      await submit(tester);
      expect(account.submitted?['version'], 3);
      expect(account.submitted?['template_id'], 11);
      expect(account.submitted?['answers'], [
        {'id': 'a', 'result': 'pass', 'note': ''},
      ]);
      expect(account.submitted?['serial_results'], {
        'SN-001': 'pass',
        'SN-003': 'pass',
      });
      expect(account.submittedKey, isNot(firstKey));
    },
  );

  testWidgets('legacy stale draft does not invent its missing task snapshot', (
    tester,
  ) async {
    account.task['version'] = 3;
    account.saved[account.draftKey('inspect-task-1')!] = {
      'version': 2,
      'note': 'Legacy note',
    };
    await open(tester);
    expect(account.submitted, isNull);
    expect(find.text('编辑时'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    final comparison = tester.widget<CloudTaskConflictComparison>(
      find.byType(CloudTaskConflictComparison),
    );
    expect(comparison.before, {'version': 2});
    expect(find.text('Legacy note'), findsOneWidget);
  });

  testWidgets(
    'changing account during continuation confirmation keeps the old draft untouched',
    (tester) async {
      account.conflict = true;
      account.conflictCurrent = {...account.task, 'version': 3};
      await open(tester);
      await tester.enterText(
        find.byType(TextField).last,
        'Original account note',
      );
      await submit(tester);
      final oldKey = account.submittedKey;
      await tester.ensureVisible(find.text('按当前任务继续'));
      await tester.tap(find.text('按当前任务继续'));
      await tester.pumpAndSettle();
      account.profile = {'id': 'different-account'};
      account.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(account.submittedKey, oldKey);
      expect(account.saved.values.single['version'], 2);
      expect(account.saved.values.single['note'], 'Original account note');
      expect(find.text('Original account note'), findsNothing);
    },
  );

  testWidgets(
    'account name opens the secondary account page and back retains My tab',
    (tester) async {
      account.profile = {
        'id': 'draft-owner',
        'display_name': 'Quality Engineer',
        'username': 'quality.engineer',
      };
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(LineSightApp(store: store, cloud: account));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quality Engineer').first);
      await tester.pumpAndSettle();
      expect(find.byType(CloudProfilePage), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('团队与账户'), findsOneWidget);
      expect(find.byType(CloudProfilePage), findsNothing);
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets('$language narrow conflict comparison renders at large text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await (FontLoader('EvidenceFont')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
                ),
              ),
            ))
            .load();
      });
      final before = {
        ...account.task,
        'template': {'id': 10, 'name': 'PLA bracket checklist', 'version': 1},
        'updated_at': '2026-10-24T01:00:00Z',
      };
      final after = {
        ...before,
        'version': 3,
        'status': 'closed',
        'quantity': 12,
        'printer': 'Bambu Lab X1 Carbon',
        'template': {'id': 11, 'name': 'PLA bracket checklist', 'version': 2},
        'inspections': [
          {'round_no': 1},
        ],
        'updated_at': '2026-10-24T01:05:00Z',
      };
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: appTheme(false).copyWith(
            textTheme: appTheme(
              false,
            ).textTheme.apply(fontFamily: 'EvidenceFont'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.25)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: const ValueKey('conflict-review'),
                  child: GlassPanel(
                    child: CloudTaskConflictComparison(
                      before: cloudTaskSnapshot(before),
                      current: after,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(language == 'zh' ? '任务更新后' : 'Updated task'),
        findsOneWidget,
      );
      Directory(
        'docs/product/linesight/acceptance/conflict-batch/png',
      ).createSync(recursive: true);
      await expectLater(
        find.byKey(const ValueKey('conflict-review')),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/conflict-batch/png/98-conflict-review-$language-desktop-render.png',
        ),
      );
    });
  }
}

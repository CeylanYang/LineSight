import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/record_review.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/state_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stale evidence cannot change SQLite data or audit history', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/review-version-${uid()}.db';
    var s = AppStore();
    await s.init(path: path);
    addTearDown(() async {
      await s.db.close();
      s.dispose();
    });
    await s.register('review.admin', '复核管理员', 'Review-password-42');
    await s.login('review.admin', 'Review-password-42');
    final record = s.pending.first, originalPassed = s.pending.first.passed;
    final initial = ReviewRecordVersion.capture(record);
    await s.review(record.id, 'pass', '首轮核对检测证据', expectedVersion: initial);
    final current = s.data.inspections.firstWhere((r) => r.id == record.id);
    final currentVersion = ReviewRecordVersion.capture(current);
    final before = await StateStorage.read(s.db, 'workspace');
    final revision = s.revision, audits = s.data.audits.length;
    await expectLater(
      s.review(record.id, 'reject', '过期表单尝试覆盖', expectedVersion: initial),
      throwsStateError,
    );
    expect(await StateStorage.read(s.db, 'workspace'), before);
    expect(jsonEncode(s.data.toJson()), before);
    expect(s.revision, revision);
    expect(s.data.audits.length, audits);
    expect(s.writing, isFalse);
    await s.simulate('s1');
    await s.review(
      record.id,
      'reject',
      '无关记录变化不阻止复核',
      expectedVersion: currentVersion,
    );
    final beforeRestoreVersion = ReviewRecordVersion.capture(
      s.data.inspections.firstWhere((r) => r.id == record.id),
    );
    final incoming = Workspace.fromJson(s.data.toJson());
    incoming.inspections.firstWhere((r) => r.id == record.id).serial =
        'RESTORED-RECORD';
    await s.restore(incoming, expectedRevision: s.revision);
    final restored = await StateStorage.read(s.db, 'workspace');
    await expectLater(
      s.review(
        record.id,
        'pass',
        '旧证据不能继续提交',
        expectedVersion: beforeRestoreVersion,
      ),
      throwsStateError,
    );
    expect(await StateStorage.read(s.db, 'workspace'), restored);
    await s.db.close();
    s.dispose();
    s = AppStore();
    await s.init(path: path);
    await s.login('review.admin', 'Review-password-42');
    final persisted = s.data.inspections.firstWhere((r) => r.id == record.id);
    expect(persisted.serial, 'RESTORED-RECORD');
    expect(persisted.review, 'reject');
    expect(persisted.note, '无关记录变化不阻止复核');
    expect(persisted.passed, originalPassed);
    expect(
      s.history('record', record.id).where((a) => a.action == '质量复核'),
      hasLength(2),
    );
  });

  testWidgets('visible draft, conflict, acknowledged save and lock journey', (
    tester,
  ) async {
    final s = AppStore();
    await s.init(path: '${await getDatabasesPath()}/review-ui-${uid()}.db');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await s.db.close();
      s.dispose();
    });
    await s.register('draft.admin', '质量工程负责人', 'Draft-password-42');
    await s.login('draft.admin', 'Draft-password-42');
    final record = s.pending.first;
    await tester.pumpWidget(LineSightApp(store: s));
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    openPage(
      tester.element(find.byType(AppShell)),
      RecordDetailPage(id: record.id),
    );
    await tester.pumpAndSettle();
    Future<void> reveal(Finder target, {double delta = 300}) async {
      await tester.scrollUntilVisible(
        target,
        delta,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    Future<void> enterNote(String value) async {
      await reveal(find.byType(TextFormField));
      // The live binding caches focusedEditable after unfocus. A real tap
      // reconnects this same field before the next injected editing value.
      await tester.tap(find.byType(TextFormField));
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.enterText(find.byType(TextFormField), value);
      await tester.pump(const Duration(milliseconds: 300));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        value,
      );
    }

    await reveal(find.byType(TextFormField));
    await enterNote(' x ');
    await reveal(find.text('提交复核'));
    await tester.tap(find.text('提交复核'));
    await tester.pumpAndSettle();
    expect(find.text('请填写至少 3 个字的复核依据'), findsOneWidget);
    await capture('review-validation');
    await enterNote('逐项核对检测证据，确认可放行');
    await reveal(find.text('放行'), delta: -180);
    await tester.tap(find.text('放行'));
    await tester.pumpAndSettle();
    await reveal(find.text('提交复核'));
    await capture('review-draft');
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.text('放弃未提交的复核？'), findsOneWidget);
    await capture('review-leave-dialog');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await s.review(record.id, 'reject', '另一页面发现需要再次核查');
    await tester.pumpAndSettle();
    await reveal(find.text('记录已更新'), delta: -200);
    await capture('review-conflict');
    await tester.tap(find.text('核对后保留草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留草稿继续复核'));
    await tester.pumpAndSettle();
    await reveal(find.text('提交复核'));
    await tester.tap(find.text('提交复核'));
    await tester.pumpAndSettle();
    final saved = s.data.inspections.firstWhere((r) => r.id == record.id);
    expect(saved.review, 'pass');
    expect(saved.note, '逐项核对检测证据，确认可放行');
    expect(saved.passed, record.passed);
    expect(
      s.history('record', record.id).where((a) => a.action == '质量复核'),
      hasLength(2),
    );
    await reveal(find.text('与已保存的复核一致'));
    await capture('review-saved');
    await enterNote('锁定时清除这份新草稿');
    s.lock();
    await tester.pumpAndSettle();
    expect(find.byType(RecordDetailPage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    final stored = Workspace.fromJson(
      jsonDecode((await StateStorage.read(s.db, 'workspace'))!),
    );
    expect(
      stored.inspections.firstWhere((r) => r.id == record.id).note,
      '逐项核对检测证据，确认可放行',
    );
    expect(tester.takeException(), isNull);
  });
}

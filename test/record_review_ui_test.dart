import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/record_review.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class ReviewStore extends AppStore {
  int reviewCalls = 0;
  bool failSave = false;
  Completer<void>? saveGate;
  ReviewRecordVersion? submittedVersion;

  ReviewStore() {
    ready = true;
    user = const LocalUser('admin', 'admin', '管理员', 'admin', true);
    preferences = {'haptics': false, 'reduceMotion': true};
    data = Workspace.seed(examples: false)
      ..inspections = [
        Inspection(
          id: 'review-1',
          stationId: 's1',
          serial: 'REVIEW-001',
          recipeName: '测试配方',
          at: DateTime.utc(2026, 10, 14),
          passed: false,
          defect: '表面划痕',
          confidence: .98,
          operatorName: '检测员',
        ),
      ];
  }

  void change(void Function(Inspection) edit) {
    data = Workspace.fromJson(data.toJson());
    edit(data.inspections.single);
    revision++;
    notifyListeners();
  }

  @override
  Future<void> review(
    String id,
    String verdict,
    String note, {
    ReviewRecordVersion? expectedVersion,
  }) async {
    reviewCalls++;
    submittedVersion = expectedVersion;
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('模拟保存失败');
    if (expectedVersion == null ||
        !expectedVersion.matches(data.inspections.single)) {
      throw StateError('记录已发生变化，请核对最新记录后重新提交复核');
    }
    change(
      (r) => r
        ..review = verdict
        ..note = note.trim()
        ..reviewer = user!.name
        ..reviewedAt = DateTime.now().toUtc(),
    );
  }
}

Future<void> mount(
  WidgetTester tester,
  ReviewStore store, {
  double width = 390,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    AppScope(
      store: store,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RecordDetailPage(id: 'review-1'),
                  ),
                ),
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开详情'));
  await tester.pumpAndSettle();
}

Future<void> reveal(
  WidgetTester tester,
  Finder target, {
  double delta = 350,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> edit(WidgetTester tester, String text) async {
  await reveal(tester, find.byType(TextFormField));
  await tester.enterText(find.byType(TextFormField), text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'locking clears an unsaved review route without a discard dialog',
    (tester) async {
      final s = ReviewStore();
      addTearDown(s.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(LineSightApp(store: s));
      await tester.pumpAndSettle();
      openPage(
        tester.element(find.byType(AppShell)),
        const RecordDetailPage(id: 'review-1'),
      );
      await tester.pumpAndSettle();
      await edit(tester, '锁定时必须清除的草稿');
      s.lock();
      await tester.pumpAndSettle();
      expect(find.byType(RecordDetailPage), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('锁定时必须清除的草稿'), findsNothing);
      expect(s.reviewCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('back protects the draft and allows explicit discard', (
    tester,
  ) async {
    final s = ReviewStore();
    addTearDown(s.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, s);
    await edit(tester, '尚未提交的核查依据');
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.text('放弃未提交的复核？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '尚未提交的核查依据',
    );
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃并返回'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordDetailPage), findsNothing);
    expect(s.reviewCalls, 0);
  });

  testWidgets('inline validation, guarded save and clean back navigation', (
    tester,
  ) async {
    final s = ReviewStore();
    addTearDown(s.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, s);
    await edit(tester, ' x ');
    await reveal(tester, find.text('提交复核'));
    await tester.tap(find.text('提交复核'));
    await tester.pumpAndSettle();
    expect(find.text('请填写至少 3 个字的复核依据'), findsOneWidget);
    expect(s.reviewCalls, 0);
    await edit(tester, '  已核对完整检测证据  ');
    await reveal(tester, find.text('放行'), delta: -150);
    await tester.tap(find.text('放行'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('提交复核'));
    await tester.tap(find.text('提交复核'));
    await tester.pumpAndSettle();
    expect(s.reviewCalls, 1);
    expect(s.submittedVersion, isNotNull);
    expect(s.data.inspections.single.review, 'pass');
    expect(s.data.inspections.single.note, '已核对完整检测证据');
    expect(
      tester.widget<BusyButton>(find.byType(BusyButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.byType(RecordDetailPage), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'unrelated edits keep drafts; conflicting reviews require acknowledgement',
    (tester) async {
      final s = ReviewStore();
      addTearDown(s.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, s);
      await edit(tester, '我的复核草稿');
      s.change((_) => s.data.stations.first.name = '新工位名称');
      await tester.pumpAndSettle();
      expect(find.text('记录已更新'), findsNothing);
      expect(
        tester.widget<BusyButton>(find.byType(BusyButton)).onPressed,
        isNotNull,
      );
      s.change(
        (r) => r
          ..review = 'pass'
          ..note = '另一页面的复核'
          ..reviewer = '工程师'
          ..reviewedAt = DateTime.now(),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('记录已更新'), delta: -250);
      expect(find.text('记录已更新'), findsOneWidget);
      await reveal(tester, find.text('提交复核'));
      expect(
        tester.widget<BusyButton>(find.byType(BusyButton)).onPressed,
        isNull,
      );
      await reveal(tester, find.text('核对后保留草稿'), delta: -250);
      await tester.tap(find.text('核对后保留草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保留草稿继续复核'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextFormField));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '我的复核草稿',
      );
      await reveal(tester, find.text('提交复核'));
      await tester.tap(find.text('提交复核'));
      await tester.pumpAndSettle();
      expect(s.data.inspections.single.note, '我的复核草稿');
      expect(s.data.inspections.single.review, 'reject');
      expect(s.reviewCalls, 1);
    },
  );

  testWidgets(
    'reload checks again after confirmation and clean forms refresh',
    (tester) async {
      final s = ReviewStore();
      addTearDown(s.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, s);
      await reveal(tester, find.byType(TextFormField));
      s.change((r) => r.note = '没有草稿时自动刷新');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '没有草稿时自动刷新',
      );
      await edit(tester, '需要保留的草稿');
      s.change((r) => r.note = '最新保存的依据');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('载入最新复核'), delta: -250);
      await tester.tap(find.text('载入最新复核'));
      await tester.pumpAndSettle();
      s.change((r) => r.note = '确认期间再次发生变化');
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新载入'));
      await tester.pumpAndSettle();
      expect(find.text('记录再次发生变化，请重新核对'), findsOneWidget);
      await tester.tap(find.text('载入最新复核'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新载入'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byType(TextFormField));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '确认期间再次发生变化',
      );
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('removed or archived records keep drafts available to copy', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final removed in [false, true]) {
      final s = ReviewStore();
      await mount(tester, s);
      await edit(tester, '记录变化后仍可复制的草稿');
      if (removed) {
        s.data = Workspace.seed(examples: false);
        s.revision++;
        s.notifyListeners();
      } else {
        s.change((r) => r.archived = true);
      }
      await tester.pumpAndSettle();
      await reveal(tester, find.text('未提交的复核草稿'), delta: removed ? -250 : 250);
      expect(find.text('记录变化后仍可复制的草稿'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(find.text('放弃未提交的复核？'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    }
  });

  testWidgets('saving blocks edits and back; failure leaves the draft', (
    tester,
  ) async {
    final s = ReviewStore()
      ..saveGate = Completer<void>()
      ..failSave = true;
    addTearDown(s.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, s);
    await edit(tester, '保存失败后仍可重试');
    await reveal(tester, find.text('提交复核'));
    await tester.tap(find.text('提交复核'));
    await tester.pump();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    await tester.tap(find.byType(BackButton).last);
    await tester.pump();
    expect(find.text('正在保存复核，请稍候'), findsOneWidget);
    expect(find.byType(RecordDetailPage), findsOneWidget);
    s.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(s.data.inspections.single.review, isNull);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '保存失败后仍可重试',
    );
    await tester.tap(find.byType(BackButton).last);
    await tester.pumpAndSettle();
    expect(find.text('放弃未提交的复核？'), findsOneWidget);
  });

  testWidgets('review form and conflicts fit enlarged phone and tablet text', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [320.0, 1100.0]) {
      final s = ReviewStore();
      await mount(tester, s, width: width, scale: 1.8, dark: width == 1100);
      await edit(tester, '使用较大文字完成复核');
      s.change((r) => r.note = '最新证据已经改变');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('记录已更新'), delta: -300);
      await reveal(tester, find.text('提交复核'));
      expect(tester.takeException(), isNull, reason: 'width=$width');
      await tester.pumpWidget(const SizedBox.shrink());
      s.dispose();
    }
  });
}

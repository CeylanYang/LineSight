import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:linesight_flutter/screens/production.dart';
import 'package:linesight_flutter/l10n_catalog.dart';

class FormStore extends AppStore {
  int calls = 0;
  bool fail = true, committedFailure = false;
  Completer<void>? gate;
  final submitted = <ProductionJob>[];
  @override
  Future<void> createProductionJob(ProductionJob job) async {
    calls++;
    submitted.add(job);
    await gate?.future;
    if (committedFailure) data.jobs.add(job);
    if (fail) throw StateError('private database detail');
    data.jobs.add(job);
    notifyListeners();
  }
}

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language local task keeps form after failure and deduplicates taps',
      (t) async {
        t.view.physicalSize = const Size(320, 700);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final s = FormStore()
          ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
        addTearDown(s.dispose);
        String label(String v) =>
            language == 'en' ? englishMessages[v] ?? v : v;
        await mount(t, s, language);
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextFormField).first, '连接板');
        await t.enterText(find.byType(TextFormField).last, '12');
        final save = find.text(label('创建任务'));
        await t.ensureVisible(save);
        await t.tap(save);
        await t.pumpAndSettle();
        expect(find.text(label('保存失败，请重试')), findsOneWidget);
        expect(find.textContaining('private database'), findsNothing);
        expect(
          t
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          '连接板',
        );
        expect(
          t
              .widget<TextFormField>(find.byType(TextFormField).last)
              .controller!
              .text,
          '12',
        );
        s.fail = false;
        s.gate = Completer<void>();
        await t.tap(save);
        await t.pump();
        expect(s.calls, 2);
        expect(
          t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(
          t
              .widget<TextButton>(find.widgetWithText(TextButton, label('取消')))
              .onPressed,
          isNull,
        );
        s.gate!.complete();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(s.data.jobs.where((j) => j.partName == '连接板'), hasLength(1));
        expect(s.submitted[0].id, s.submitted[1].id);
      },
    );
  }
  testWidgets('committed local task is not repeated when refresh fails', (
    t,
  ) async {
    final s = FormStore()
      ..committedFailure = true
      ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
    addTearDown(s.dispose);
    await mount(t, s, 'zh');
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, '已保存任务');
    await t.tap(find.text('创建任务'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(s.calls, 1);
    expect(s.data.jobs.where((j) => j.partName == '已保存任务'), hasLength(1));
  });
  testWidgets('identity change hides local task draft and blocks submission', (
    t,
  ) async {
    final s = FormStore()
      ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
    addTearDown(s.dispose);
    await mount(t, s, 'zh');
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, '原账号草稿');
    s.user = const LocalUser('u2', 'other', '小周', 'operator', true);
    s.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('账户或团队已切换，请重新打开页面'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(s.calls, 0);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}

Future<void> mount(WidgetTester t, AppStore s, String language) async {
  await t.pumpWidget(
    AppScope(
      store: s,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => ProductionPage.createJob(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_template_workflow_test.dart' show TemplateAccount, checklist;

void main() {
  setUpAll(() async {
    for (final family in ['EvidenceFont', 'sans-serif', 'Roboto']) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  late TemplateAccount account;
  late AppStore store;
  setUp(() {
    account = TemplateAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'haptic': false, 'glass': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    Widget? page,
    double width = 390,
    double scale = 1,
    String language = 'zh',
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(false).copyWith(
          chipTheme: appTheme(false).chipTheme.copyWith(
            labelStyle: appTheme(
              false,
            ).chipTheme.labelStyle!.copyWith(fontFamily: 'EvidenceFont'),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: appTheme(false).filledButtonTheme.style!.copyWith(
              textStyle: const WidgetStatePropertyAll(
                TextStyle(
                  fontFamily: 'EvidenceFont',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          textTheme: appTheme(
            false,
          ).textTheme.apply(fontFamily: 'EvidenceFont'),
          appBarTheme: appTheme(false).appBarTheme.copyWith(
            titleTextStyle: appTheme(
              false,
            ).appBarTheme.titleTextStyle!.copyWith(fontFamily: 'EvidenceFont'),
          ),
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(
            account: account,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
        home: page ?? const Scaffold(body: CloudTemplatesPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Scaffold).last,
      matchesGoldenFile(
        '../docs/product/linesight/acceptance/templates81-batch/png/$name.png',
      ),
    );
  }

  testWidgets(
    'preview answers, notes, completion and reset never write or change template',
    (tester) async {
      final before = jsonEncode(account.templates);
      await show(
        tester,
        page: CloudTemplateDetailPage(template: account.templates.first),
      );
      await tap(tester, find.byKey(const ValueKey('preview-size-pass')));
      expect(find.text('已检查 1 / 3 项'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('preview-item-surface')));
      await tap(tester, find.byKey(const ValueKey('preview-surface-na')));
      await tap(tester, find.byKey(const ValueKey('preview-item-fit')));
      await tap(tester, find.byKey(const ValueKey('preview-fit-fail')));
      await tester.enterText(find.byType(TextField), '配合过紧');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('预览完成'), findsOneWidget);
      expect(find.text('异常 1'), findsOneWidget);
      await shot(tester, '81-completed-preview-zh');
      expect(account.posts, isEmpty);
      expect(account.reads, 0);
      expect(jsonEncode(account.templates), before);
      await tap(tester, find.byTooltip('重置预览'));
      expect(find.text('已检查 0 / 3 项'), findsOneWidget);
      expect(find.text('配合过紧'), findsNothing);
      expect(find.text('预览完成'), findsNothing);
    },
  );

  testWidgets(
    'catalogue searches checks, filters origin and returns with search intact',
    (tester) async {
      account.templates = [
        {...checklist(builtIn: true), 'name': '通用外观检查'},
        {
          ...checklist(id: 20),
          'name': '装配检查',
          'items': [
            {'id': 'fit', 'label': '工装配合', 'required': true, 'allow_na': false},
          ],
        },
      ];
      await show(tester);
      await shot(tester, '81-catalogue-zh');
      await tap(tester, find.widgetWithText(ChoiceChip, '团队模板'));
      expect(find.text('通用外观检查'), findsNothing);
      expect(find.text('装配检查'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, '全部'));
      await tester.enterText(find.byType(TextField), '工装');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('通用外观检查'), findsNothing);
      await tap(tester, find.text('交互预览'));
      expect(find.byType(CloudTemplateDetailPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '工装',
      );
      await tap(tester, find.text('用于任务'));
      expect(
        tester
            .widget<CloudCreateTaskPage>(find.byType(CloudCreateTaskPage))
            .initialTemplateId,
        20,
      );
      expect(account.posts, isEmpty);
    },
  );

  testWidgets(
    'changing version clears preview while keeping exact task version',
    (tester) async {
      account.templates = [checklist(), checklist(id: 11, version: 2)];
      await show(
        tester,
        page: CloudTemplateDetailPage(template: account.templates.last),
      );
      await tap(tester, find.byKey(const ValueKey('preview-size-fail')));
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<int>),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.byType(DropdownButtonFormField<int>));
      await tap(tester, find.text('v1').last);
      expect(find.text('已检查 0 / 3 项'), findsOneWidget);
      expect(find.text('异常 1'), findsNothing);
      await tap(tester, find.text('使用此模板创建任务'));
      expect(
        tester
            .widget<CloudCreateTaskPage>(find.byType(CloudCreateTaskPage))
            .initialTemplateId,
        10,
      );
      expect(account.posts, isEmpty);
    },
  );

  testWidgets(
    'viewer can interact but cannot create or publish; workspace change hides preview',
    (tester) async {
      account.activeWorkspace!['role'] = 'viewer';
      await show(tester);
      expect(find.text('用于任务'), findsNothing);
      expect(find.byTooltip('发布检查模板'), findsNothing);
      await tap(tester, find.text('交互预览'));
      await tap(tester, find.byKey(const ValueKey('preview-size-pass')));
      expect(find.text('使用此模板创建任务'), findsNothing);
      expect(find.text('复制模板'), findsNothing);
      account.activeWorkspace = {'id': 2, 'role': 'viewer'};
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('工作区已切换'), findsOneWidget);
      expect(find.text('交互预览'), findsNothing);
      expect(account.posts, isEmpty);
    },
  );

  testWidgets(
    'search empty state can recover and clears when workspace changes',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), 'not-found');
      await tester.pumpAndSettle();
      expect(find.text('未找到匹配模板'), findsOneWidget);
      await tap(tester, find.text('查看全部模板'));
      expect(find.text('Bracket checklist'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'size');
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor previews current edits and returns without publishing or losing edits',
    (tester) async {
      await show(tester, page: CloudTemplateEditor(template: checklist()));
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '检查项 1',
      );
      await tester.enterText(field, '修改后的检查项');
      await tap(tester, find.byTooltip('交互预览'));
      expect(find.text('修改后的检查项'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('preview-size-pass')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '修改后的检查项');
      expect(account.posts, isEmpty);
      expect(account.reads, 0);
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets('$language preview and catalogue fit narrow large text', (
      tester,
    ) async {
      await show(tester, width: 320, scale: 1.6, language: language);
      expect(tester.takeException(), isNull);
      await shot(tester, '81-catalogue-large-$language');
      await tap(
        tester,
        find.text(language == 'zh' ? '交互预览' : 'Interactive preview'),
      );
      await tap(tester, find.byKey(const ValueKey('preview-size-fail')));
      await shot(tester, '81-preview-large-$language');
      expect(find.byKey(const ValueKey('preview-size-na')), findsNothing);
    });
  }
}

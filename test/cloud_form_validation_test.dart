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
import 'cloud_task_ui_test.dart' show DraftTaskAccount;

class FormAccount extends DraftTaskAccount {
  int writes = 0;
  FormAccount() {
    templates = [
      {
        'id': 10,
        'name': 'Bracket checklist',
        'version': 1,
        'items': [
          {
            'id': 'size',
            'label': 'Critical dimensions',
            'required': true,
            'allow_na': false,
          },
          {
            'id': 'surface',
            'label': 'Surface finish',
            'required': false,
            'allow_na': true,
          },
          {
            'id': 'fit',
            'label': 'Assembly fit',
            'required': true,
            'allow_na': true,
          },
        ],
      },
    ];
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
      return [
        {'id': 12, 'display_name': 'Inspector Lin'},
      ];
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
  late FormAccount account;
  late AppStore store;
  setUp(() {
    account = FormAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false, 'haptic': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> open(
    WidgetTester tester,
    Widget page, {
    String language = 'zh',
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: 'EvidenceFont',
          colorScheme: appTheme(false).colorScheme,
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: RepaintBoundary(
          key: const ValueKey('form-evidence'),
          child: page,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    if (find.text(label).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(label),
        400,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.text(label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Finder input(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> inspect(WidgetTester tester) => open(
    tester,
    CloudTaskCommandPage(
      job: {...account.task, 'template': account.templates.first},
      workspaceId: 1,
      action: 'inspect',
    ),
  );

  testWidgets(
    'create scrolls from submit to first missing field without a request',
    (tester) async {
      await open(tester, const CloudCreateTaskPage());
      await tap(tester, '创建任务');
      expect(account.writes, 0);
      expect(find.text('请填写零件名称').hitTestable(), findsOneWidget);
      expect(find.text('请填写打印设备'), findsOneWidget);
    },
  );
  testWidgets(
    'serial count and duplicates are checked locally with inputs retained',
    (tester) async {
      await open(tester, const CloudCreateTaskPage());
      await tester.enterText(input('零件名称'), 'Bracket');
      await tester.enterText(input('打印设备'), 'A1');
      await tap(tester, '逐件SN追踪');
      await tester.enterText(input('SN，每行一个'), 'SN-A\nSN-A');
      await tap(tester, '创建任务');
      expect(account.writes, 0);
      final errorRect = tester.getRect(find.text('SN需要与工件数量一致且不能重复'));
      expect(errorRect.top, greaterThan(56));
      expect(errorRect.bottom, lessThan(800));
      expect(
        tester.widget<TextField>(input('零件名称')).controller!.text,
        'Bracket',
      );
    },
  );
  testWidgets('assignee can be cleared and selection is saved immediately', (
    tester,
  ) async {
    await open(tester, const CloudCreateTaskPage());
    await tester.ensureVisible(find.byType(DropdownButtonFormField<int>).last);
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inspector Lin').last);
    await tester.pumpAndSettle();
    expect(account.saved.values.single['assignee_id'], 12);
    await tester.tap(find.byType(DropdownButtonFormField<int>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('未指派').last);
    await tester.pumpAndSettle();
    expect(account.saved.values.single['assignee_id'], isNull);
  });
  testWidgets('inspection locates incomplete checklist before writing', (
    tester,
  ) async {
    await inspect(tester);
    await tap(tester, '确认提交');
    expect(account.writes, 0);
    expect(find.text('请选择检查结果'), findsNWidgets(2));
    expect(find.text('Critical dimensions').hitTestable(), findsOneWidget);
  });
  testWidgets(
    'inspection rejects inconsistent quantities and preserves checklist',
    (tester) async {
      await inspect(tester);
      for (final index in [0, 2]) {
        final chip = find.widgetWithText(ChoiceChip, '合格').at(index);
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(input('合格数量'));
      await tester.enterText(input('合格数量'), '9');
      await tap(tester, '确认提交');
      expect(account.writes, 0);
      expect(find.text('检验结论与工件数量不一致').hitTestable(), findsOneWidget);
      expect(
        account.saved.values.single['answers'],
        containsPair('size', 'pass'),
      );
    },
  );
  testWidgets('template validation runs before publishing and locates name', (
    tester,
  ) async {
    await open(tester, const CloudTemplateEditor());
    await tap(tester, '发布');
    expect(account.writes, 0);
    expect(find.text('请填写模板名称和3至6个检查项').hitTestable(), findsOneWidget);
  });
  testWidgets('template rejects overlong item without publishing', (
    tester,
  ) async {
    await open(tester, const CloudTemplateEditor());
    await tester.enterText(input('模板名称'), 'Final inspection');
    await tester.ensureVisible(input('每行一项（3 至 6 项）'));
    await tester.enterText(input('每行一项（3 至 6 项）'), '${'A' * 121}\nFit\nFinish');
    await tap(tester, '发布');
    expect(account.writes, 0);
    expect(find.text('每个检查项最多120个字符').hitTestable(), findsOneWidget);
  });
  for (final language in ['zh', 'en']) {
    testWidgets('$language narrow checklist validation screenshot', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await (FontLoader('EvidenceFont')..addFont(
              Future.value(
                ByteData.sublistView(
                  File('assets/fonts/NotoSansSC.ttf').readAsBytesSync(),
                ),
              ),
            ))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      await open(
        tester,
        CloudTaskCommandPage(
          job: {...account.task, 'template': account.templates.first},
          workspaceId: 1,
          action: 'inspect',
        ),
        language: language,
      );
      await tap(tester, language == 'zh' ? '确认提交' : 'Submit');
      expect(account.writes, 0);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('form-evidence')),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/forms-batch/png/114-checklist-validation-$language-desktop-render.png',
        ),
      );
    });
  }
}

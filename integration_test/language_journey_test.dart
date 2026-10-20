import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/state_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'language persists before sign-in, across writes, review drafts and SQLite reopening',
    (tester) async {
      final path =
          '${await getDatabasesPath()}/language-acceptance-${uid()}.db';
      var store = AppStore();
      await store.init(path: path);
      addTearDown(() async {
        await store.db.close();
        store.dispose();
      });
      expect(store.languageCode, 'zh');
      await tester.pumpWidget(LineSightApp(store: store));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await binding.takeScreenshot('language-chinese-setup');
      await tester.tap(find.byKey(const ValueKey('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String> && w.value == 'en',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready to see the details.'), findsOneWidget);
      expect(store.user, isNull);
      expect(
        jsonDecode(
          (await StateStorage.read(store.db, 'preferences'))!,
        )['language'],
        'en',
      );
      await binding.takeScreenshot('language-english-setup');
      await tester.pumpWidget(const SizedBox());
      await store.db.close();
      store.dispose();
      store = AppStore();
      await store.init(path: path);
      expect(store.languageCode, 'en');
      await store.register('language.admin', '验收管理员', 'Language-password-42');
      await store.login('language.admin', 'Language-password-42');
      final before = jsonEncode(store.data.toJson());
      await Future.wait([
        store.preference('dark', true),
        store.setLanguage('zh'),
        store.setLanguage('en'),
      ]);
      expect(store.dark, isTrue);
      expect(store.languageCode, 'en');
      expect(jsonEncode(store.data.toJson()), before);
      final preferences = jsonDecode(
        (await StateStorage.read(store.db, 'preferences'))!,
      );
      expect(preferences['dark'], isTrue);
      expect(preferences['language'], 'en');
      await store.preference('dark', false);
      await tester.pumpWidget(LineSightApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
      await binding.takeScreenshot('language-english-dashboard');
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      final languageSetting = find.byKey(const ValueKey('language-settings'));
      await tester.tap(languageSetting);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-option-zh')));
      await tester.pumpAndSettle();
      expect(find.text('你的工作区。'), findsOneWidget);
      expect(store.languageCode, 'zh');
      await tester.tap(languageSetting);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-option-en')));
      await tester.pumpAndSettle();
      expect(find.text('Your workspace.'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      await binding.takeScreenshot('language-english-settings');
      final record = store.pending.first;
      final original = record.passed;
      openPage(
        tester.element(find.byType(AppShell)),
        RecordDetailPage(id: record.id),
      );
      await tester.pumpAndSettle();
      final noteFinder = find.byType(TextFormField);
      await tester.scrollUntilVisible(
        noteFinder,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(noteFinder);
      await tester.pumpAndSettle();
      await tester.enterText(noteFinder, 'Checked surface. 中文依据保留。');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await store.setLanguage('zh');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(noteFinder).controller!.text,
        'Checked surface. 中文依据保留。',
      );
      expect(find.text('提交复核'), findsOneWidget);
      await store.setLanguage('en');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept').last);
      await tester.pumpAndSettle();
      final submit = find.text('Submit review');
      await tester.scrollUntilVisible(
        submit,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final saved = store.data.inspections.firstWhere((r) => r.id == record.id);
      expect(saved.review, 'pass');
      expect(saved.passed, original);
      expect(saved.note, 'Checked surface. 中文依据保留。');
      await binding.takeScreenshot('language-english-review');
      await tester.pumpWidget(const SizedBox());
      await store.db.close();
      store.dispose();
      store = AppStore();
      await store.init(path: path);
      expect(store.languageCode, 'en');
      expect(store.user, isNull);
      expect(
        store.data.inspections.firstWhere((r) => r.id == record.id).note,
        'Checked surface. 中文依据保留。',
      );
      await tester.pumpWidget(LineSightApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      await store.setLanguage('zh');
      await tester.pumpAndSettle();
      expect(find.text('欢迎回到工作台'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

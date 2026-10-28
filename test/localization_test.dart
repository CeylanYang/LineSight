import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/l10n.dart';
import 'package:linesight_flutter/l10n_catalog.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/record_query.dart';
import 'package:linesight_flutter/record_csv.dart';
import 'package:linesight_flutter/screens/auth.dart';
import 'package:linesight_flutter/screens/backup_transfer.dart';
import 'package:linesight_flutter/screens/dashboard.dart';
import 'package:linesight_flutter/screens/modules.dart';
import 'package:linesight_flutter/screens/records.dart';
import 'package:linesight_flutter/screens/settings.dart';
import 'package:linesight_flutter/screens/statistics.dart';
import 'package:linesight_flutter/screens/storage_recovery.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';

class LanguageStore extends AppStore {
  LanguageStore({bool signedIn = false}) {
    ready = true;
    preferences = {'reduceMotion': true, 'haptics': false};
    data = Workspace.seed();
    if (signedIn) {
      user = const LocalUser('admin', 'admin', '中文用户', 'admin', true);
      users = [user!];
    }
  }
  @override
  Future<void> setLanguage(String language) async {
    preferences = {...preferences, 'language': language};
    notifyListeners();
  }
}

void main() {
  test('team workspace customer labels have English counterparts', () {
    expect(englishMessages['团队管理员'], 'Team admin');
    expect(englishMessages['操作成员'], 'Operator');
    expect(englishMessages['只读成员'], 'View only');
    expect(englishMessages['团队成员'], 'Team members');
    expect(
      englishMessages['查看照片与边缘参考 #{0}'],
      'View photo and edge reference #{0}',
    );
  });

  test(
    'CSV header follows captured language while multilingual data stays unchanged',
    () {
      final store = LanguageStore(signedIn: true)
        ..preferences['language'] = 'en';
      store.data.inspections.first.note = '中文备注 / English note';
      final english = store.captureCsv(store.records);
      store.preferences['language'] = 'zh';
      final chinese = store.captureCsv(store.records);
      expect(english.columns.first, 'Record ID');
      expect(chinese.columns, csvColumns);
      expect(csvChunks(english).first, startsWith('\uFEFF"Record ID"'));
      expect(
        english.records
            .firstWhere((r) => r.id == store.data.inspections.first.id)
            .values[11],
        '中文备注 / English note',
      );
      expect(english.columns.first, 'Record ID');
      store.dispose();
    },
  );

  test('English defect searches preserve canonical records', () {
    final store = LanguageStore(signedIn: true);
    final before = jsonEncode(store.data.toJson());
    final cache = RecordQueryCache();
    final english = cache.resolve(
      workspace: store.data,
      revision: 0,
      session: 0,
      query: 'surface SCRATCH',
    );
    final chinese = cache.resolve(
      workspace: store.data,
      revision: 0,
      session: 0,
      query: '表面划痕',
    );
    expect(english.ids, isNotEmpty);
    expect(english.ids, chinese.ids);
    expect(jsonEncode(store.data.toJson()), before);
    store.dispose();
  });

  test(
    'every translation preserves placeholders and contains English text',
    () {
      final slots = RegExp(r'\{\d+\}');
      for (final entry in englishMessages.entries) {
        expect(
          slots.allMatches(entry.value).map((m) => m[0]).toList()..sort(),
          slots.allMatches(entry.key).map((m) => m[0]).toList()..sort(),
          reason: entry.key,
        );
        expect(
          RegExp(r'[\u3400-\u9fff]').hasMatch(entry.value),
          isFalse,
          reason: entry.key,
        );
      }
      final store = AppStore()..preferences = {'language': 'unsupported'};
      expect(store.languageCode, 'zh');
      store.dispose();
    },
  );

  testWidgets('login language menu switches immediately and retains input', (
    tester,
  ) async {
    final store = LanguageStore();
    addTearDown(store.dispose);
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(LineSightApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('准备好，看见细节。'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'quality.user');
    await tester.tap(find.byKey(const ValueKey('language-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<String> && w.value == 'en',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready to see the details.'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale?.languageCode,
      'en',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'quality.user',
    );
    await tester.tap(find.byKey(const ValueKey('language-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<String> && w.value == 'zh',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('准备好，看见细节。'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'quality.user',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('English labels and service messages preserve user arguments', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(tr(context, '关键词：{0}', ['中文备注 {0}']), 'Keyword: 中文备注 {0}');
    expect(
      trMessage(context, '密码需要 8–128 个字符'),
      'Password must contain 8–128 characters',
    );
    expect(
      trMessage(context, '正在生成 CSV · 3 / 10 条'),
      'Generating CSV · 3 / 10 records',
    );
    expect(
      trMessage(context, '草稿未删除，请重试'),
      'Draft was not deleted. Please retry.',
    );
    expect(trMessage(context, '已提交打印'), 'Print job submitted');
    expect(trMessage(context, '已取消打印'), 'Printing cancelled');
    expect(
      trMessage(context, '阅读进度未保存，请点书签重试'),
      'Reading progress was not saved. Tap the bookmark to retry.',
    );
    expect(
      trMessage(context, '已收藏，第 12 集等你回来'),
      'Episode 12 bookmarked. Come back any time.',
    );
    expect(trMessage(context, '用户输入原文 {0}'), '用户输入原文 {0}');
  });

  testWidgets(
    'Profile contains a working language setting for both directions',
    (tester) async {
      final store = LanguageStore(signedIn: true);
      addTearDown(store.dispose);
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(LineSightApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      final setting = find.byKey(const ValueKey('language-settings'));
      await tester.tap(setting);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-option-en')));
      await tester.pumpAndSettle();
      expect(find.text('Your workspace.'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      await tester.tap(setting);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-option-zh')));
      await tester.pumpAndSettle();
      expect(find.text('你的工作区。'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'English audit filters use canonical actions and retain original prose',
    (tester) async {
      final store = LanguageStore(signedIn: true)
        ..preferences['language'] = 'en';
      addTearDown(store.dispose);
      for (var i = 0; i < 2; i++) {
        store.data.audits.add(
          AuditEntry(
            'log-$i',
            '中文用户',
            i == 0 ? '质量复核' : '添加示例',
            '原始操作说明 $i',
            DateTime.now(),
          ),
        );
      }
      final before = jsonEncode(store.data.toJson());
      await tester.pumpWidget(
        AppScope(
          store: store,
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: [Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: AuditPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 actions'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('原始操作说明 0'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('原始操作说明 0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quality review').last);
      await tester.pumpAndSettle();
      expect(find.text('1 actions'), findsOneWidget);
      expect(jsonEncode(store.data.toJson()), before);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('English pages handle narrow large text and tablet layouts', (
    tester,
  ) async {
    final store = LanguageStore(signedIn: true)..preferences['language'] = 'en';
    addTearDown(store.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final before = jsonEncode(store.data.toJson());
    final pages = <Widget>[
      const AuthPage(),
      Scaffold(body: DashboardPage(onRecords: () {})),
      const RecordsScreen(),
      RecordDetailPage(id: store.data.inspections.first.id),
      const Scaffold(body: ModulesPage()),
      const RecipeEditorPage(),
      const ChangeoverPage(),
      const StatisticsPage(),
      const Scaffold(body: SettingsPage()),
      const MembersPage(),
      const DataPage(),
      const HelpPage(),
      const BackupExportPage(),
      const StorageFailurePage(),
    ];
    for (final width in [320.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      for (final page in pages) {
        await tester.pumpWidget(
          AppScope(
            store: store,
            child: MaterialApp(
              locale: const Locale('en'),
              supportedLocales: const [Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: appTheme(width == 1100),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: page,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.runtimeType} at $width',
        );
        final scroll = find.byType(Scrollable);
        if (scroll.evaluate().isNotEmpty) {
          for (var i = 0; i < 4; i++) {
            await tester.drag(scroll.first, const Offset(0, -550));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.runtimeType} scroll $i at $width',
            );
          }
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
    expect(jsonEncode(store.data.toJson()), before);
  });
}

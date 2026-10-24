import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/collaboration_api.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;

Map<String, dynamic> checklist({
  int id = 10,
  int version = 1,
  bool builtIn = false,
}) => {
  'id': id,
  'name': 'Bracket checklist',
  'version': version,
  'built_in': builtIn,
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
    {'id': 'fit', 'label': 'Assembly fit', 'required': true, 'allow_na': true},
  ],
};

class TemplateAccount extends AccessAccount {
  final posts = <({Map<String, dynamic> body, String? key})>[];
  int reads = 0;
  Object? writeFailure, readFailure;
  Completer<Map<String, dynamic>>? postGate;
  List<Map<String, dynamic>> serverRows = [checklist()];
  TemplateAccount() {
    templates = [checklist()];
  }
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    if (method == 'GET') {
      reads++;
      if (readFailure != null) throw readFailure!;
      return serverRows;
    }
    final data = Map<String, dynamic>.from(body as Map);
    posts.add((body: data, key: idempotencyKey));
    if (writeFailure != null) throw writeFailure!;
    if (postGate != null) return postGate!.future;
    return {
      'id': 12,
      'name': data['name'],
      'version': data.containsKey('base_template_id') ? 2 : 1,
      'items': data['items'],
      'built_in': false,
    };
  }
}

void main() {
  late TemplateAccount account;
  late AppStore store;
  setUp(() {
    account = TemplateAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'glass': false, 'haptic': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> show(
    WidgetTester tester, {
    Widget? page,
    String language = 'en',
    bool routed = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          fontFamily: 'EvidenceFont',
          colorScheme: appTheme(false).colorScheme,
        ),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(
            account: account,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
        home: routed
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => openPage(
                      context,
                      page ?? CloudTemplateEditor(template: checklist()),
                    ),
                    child: const Text('Origin'),
                  ),
                ),
              )
            : page ?? CloudTemplateEditor(template: checklist()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder control(String label) =>
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == label);
  Finder input(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  testWidgets(
    'publishing preserves source IDs and flags when items are reordered',
    (tester) async {
      await show(tester);
      await tap(tester, control('Move down').first);
      await tap(tester, find.text('Publish'));
      final data = account.posts.single.body;
      expect(data['base_template_id'], 10);
      expect((data['items'] as List).map((e) => e['id']), [
        'surface',
        'size',
        'fit',
      ]);
      expect((data['items'] as List).first['required'], isFalse);
      expect((data['items'] as List)[1]['allow_na'], isFalse);
      expect(find.text('Checklist published'), findsWidgets);
      expect(account.templates.any((t) => t['id'] == 12), isTrue);
    },
  );
  testWidgets(
    'copy uses a distinct editable name and leaves the source intact',
    (tester) async {
      final source = checklist(builtIn: true);
      await show(
        tester,
        page: CloudTemplateEditor(template: source, copy: true),
      );
      expect(
        tester.widget<TextField>(input('Checklist name')).controller!.text,
        'Bracket checklist Copy',
      );
      await tap(tester, find.text('Publish'));
      expect(
        account.posts.single.body.containsKey('base_template_id'),
        isFalse,
      );
      expect(source['name'], 'Bracket checklist');
      expect(source['items'], checklist()['items']);
    },
  );
  testWidgets(
    'new item controls enforce three to six items and retain option toggles',
    (tester) async {
      await show(tester);
      expect(
        tester.widget<IconButton>(control('Remove check').first).onPressed,
        isNull,
      );
      for (var i = 0; i < 3; i++) {
        await tap(tester, find.text('Add check'));
      }
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add check'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, control('Remove check').last);
      expect(find.byType(SwitchListTile), findsNWidgets(10));
      await tap(tester, find.byType(SwitchListTile).first);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
        isFalse,
      );
    },
  );
  testWidgets(
    'a lost response retries the identical payload with the same key, GET recovery never posts',
    (tester) async {
      account.writeFailure = const CollaborationApiException(
        503,
        'private transport',
      );
      await show(tester);
      await tap(tester, find.text('Publish'));
      final key = account.posts.single.key;
      expect(key!.length, inInclusiveRange(16, 64));
      expect(find.textContaining('private transport'), findsNothing);
      await tap(tester, find.text('Retry'));
      expect(account.posts.length, 1);
      account.writeFailure = null;
      await tap(tester, find.text('Publish'));
      expect(account.posts.last.key, key);
    },
  );
  testWidgets(
    'changing the payload after a failed attempt uses a different publication key',
    (tester) async {
      account.writeFailure = const CollaborationApiException(503, 'private');
      await show(tester);
      await tap(tester, find.text('Publish'));
      final key = account.posts.single.key;
      await tester.enterText(input('Check 1'), 'Revised dimensions');
      await tap(tester, find.text('Publish'));
      expect(account.posts.last.key, isNot(key));
    },
  );
  testWidgets(
    'acknowledged publication remains successful when catalogue refresh fails',
    (tester) async {
      account.readFailure = const CollaborationApiException(503, 'private');
      await show(tester);
      await tap(tester, find.text('Publish'));
      expect(find.text('Checklist published'), findsWidgets);
      expect(find.text('Publish'), findsNothing);
      expect(
        tester.widget<TextField>(input('Checklist name')).enabled,
        isFalse,
      );
      account.readFailure = null;
      await tap(tester, find.text('Retry'));
      expect(account.posts.length, 1);
      expect(find.text('Done'), findsOneWidget);
    },
  );
  testWidgets(
    'stale publication compares the latest version and requires explicit acceptance',
    (tester) async {
      account.writeFailure = const CollaborationApiException(409, 'private');
      account.serverRows = [checklist(), checklist(id: 11, version: 2)];
      await show(tester);
      await tester.enterText(input('Check 1'), 'My retained change');
      await tap(tester, find.text('Publish'));
      await tap(tester, find.text('View latest version'));
      expect(account.posts.length, 1);
      expect(
        tester.widget<TextField>(input('Check 1')).controller!.text,
        'My retained change',
      );
      await tap(tester, find.text('Use the latest version and keep my edits'));
      account.writeFailure = null;
      await tap(tester, find.text('Publish'));
      expect(account.posts.last.body['base_template_id'], 11);
    },
  );
  testWidgets(
    'switching workspace while publication is pending hides the late receipt',
    (tester) async {
      account.postGate = Completer();
      await show(tester);
      await tester.ensureVisible(find.text('Publish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish'));
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Publish'),
      );
      expect(button.onPressed, isNull);
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifyListeners();
      await tester.pumpAndSettle();
      account.postGate!.complete(checklist(id: 12, version: 2));
      await tester.pumpAndSettle();
      expect(find.text('Workspace changed'), findsOneWidget);
      expect(find.text('Checklist published'), findsNothing);
      expect(account.reads, 0);
    },
  );
  testWidgets(
    'dirty back asks once; cancel preserves content and discard returns to origin',
    (tester) async {
      await show(tester, routed: true);
      await tap(tester, find.text('Origin'));
      await tester.enterText(input('Check 1'), 'Unsaved dimensions');
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Cancel'));
      expect(
        tester.widget<TextField>(input('Check 1')).controller!.text,
        'Unsaved dimensions',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(tester, find.text('Discard and go back'));
      expect(find.text('Origin'), findsOneWidget);
      expect(account.posts, isEmpty);
    },
  );
  testWidgets(
    'catalogue shows latest per family; detail offers historic versions and hides writes for viewers',
    (tester) async {
      account.templates = [checklist(), checklist(id: 11, version: 2)];
      await show(tester, page: const Scaffold(body: CloudTemplatesPage()));
      expect(find.text('Bracket checklist'), findsOneWidget);
      await tap(tester, find.text('Bracket checklist'));
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      await tap(tester, find.byType(DropdownButtonFormField<int>));
      await tap(tester, find.text('v1').last);
      expect(find.text('Publish new version'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Copy checklist'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Copy checklist'), findsOneWidget);
      account.activeWorkspace!['role'] = 'viewer';
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Workspace changed'), findsOneWidget);
    },
  );
  testWidgets(
    'finishing publication returns to the newly published version even if catalogue refresh fails',
    (tester) async {
      account.readFailure = const CollaborationApiException(503, 'private');
      await show(tester, page: CloudTemplateDetailPage(template: checklist()));
      await tap(tester, find.text('Publish new version'));
      await tap(tester, find.text('Publish'));
      await tap(tester, find.text('Done'));
      expect(find.byType(CloudTemplateEditor), findsNothing);
      await tester.scrollUntilVisible(
        find.byType(DropdownButtonFormField<int>),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      final version = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      expect(version.initialValue, 12);
      await tester.scrollUntilVisible(
        find.text('Publish new version'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Publish new version'), findsOneWidget);
      expect(account.posts.length, 1);
    },
  );
  for (final language in ['zh', 'en']) {
    for (final state in [
      'catalogue',
      'detail',
      'editor',
      'editor-end',
      'receipt',
      'conflict',
    ]) {
      testWidgets('$language checklist $state component PNG', (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
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
        if (state == 'conflict') {
          account.writeFailure = const CollaborationApiException(
            409,
            'private',
          );
        }
        await show(
          tester,
          language: language,
          page: switch (state) {
            'catalogue' => const Scaffold(body: CloudTemplatesPage()),
            'detail' => CloudTemplateDetailPage(template: checklist()),
            _ => CloudTemplateEditor(template: checklist()),
          },
        );
        if (state == 'receipt' || state == 'conflict') {
          await tap(tester, find.text(language == 'zh' ? '发布' : 'Publish'));
        }
        if (state == 'editor-end') {
          await tester.ensureVisible(
            find.text(language == 'zh' ? '发布' : 'Publish'),
          );
          await tester.pumpAndSettle();
        }
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../docs/product/linesight/acceptance/${state == 'catalogue' ? 'cloud82-batch' : 'templates81-batch'}/template-batch/png/180-checklist-$state-$language-desktop-render.png',
          ),
        );
      });
    }
    testWidgets('$language checklist small large-text and tablet layouts', (
      tester,
    ) async {
      for (final size in [const Size(320, 640), const Size(900, 1100)]) {
        await tester.binding.setSurfaceSize(size);
        await show(tester, language: language, textScale: 1.6);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_history.dart';
import 'package:linesight_flutter/screens/cloud_business.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_access_ui_test.dart' show AccessAccount;
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'docs/product/linesight/acceptance/history-batch/live-history.json',
            ).readAsStringSync(),
          )
          as Map;
  final events = (fixture['events'] as List).cast<Map<String, dynamic>>();
  final inspection = Map<String, dynamic>.from(
    (fixture['inspections'] as List).firstWhere((row) => row['round_no'] == 1),
  );
  late AccessAccount account;
  late AppStore store;
  setUp(() {
    account = AccessAccount();
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'haptic': false, 'glass': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> show(WidgetTester tester, Widget page, String locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(fontFamily: 'EvidenceFont'),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fonts() async {
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
  }

  for (final locale in ['zh', 'en']) {
    testWidgets('live history and first-round SN $locale desktop evidence', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await fonts();
      await show(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final event in events) CloudHistoryEvent(event: event),
                ],
              ),
            ),
          ),
        ),
        locale,
      );
      expect(find.byType(CloudHistoryEvent), findsNWidgets(8));
      // Locate by the actual event identity; translated titles can evolve independently.
      final failureTile = find.descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is CloudHistoryEvent && w.event['action'] == 'inspection.fail',
        ),
        matching: find.byType(ExpansionTile),
      );
      await tester.tap(failureTile);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(locale == 'zh' ? '检验轮次 · 1' : 'Round · 1'),
        findsOneWidget,
      );
      expect(
        find.textContaining(locale == 'zh' ? '合格数 · 1' : 'Passed · 1'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/history-batch/png/64-history-$locale-desktop-render.png',
        ),
      );
      await show(tester, CloudInspectionDetailPage(record: inspection), locale);
      await tester.ensureVisible(find.byType(CloudSerialResults));
      await tester.pumpAndSettle();
      for (final serial in fixture['serial_numbers'] as List) {
        expect(find.text(serial as String), findsOneWidget);
      }
      expect(
        (inspection['serial_results'] as Map).values
            .where((v) => v == 'pass')
            .length,
        1,
      );
      expect(
        (inspection['serial_results'] as Map).values
            .where((v) => v == 'fail')
            .length,
        1,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/history-batch/png/65-serial-results-$locale-desktop-render.png',
        ),
      );
      account.activeWorkspace = {'id': 2, 'role': 'owner'};
      account.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(CloudSerialResults), findsNothing);
      expect(
        find.text(locale == 'zh' ? '工作区已切换' : 'Workspace changed'),
        findsOneWidget,
      );
    });
  }
  testWidgets(
    'sparse history preserves unknown actor and has no invented transition',
    (tester) async {
      await show(
        tester,
        const Scaffold(
          body: CloudHistoryEvent(
            event: {
              'action': 'job.created',
              'details': {},
              'created_at': '2026-10-23T14:08:34Z',
              'object_id': 'task-a',
            },
          ),
        ),
        'zh',
      );
      expect(find.textContaining('未记录操作者'), findsOneWidget);
      expect(find.textContaining('→'), findsNothing);
    },
  );
}

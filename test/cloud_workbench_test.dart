import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_workbench.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';

class WorkbenchAccount extends CloudAccount {
  WorkbenchAccount() {
    workspaceDataLoaded = true;
  }
  @override
  bool get signedIn => true;
}

class RouteCapture extends NavigatorObserver {
  Route<dynamic>? latest;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    latest = route;
  }
}

void main() {
  test('write access requires an explicitly supported role', () {
    final account = WorkbenchAccount();
    for (final role in [null, 'viewer', 'unexpected', 'owner', 'operator']) {
      account.activeWorkspace = {'id': 1, 'role': role};
      expect(account.canEdit, role == 'owner' || role == 'operator');
    }
    account.dispose();
  });
  for (final locale in ['zh', 'en']) {
    testWidgets('narrow $locale dashboard renders correct date counts', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final font = File('assets/fonts/NotoSansSC.ttf');
      final loader = FontLoader('EvidenceFont')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await iconLoader.load();
      final store = AppStore()
        ..ready = true
        ..preferences = {'reduceMotion': true, 'haptic': false};
      addTearDown(store.dispose);
      final routes = RouteCapture();
      final now = DateTime(2026, 10, 23, 12);
      final bounds = cloudTodayBounds(now);
      final start = DateTime.parse(bounds['updated_from']!);
      final account = WorkbenchAccount()..restoring = false;
      addTearDown(account.dispose);
      account.activeWorkspace = {'id': 1, 'role': 'viewer'};
      account.jobs = [
        for (var i = 0; i < 4; i++)
          {
            'id': 'job-$i',
            'part_name': 'Bracket $i',
            'status': i == 3 ? 'closed' : 'inspection',
            'updated_at': start
                .add(Duration(hours: i == 0 ? -1 : i))
                .toIso8601String(),
          },
      ];
      account.notifications = [
        {
          'task_id': 'job-1',
          'part_name': 'Bracket · first inspection',
          'status': 'inspection',
          'reinspection': false,
        },
        {
          'task_id': 'job-2',
          'part_name': 'Bracket · reinspection',
          'status': 'inspection',
          'reinspection': true,
        },
        {
          'task_id': 'job-4',
          'part_name': 'Bracket · surface issue',
          'status': 'exception',
        },
      ];
      account.metrics = {
        'trend': [
          for (var i = 0; i < 7; i++)
            {'day': '2026-10-${17 + i}', 'passed': i, 'inspected': i + 1},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppScope(store: store, child: child!),
          navigatorObservers: [routes],
          locale: Locale(locale),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ThemeData(fontFamily: 'EvidenceFont'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CloudWorkbenchSummary(account: account, now: now),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = locale == 'en' ? 'Awaiting inspection today' : '今日待检';
      expect(find.text(label), findsOneWidget);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/workbench-batch/png/60-workbench-$locale-desktop-render.png',
        ),
      );
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Bracket · first inspection'), findsOneWidget);
      expect(find.text('Bracket · reinspection'), findsNothing);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          '../docs/product/linesight/acceptance/workbench-batch/png/61-todo-$locale-desktop-render.png',
        ),
      );
      await tester.tap(find.text(label));
      final destination =
          (routes.latest as PageRouteBuilder).pageBuilder(
                tester.element(find.byType(Scaffold)),
                const AlwaysStoppedAnimation<double>(1),
                const AlwaysStoppedAnimation<double>(0),
              )
              as CloudTaskListPage;
      expect(destination.status, 'inspection');
      expect(destination.filters, bounds);
      final cards = tester.widgetList<StatCard>(find.byType(StatCard)).toList();
      expect(cards.map((c) => c.value), ['2', '0', '1']);
      expect(
        bounds['updated_to'],
        start.add(const Duration(days: 1)).toIso8601String(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

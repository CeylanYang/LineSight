import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/screens/cloud_tasks.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'cloud_assignment_test.dart' show AssignmentAccount;

void main() {
  late AssignmentAccount account;
  late AppStore store;
  setUp(() {
    account = AssignmentAccount();
    account.job['status'] = 'exception';
    account.job['exceptions'] = [
      {
        'id': 42,
        'status': 'open',
        'note': 'Diameter outside tolerance',
        'category': 'dimension',
        'severity': 'major',
        'assignee': 'Alice',
      },
    ];
    store = AppStore()
      ..ready = true
      ..preferences = {'reduceMotion': true, 'haptic': false, 'glass': false};
  });
  tearDown(() {
    account.dispose();
    store.dispose();
  });
  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: appTheme(false),
        builder: (context, child) => AppScope(
          store: store,
          child: CloudScope(account: account, child: child!),
        ),
        home: CloudTaskPage(job: account.job, workspaceId: 1),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'top issue action reveals section and actionable issue on a small phone',
    (tester) async {
      await show(tester);
      final tabs = find.byType(SegmentedButton<int>);
      expect(tester.getTopLeft(tabs).dy, greaterThan(500));
      final action = find.widgetWithText(FilledButton, '处理异常').first;
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(tester.widget<SegmentedButton<int>>(tabs).selected, {2});
      expect(tester.getTopLeft(tabs).dy, lessThan(350));
      expect(
        find.text('Diameter outside tolerance').hitTestable(),
        findsOneWidget,
      );
      expect(account.posts, isEmpty);
    },
  );
  testWidgets(
    'manual section selection moves content into view without business writes',
    (tester) async {
      await show(tester);
      final tabs = find.byType(SegmentedButton<int>);
      await tester.ensureVisible(tabs);
      await tester.pumpAndSettle();
      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
      expect(tester.widget<SegmentedButton<int>>(tabs).selected, {3});
      expect(tester.getTopLeft(tabs).dy, lessThan(350));
      expect(account.posts, isEmpty);
    },
  );
  testWidgets('system reduced animations makes section positioning immediate', (
    tester,
  ) async {
    store.preferences['reduceMotion'] = false;
    await show(tester);
    final context = tester.element(find.byType(CloudTaskPage));
    final media = MediaQuery.of(context);
    await tester.pumpWidget(
      AppScope(
        store: store,
        child: CloudScope(
          account: account,
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: appTheme(false),
            home: MediaQuery(
              data: media.copyWith(disableAnimations: true),
              child: CloudTaskPage(job: account.job, workspaceId: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.widgetWithText(FilledButton, '处理异常').first;
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(SegmentedButton<int>)).dy,
      lessThan(350),
    );
    expect(account.posts, isEmpty);
  });
}

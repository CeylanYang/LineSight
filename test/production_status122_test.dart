import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';
import 'package:linesight_flutter/ui.dart';
import 'package:linesight_flutter/screens/production.dart';
import 'package:linesight_flutter/l10n_catalog.dart';

class StatusStore extends AppStore {
  int calls = 0;
  bool fail = true;
  Completer<void>? gate;
  @override
  Future<void> updateProductionJob(
    String id, {
    required String status,
    String? note,
  }) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('private sqlite diagnostic');
    data.jobs.firstWhere((j) => j.id == id).status = status;
    notifyListeners();
  }
}

ProductionJob job(String id, DateTime at) => ProductionJob(
  id: id,
  partName: id,
  printer: 'A1',
  quantity: '1',
  status: 'queued',
  note: '',
  createdAt: at,
);
void main() {
  for (final language in ['zh', 'en']) {
    testWidgets('$language task status preserves failure and retries once', (
      t,
    ) async {
      final s = StatusStore()
        ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
      s.data.jobs = [job('first', DateTime(2026, 10, 25))];
      addTearDown(s.dispose);
      String label(String v) => language == 'en' ? englishMessages[v] ?? v : v;
      await mount(t, s, language);
      await t.ensureVisible(find.text(label('开始打印')));
      s.gate = Completer<void>();
      await t.tap(find.text(label('开始打印')));
      await t.pump();
      expect(
        t.widget<OutlinedButton>(find.byType(OutlinedButton).first).onPressed,
        isNull,
      );
      s.data.jobs.add(job('second', DateTime(2026, 10, 26)));
      s.notifyListeners();
      await t.pump();
      final original = find.byKey(const ValueKey('production-job/first'));
      expect(
        t
            .widget<OutlinedButton>(
              find.descendant(
                of: original,
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(s.calls, 1);
      s.gate!.complete();
      await t.pumpAndSettle();
      expect(find.text(label('保存失败，请重试')), findsOneWidget);
      expect(find.textContaining('sqlite'), findsNothing);
      expect(s.data.jobs.first.status, 'queued');
      s.fail = false;
      final button = find.descendant(
        of: original,
        matching: find.byType(OutlinedButton),
      );
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
      expect(s.calls, 2);
      expect(s.data.jobs.first.status, 'printing');
      expect(find.text(label('打印完成，送检')), findsOneWidget);
    });
  }
  testWidgets('late failure after identity change does not show old error', (
    t,
  ) async {
    final s = StatusStore()
      ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
    s.data.jobs = [job('first', DateTime(2026, 10, 25))];
    s.gate = Completer<void>();
    addTearDown(s.dispose);
    await mount(t, s, 'zh');
    await t.ensureVisible(find.text('开始打印'));
    await t.tap(find.text('开始打印'));
    await t.pump();
    s.user = const LocalUser('u2', 'other', '小周', 'operator', true);
    s.notifyListeners();
    s.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('保存失败，请重试'), findsNothing);
    expect(s.calls, 1);
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
        home: const ProductionPage(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

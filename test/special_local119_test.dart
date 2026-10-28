import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/main.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';

class MemoryProductionStore extends AppStore {
  ProductionJob? created;
  @override
  Future<void> createProductionJob(ProductionJob job) async {
    created = job;
    data.jobs.add(job);
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'local special home creates production job directly and opens records',
    (t) async {
      final store = MemoryProductionStore()
        ..ready = true
        ..preferences = {
          'specialEdition': true,
          'reduceMotion': true,
          'haptics': false,
          'glass': false,
        }
        ..user = const LocalUser('u1', 'tester', '小林', 'operator', true);
      addTearDown(store.dispose);
      await t.pumpWidget(LineSightApp(store: store, showBrandReveal: false));
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      if (find.byKey(const ValueKey('skip-login-ad')).evaluate().isNotEmpty) {
        await t.tap(find.byKey(const ValueKey('skip-login-ad')));
        await t.pump(const Duration(milliseconds: 700));
        await t.pumpAndSettle();
      }
      await t.ensureVisible(find.text('新建任务'));
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      await t.tap(find.text('新建任务'));
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(find.text('新建生产任务'), findsOneWidget);
      expect(store.created, isNull);
      await t.enterText(find.byType(TextFormField).first, '定位工装连接板');
      await t.enterText(find.byType(TextFormField).last, '12');
      await t.tap(find.text('创建任务'));
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(store.created?.partName, '定位工装连接板');
      expect(store.created?.quantity, '12');
      expect(store.created?.status, 'queued');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('记录查询'), findsOneWidget);
      expect(find.text('扫码追溯'), findsNothing);
      await t.ensureVisible(find.text('记录查询'));
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      await t.tap(find.text('记录查询'));
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();
      expect(t.widget<IndexedStack>(find.byType(IndexedStack).first).index, 2);
    },
  );
}

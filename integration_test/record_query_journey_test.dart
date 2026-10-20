import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/record_query.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'committed review, archive, restore and sessions refresh queries',
    (tester) async {
      final s = AppStore();
      await s.init(
        path: '${await getDatabasesPath()}/record-query-${uid()}.db',
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await s.db.close();
        s.dispose();
      });
      await s.register('query.admin', '检索管理员', 'Query-password-42');
      await s.login('query.admin', 'Query-password-42');
      final cache = RecordQueryCache(), pendingCache = RecordQueryCache();
      RecordQueryResult read({bool archived = false}) => cache.resolve(
        workspace: s.data,
        revision: s.revision,
        session: s.session,
        query: '唯一检索复核依据',
        archived: archived,
      );
      RecordQueryResult pending() => pendingCache.resolve(
        workspace: s.data,
        revision: s.revision,
        session: s.session,
        status: 'pending',
      );
      final id = s.pending.first.id;
      expect(read().records, isEmpty);
      expect(pending().ids, contains(id));
      await s.review(id, 'pass', '唯一检索复核依据');
      expect(read().ids, {id});
      expect(pending().ids, isNot(contains(id)));
      final beforePreference = read();
      await s.preference('dark', true);
      expect(read(), same(beforePreference));
      expect(s.captureCsv(read().records).records.single.id, id);

      await s.archive({id}, true);
      expect(read().records, isEmpty);
      expect(read(archived: true).ids, {id});
      read();
      await s.archive({id}, false);
      expect(read().ids, {id});
      final beforeSession = read();
      s.lock();
      await s.login('query.admin', 'Query-password-42');
      expect(read(), isNot(same(beforeSession)));
      expect(read().ids, {id});
      await s.restore(
        Workspace.seed(examples: false),
        expectedRevision: s.revision,
      );
      expect(read().records, isEmpty);
      await s.undoRestore();
      expect(read().ids, {id});
      final beforeSimulation = read();
      await s.simulate('s1');
      expect(read(), isNot(same(beforeSimulation)));
      expect(read().ids, {id});
    },
  );

  testWidgets('cached local-day filters include 23 and 25 hour New York days', (
    tester,
  ) async {
    // Run only on the disposable emulator in America/New_York.
    expect(DateTime(2026, 1).timeZoneOffset, const Duration(hours: -5));
    expect(DateTime(2026, 7).timeZoneOffset, const Duration(hours: -4));
    final w = Workspace.seed(examples: false), cache = RecordQueryCache();
    for (final (date, hours) in [
      (DateTime(2026, 3, 8), 23),
      (DateTime(2026, 11, 1), 25),
    ]) {
      final next = localDay(date, 1);
      expect(next.difference(date).inHours, hours);
      final instants = [
        date.subtract(const Duration(microseconds: 1)),
        date,
        next.subtract(const Duration(microseconds: 1)),
        next,
      ];
      w.inspections = List.generate(
        4,
        (i) => Inspection(
          id: 'boundary-$i',
          stationId: 's1',
          recipeName: '边界配方',
          serial: 'DAY-$i',
          at: instants[i].toUtc(),
          passed: true,
          defect: '',
          confidence: .99,
          operatorName: '测试员',
        ),
      );
      RecordQueryResult read(DateTime last) => cache.resolve(
        workspace: w,
        revision: 0,
        session: 0,
        firstDate: date,
        lastDate: last,
      );
      final result = read(date);
      expect(result.ids, {'boundary-1', 'boundary-2'});
      expect(result.records.map((r) => r.id), ['boundary-2', 'boundary-1']);
      expect(read(date.toUtc()), same(result));
      expect(read(next).ids, {'boundary-1', 'boundary-2', 'boundary-3'});
    }
  });
}

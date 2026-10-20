import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/record_query.dart';

Workspace fixture() =>
    Workspace.seed(examples: false)
      ..inspections = List.generate(
        24,
        (i) => Inspection(
          id: 'r$i',
          serial: 'SERIAL $i',
          stationId: 's${i % 3 + 1}',
          recipeName: '配方 Alpha',
          at: DateTime(2026, 10, 12 + i ~/ 8, i % 4),
          passed: i % 2 == 0,
          defect: i % 2 == 0 ? '' : '划痕',
          confidence: .98,
          operatorName: 'Operator',
          note: i % 3 == 0 ? 'Alpha  BETA\n质检 😀' : '中文备注',
          archived: i % 5 == 0,
          review: i % 7 == 0 ? 'pass' : (i % 7 == 1 ? 'reject' : null),
        ),
      );

// Keep the pre-cache algorithm as an independent compatibility oracle.
List<Inspection> original(
  Workspace w, {
  required String query,
  required String status,
  required String? stationId,
  required bool archived,
  required bool newest,
  required DateTime? firstDate,
  required DateTime? lastDate,
}) {
  final normalizedQuery = query.toLowerCase();
  return w.inspections.where((r) {
    return r.archived == archived &&
        (stationId == null || r.stationId == stationId) &&
        (firstDate == null || inLocalDateRange(r.at, firstDate, lastDate!)) &&
        (switch (status) {
          'pass' => r.finalPassed,
          'fail' => !r.finalPassed,
          'pending' => r.pending,
          _ => true,
        }) &&
        (normalizedQuery.isEmpty ||
            '${r.serial} ${r.id} ${r.defect} ${r.recipeName} ${r.note} ${r.operatorName}'
                .toLowerCase()
                .contains(normalizedQuery));
  }).toList()..sort(
    (a, b) => newest ? b.at.compareTo(a.at) : a.at.compareTo(b.at),
  );
}

void main() {
  test('all filters preserve original search, order and timestamp ties', () {
    final w = fixture(), cache = RecordQueryCache();
    for (final query in [
      '',
      ' ',
      '  ',
      'AlPhA',
      'ALPHA  beta\n质检',
      '😀',
      '中文备注 Operator',
      '1 r1 划痕',
      'r2  配方',
      'absent',
    ]) {
      for (final status in ['all', 'pass', 'fail', 'pending']) {
        for (final station in [null, 's1', 'absent']) {
          for (final archived in [false, true]) {
            for (final newest in [false, true]) {
              for (final dated in [false, true]) {
                final first = dated ? DateTime(2026, 10, 13, 18) : null;
                final last = dated ? DateTime(2026, 10, 14, 6) : null;
                final actual = cache.resolve(
                  workspace: w,
                  revision: 0,
                  session: 0,
                  query: query,
                  status: status,
                  stationId: station,
                  archived: archived,
                  newest: newest,
                  firstDate: first,
                  lastDate: last,
                );
                final expected = original(
                  w,
                  query: query,
                  status: status,
                  stationId: station,
                  archived: archived,
                  newest: newest,
                  firstDate: first,
                  lastDate: last,
                );
                expect(actual.records, orderedEquals(expected));
                expect(actual.ids, expected.map((r) => r.id).toSet());
              }
            }
          }
        }
      }
    }
  });

  test('reuses normalized queries, retains only the last result', () {
    final w = fixture(), cache = RecordQueryCache();
    RecordQueryResult read(String query) =>
        cache.resolve(workspace: w, revision: 0, session: 0, query: query);
    final first = read('AlPhA');
    expect(read('alpha'), same(first));
    expect(read('ALPHA'), same(first));
    final spaced = read('alpha ');
    expect(spaced, isNot(same(first)));
    expect(read('AlPhA'), isNot(same(first)));
    expect(() => first.records.clear(), throwsUnsupportedError);
    expect(() => first.ids.clear(), throwsUnsupportedError);
    expect(
      first.records.first,
      same(w.inspections.firstWhere((r) => r.id == first.records.first.id)),
    );
  });

  test('identity, length, revision and session invalidate independently', () {
    var w = fixture();
    final cache = RecordQueryCache();
    var revision = 0, session = 0;
    RecordQueryResult read() =>
        cache.resolve(workspace: w, revision: revision, session: session);
    var previous = read();
    void changed() {
      final next = read();
      expect(next, isNot(same(previous)));
      expect(read(), same(next));
      previous = next;
    }

    revision++;
    changed();
    session++;
    changed();
    w.inspections = List.of(w.inspections);
    changed();
    w.inspections.removeLast();
    changed();
    // Same inspection list, new workspace (e.g. initialization/replacement).
    w = Workspace.seed(examples: false)..inspections = w.inspections;
    changed();
  });

  test('in-place review, note edits, archive and reordering need revision', () {
    final w = fixture(), cache = RecordQueryCache();
    var revision = 0;
    RecordQueryResult read({String status = 'all', String query = ''}) =>
        cache.resolve(
          workspace: w,
          revision: revision,
          session: 0,
          status: status,
          query: query,
        );
    final row = w.inspections[3];
    expect(read(status: 'pending').ids, contains(row.id));
    row.review = 'pass';
    revision++;
    expect(read(status: 'pending').ids, isNot(contains(row.id)));
    expect(read(status: 'pass').ids, contains(row.id));
    row.note = 'new unique note';
    revision++;
    expect(read(query: 'unique').ids, {row.id});
    row.note = 'changed';
    revision++;
    expect(read(query: 'unique').records, isEmpty);
    final beforeArchive = read();
    row.archived = true;
    revision++;
    expect(read().ids, isNot(contains(row.id)));
    expect(beforeArchive.ids, contains(row.id));
    row.archived = false;
    revision++;
    expect(read().ids, contains(row.id));
    w.inspections.setAll(0, w.inspections.reversed.toList());
    revision++;
    expect(
      read().records,
      original(
        w,
        query: '',
        status: 'all',
        stationId: null,
        archived: false,
        newest: true,
        firstDate: null,
        lastDate: null,
      ),
    );
  });

  test('calendar boundaries are inclusive start and exclusive next day', () {
    final w = fixture(), cache = RecordQueryCache();
    final start = DateTime(2026, 3, 8), end = DateTime(2026, 3, 9);
    w.inspections = w.inspections.take(4).toList();
    final instants = [
      start.subtract(const Duration(microseconds: 1)),
      start,
      end.subtract(const Duration(microseconds: 1)),
      end,
    ];
    for (var i = 0; i < 4; i++) {
      w.inspections[i]
        ..at = instants[i].toUtc()
        ..archived = false;
    }
    RecordQueryResult read(DateTime first, DateTime last) => cache.resolve(
      workspace: w,
      revision: 0,
      session: 0,
      firstDate: first,
      lastDate: last,
    );
    final result = read(start, start);
    expect(result.ids, {'r1', 'r2'});
    expect(read(DateTime(2026, 3, 8, 12), start.toUtc()), same(result));
    expect(read(start, end).ids, {'r1', 'r2', 'r3'});
    expect(read(end, end).ids, {'r3'});
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';

void main() {
  test(
    'offsets describe one instant and serialize canonically at microsecond precision',
    () {
      final utc = parseInstant('2026-10-14T00:15:42.123456Z');
      for (final source in [
        '2026-10-14T08:15:42.123456+08:00',
        '2026-10-13T20:15:42.123456-0400',
        '2026-10-14T05:45:42.123456+05:30',
      ]) {
        expect(parseInstant(source), utc);
        expect(parseInstant(source).isUtc, isTrue);
      }
      expect(instantJson(utc), '2026-10-14T00:15:42.123456Z');
      expect(utcOffsetLabel(-210), 'UTC-03:30');
      expect(utcOffsetLabel(345), 'UTC+05:45');
    },
  );

  test(
    'overflowing dates, invalid offsets and lossy fractions are rejected',
    () {
      for (final value in [
        '2026-02-29T00:00:00Z',
        '2026-01-32T00:00:00Z',
        '2026-01-01T24:00:00Z',
        '2026-01-01T00:60:00Z',
        '2026-01-01T00:00:60Z',
        '2026-01-01T00:00:00+14:01',
        '2026-01-01T00:00:00+08:60',
        '2026-01-01T00:00:00.1234567Z',
        '0001-01-01T00:00:00+14:00',
        '9999-12-31T23:59:59-14:00',
        '2026-01-01',
        'invalid',
      ]) {
        expect(() => parseInstant(value), throwsFormatException, reason: value);
      }
      expect(parseInstant('2024-02-29T12:30:00Z').day, 29);
    },
  );

  test('legacy choice can be changed repeatedly using original strings', () {
    final raw = Workspace.seed().toJson();
    final rows = raw['inspections'] as List;
    rows.first['at'] = '2026-10-14T08:00:00.000';
    rows.first['reviewedAt'] = '2026-10-14T09:00:00.000';
    rows[1]['at'] = '2026-10-14T08:00:00+08:00';
    final text = jsonEncode({
      'app': 'LineSight',
      'schema': 1,
      'exportedAt': '2026-10-14T10:00:00.000',
      'workspace': raw,
    });
    final pending = BackupDocument.parse(text);
    expect(pending.legacyTimeCount, 3);
    expect(pending.readyToRestore, isFalse);
    expect(() => AppStore().parseBackup(text), throwsFormatException);
    final china = pending.resolveLegacyTimes(const LegacyTimeChoice.fixed(480));
    expect(china.readyToRestore, isTrue);
    expect(china.workspace.inspections.first.at, DateTime.utc(2026, 10, 14));
    expect(
      china.workspace.inspections.first.reviewedAt,
      DateTime.utc(2026, 10, 14, 1),
    );
    expect(china.exportedAt, DateTime.utc(2026, 10, 14, 2));
    final nepal = china.resolveLegacyTimes(const LegacyTimeChoice.fixed(345));
    expect(
      nepal.workspace.inspections.first.at,
      DateTime.utc(2026, 10, 14, 2, 15),
    );
    expect(
      nepal.workspace.inspections[1].at,
      china.workspace.inspections[1].at,
    );
    expect(
      nepal
          .resolveLegacyTimes(const LegacyTimeChoice.fixed(480))
          .workspace
          .toJson(),
      china.workspace.toJson(),
    );
    expect(
      BackupDocument.parse(
        BackupDocument.encode(china.workspace),
      ).legacyTimeCount,
      0,
    );
  });

  test(
    'equivalent timestamp notation creates no restore differences or audit conflicts',
    () {
      final w = Workspace.seed();
      w.inspections.first.at = DateTime.utc(2026, 10, 14);
      w.audits.add(
        AuditEntry('a', '人', '动作', '描述', DateTime.utc(2026, 10, 14)),
      );
      final j = w.toJson();
      j['inspections'][0]['at'] = '2026-10-14T08:00:00+08:00';
      j['audits'][0]['at'] = '2026-10-13T20:00:00-04:00';
      final diff = RestoreComparison(w, Workspace.fromJson(j));
      expect(diff.changes, isEmpty);
      expect(diff.duplicateAudits, 1);
      expect(diff.conflictingAudits, 0);
    },
  );

  test('local display and inclusive dates use instant boundaries', () {
    final start = DateTime(2026, 10, 14), next = DateTime(2026, 10, 15);
    expect(stamp(start.toUtc()), '2026-10-14 00:00');
    expect(sameLocalDay(start.toUtc(), start), isTrue);
    expect(inLocalDateRange(start.toUtc(), start, start), isTrue);
    expect(
      inLocalDateRange(
        next.subtract(const Duration(microseconds: 1)).toUtc(),
        start,
        start,
      ),
      isTrue,
    );
    expect(inLocalDateRange(next.toUtc(), start, start), isFalse);
    expect(
      inLocalDateRange(
        start.subtract(const Duration(microseconds: 1)),
        start,
        start,
      ),
      isFalse,
    );
    expect(localDay(DateTime(2024, 3, 1), -1), DateTime(2024, 2, 29));
    expect(localDay(DateTime(2026, 12, 31), 1), DateTime(2027));
  });

  test('raw time archive round trip preserves exact original values', () {
    final raw = jsonEncode(Workspace.seed().toJson()).replaceAll('Z"', '"');
    final archive = TimeMigrationArchive(
      id: 'a',
      capturedAt: instantJson(DateTime.now()),
      zoneName: 'CST',
      offsetMinutes: 480,
      count: 96,
      originals: {'workspace': raw},
    );
    final copy = TimeMigrationArchive.fromJson(
      jsonDecode(jsonEncode(archive.toJson())),
    );
    expect(copy.originals['workspace'], raw);
    expect(
      BackupDocument.parse(copy.backupSource('workspace')).readyToRestore,
      isFalse,
    );
    expect(() => copy.backupSource('accounts'), throwsStateError);
    expect(
      () => copy.originals['workspace'] = 'changed',
      throwsUnsupportedError,
    );
  });

  test('CSV UTC headings match canonical values', () {
    final s = AppStore()
      ..ready = true
      ..user = const LocalUser('a', 'a', '人', 'admin', true);
    final r = Workspace.seed().inspections.first;
    r.at = parseInstant('2026-10-14T08:00:00+08:00');
    r.reviewedAt = parseInstant('2026-10-14T09:00:00+08:00');
    final csv = s.csv([r]);
    expect(csv, contains('检测时间（UTC）'));
    expect(csv, contains('复核时间（UTC）'));
    expect(csv, contains('2026-10-14T00:00:00.000Z'));
    expect(csv, contains('2026-10-14T01:00:00.000Z'));
  });
}

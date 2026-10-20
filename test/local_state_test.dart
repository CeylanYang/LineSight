import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/local_state.dart';
import 'package:linesight_flutter/models.dart';

List<Map<String, Object?>> rows(Map<String, String> values) => [
  for (final entry in values.entries) {'key': entry.key, 'value': entry.value},
];

Map<String, String> fixture({bool legacy = false}) {
  final workspace = Workspace.seed();
  final json = workspace.toJson();
  json['inspections'][0]['at'] = legacy
      ? '2026-10-14T09:12:13.123456'
      : '2026-10-14T09:12:13.123456+08:00';
  json['futureField'] = {'keep': '原样保留'};
  final metadata = RestorePointInfo.capture(workspace, '管理员').toJson();
  final receipt = BackupReceipt(
    '管理员',
    'operation',
    DateTime.utc(2026),
    96,
  ).toJson();
  if (legacy) {
    metadata['createdAt'] = '2026-10-14T09:13:00';
    receipt['savedAt'] = '2026-10-14T09:14:00';
  }
  return {
    'workspace': jsonEncode(json),
    'restorePoint': jsonEncode(json),
    'restorePointMeta': jsonEncode(metadata),
    'backupReceipt': jsonEncode(receipt),
    'preferences': '{"dark":true,"futureSetting":[1,2]}',
    'unused-key': 'unrecognized data is not parsed or rewritten',
  };
}

void main() {
  test('canonical state validates once and requires no migration writes', () {
    final source = fixture();
    final before = Map.of(source);
    final result = decodeLocalState(rows(source));
    expect(
      result.workspace.inspections.first.at,
      DateTime.utc(2026, 10, 14, 1, 12, 13, 123, 456),
    );
    expect(
      result.workspace.toJson(),
      Workspace.fromJson(jsonDecode(source['workspace']!)).toJson(),
    );
    expect(
      result.restorePoint!.toJson(),
      jsonDecode(source['restorePointMeta']!),
    );
    expect(result.lastBackup!.toJson(), jsonDecode(source['backupReceipt']!));
    expect(result.preferences, jsonDecode(source['preferences']!));
    expect(result.timeArchives, isEmpty);
    expect(result.migrationWrites, isEmpty);
    expect(source, before);
  });

  test('worker returns sendable complete startup state', () async {
    final source = fixture();
    final result = await compute(decodeLocalState, rows(source));
    expect(
      result.workspace.toJson(),
      decodeLocalState(rows(source)).workspace.toJson(),
    );
    expect(result.restorePoint!.records, 96);
    expect(result.migrationWrites, isEmpty);
  });

  test(
    'legacy migration preserves exact sources and unknown fields; reopen is stable',
    () {
      final source = fixture(legacy: true);
      final before = Map.of(source);
      final result = decodeLocalState(rows(source));
      expect(source, before);
      expect(result.timeArchives.single.count, 4);
      for (final key in [
        'workspace',
        'restorePoint',
        'restorePointMeta',
        'backupReceipt',
      ]) {
        expect(result.timeArchives.single.originals[key], source[key]);
        expect(result.migrationWrites, contains(key));
      }
      expect(result.migrationWrites.keys.toSet(), {
        'workspace',
        'restorePoint',
        'restorePointMeta',
        'backupReceipt',
        'timeArchives',
      });
      expect(jsonDecode(result.migrationWrites['workspace']!)['futureField'], {
        'keep': '原样保留',
      });
      expect(
        jsonDecode(
          result.migrationWrites['workspace']!,
        )['inspections'][0]['at'],
        endsWith('Z'),
      );
      expect(
        result.workspace.inspections.first.at,
        DateTime(2026, 10, 14, 9, 12, 13, 123, 456).toUtc(),
      );
      final reopened = decodeLocalState(
        rows({...source, ...result.migrationWrites}),
      );
      expect(reopened.migrationWrites, isEmpty);
      expect(
        reopened.timeArchives.single.toJson(),
        result.timeArchives.single.toJson(),
      );
      expect(reopened.workspace.toJson(), result.workspace.toJson());
      expect(reopened.restorePoint!.toJson(), result.restorePoint!.toJson());
      expect(reopened.lastBackup!.toJson(), result.lastBackup!.toJson());
    },
  );

  test(
    'restore point without metadata uses already validated point summary',
    () {
      final source = fixture()..remove('restorePointMeta');
      final result = decodeLocalState(rows(source));
      expect(result.restorePoint!.id, 'legacy');
      expect(result.restorePoint!.records, 96);
      expect(result.restorePoint!.createdAt, isNull);
      expect(result.migrationWrites, isEmpty);
      source.remove('restorePoint');
      expect(decodeLocalState(rows(source)).restorePoint, isNull);
    },
  );

  test(
    'invalid workspace, undo, metadata, receipts, archives or settings reject startup',
    () {
      final variants = <Map<String, String>>[
        fixture()..remove('workspace'),
        {...fixture(), 'workspace': '{'},
        {...fixture(), 'restorePoint': '{"recipes":[]}'},
        {...fixture(), 'restorePointMeta': '{}'},
        {...fixture(), 'backupReceipt': '{}'},
        {...fixture(), 'timeArchives': '[{}]'},
        {...fixture(legacy: true), 'preferences': '[]'},
      ];
      for (final source in variants) {
        final before = Map.of(source);
        expect(() => decodeLocalState(rows(source)), throwsA(anything));
        expect(source, before);
      }
      final source = fixture();
      final point = jsonDecode(source['restorePoint']!);
      point['inspections'][0]['stationId'] = 'missing';
      source['restorePoint'] = jsonEncode(point);
      // Valid point metadata cannot hide an invalid full restore point.
      expect(() => decodeLocalState(rows(source)), throwsFormatException);
    },
  );

  test('preserved archive timestamp and timezone text are still checked', () {
    final source = fixture();
    source['timeArchives'] = jsonEncode([
      {
        'id': 'archive',
        'capturedAt': '2026-02-30T12:00:00Z',
        'zoneName': 'GMT',
        'offsetMinutes': 0,
        'count': 1,
        'originals': {'workspace': 'exact raw original'},
      },
    ]);
    expect(() => decodeLocalState(rows(source)), throwsFormatException);
    final invalid = jsonDecode(source['workspace']!);
    invalid['inspections'][0]['at'] = '2026-10-14T09:00:00+14:30';
    source.remove('timeArchives');
    source['workspace'] = jsonEncode(invalid);
    expect(() => decodeLocalState(rows(source)), throwsFormatException);
  });
}

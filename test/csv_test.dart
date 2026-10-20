import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/record_csv.dart';
import 'package:linesight_flutter/stream_backup.dart';
import '../test_support/csv_fixtures.dart';

CsvSnapshot snapshot(Workspace w) =>
    CsvSnapshot(w.inspections, {for (final s in w.stations) s.id: s.name});

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'linesight-csv-test-',
    ),
  );
  tearDown(() async {
    final resolved = await directory.resolveSymbolicLinks();
    final root = await Directory.systemTemp.resolveSymbolicLinks();
    expect(
      resolved.startsWith('$root${Platform.pathSeparator}linesight-csv-test-'),
      isTrue,
    );
    await directory.delete(recursive: true);
  });
  String path(String name) => '${directory.path}/$name';

  test(
    'CSV snapshot freezes scalar fields, station names and selection order',
    () {
      final w = csvFixture(count: 3, large: false);
      final selected = [w.inspections[2], w.inspections[0]];
      final names = {for (final s in w.stations) s.id: s.name};
      final frozen = CsvSnapshot(selected, names);
      final before = csvChunks(frozen).join();
      w.inspections[0].serial = 'changed';
      w.inspections[0].note = 'changed';
      w.inspections[2].archived = !w.inspections[2].archived;
      names.clear();
      selected.clear();
      expect(csvChunks(frozen).join(), before);
      expect(frozen.records.map((r) => r.id), ['csv-2', 'csv-0']);
      expect(frozen.targets.map((r) => r.id), ['csv-2', 'csv-0']);
      expect(() => frozen.records.clear(), throwsUnsupportedError);
      expect(() => frozen.records.first.values.clear(), throwsUnsupportedError);
    },
  );

  test(
    'CSV preserves BOM, all 15 fields, embedded delimiters and UTC precision',
    () async {
      final w = csvFixture(count: 1, large: false);
      w.stations.first.name = '工位甲';
      final r = w.inspections.first;
      r.serial = '=HYPERLINK("demo")';
      r.review = 'pass';
      r.reviewer = '复核员';
      r.reviewedAt = DateTime.parse('2026-10-14T09:02:03.004005+08:00');
      final archive = await writeRecordCsv(snapshot(w), path('one.csv'));
      final raw = await File(archive.path).readAsBytes();
      expect(raw.take(3), [239, 187, 191]);
      final text = utf8.decode(raw);
      expect(
        text,
        endsWith(
          '"csv-0","\'=HYPERLINK(""demo"")","工位甲",'
          '"2026-10-14T01:02:03.004Z","CSV 测试快照","PASS","","0.98",'
          '"pass","复核员","2026-10-14T01:02:03.004005Z",'
          '"一行,""引号""\r\n第二行 😀","测试操作员","true","true"',
        ),
      );
      expect(text.startsWith('"记录 ID","序列号","工位","检测时间（UTC）"'), isTrue);
      expect(text.endsWith('\r\n'), isFalse);
      expect(archive.bytes, raw.length);
      expect(archive.sha256, sha256.convert(raw).toString());
    },
  );

  test('spreadsheet formula protection includes leading whitespace', () {
    for (final text in [
      '=1+1',
      '+SUM(A1)',
      '-3',
      '@demo',
      '  =1',
      '\t+1',
      '\rtext',
      '\ntext',
      '\uFEFF=1',
      '\u00A0@demo',
    ]) {
      expect(csvCell(text), startsWith('"\''), reason: text);
    }
    expect(csvCell('ordinary, "quoted"'), '"ordinary, ""quoted"""');
    expect(csvCell('plain = text'), '"plain = text"');
  });

  test(
    'worker writes more than 20 MiB without losing rows or order',
    () async {
      final w = csvFixture();
      final task = ArchiveTask.csv(snapshot(w), path('large.csv'));
      final file = await task.result;
      expect(file.bytes, greaterThan(maxBackupBytes));
      expect(file.bytes, await File(file.path).length());
      expect(
        (await sha256.bind(File(file.path).openRead()).first).toString(),
        file.sha256,
      );
      var lines = 0;
      await for (final line in File(
        file.path,
      ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
        if (lines > 0) expect(line, startsWith('"csv-${lines - 1}",'));
        lines++;
      }
      expect(lines, 4001);
      expect(task.progress.value.fraction, 1);
      expect(task.progress.value.bytes, file.bytes);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'CSV limits and early, mid-write and completion cancellation clean files',
    () async {
      final small = snapshot(csvFixture(count: 3));
      await expectLater(
        writeRecordCsv(small, path('limit.csv'), byteLimit: 256),
        throwsFormatException,
      );
      expect(await File(path('limit.csv')).exists(), isFalse);
      for (final late in [false, true]) {
        final task = ArchiveTask.csv(small, path('cancel-$late.csv'));
        final result = expectLater(
          task.result,
          throwsA(isA<BackupCancelled>()),
        );
        if (late) {
          task.progress.addListener(() {
            if (task.progress.value.fraction == 1) task.cancel();
          });
        } else {
          task.cancel();
        }
        await result;
        expect(await File(path('cancel-$late.csv')).exists(), isFalse);
      }
      var cancelled = false;
      await expectLater(
        writeRecordCsv(
          snapshot(csvFixture(count: 300)),
          path('mid.csv'),
          report: (_, fraction, _) {
            if (fraction > 0) cancelled = true;
          },
          check: () {
            if (cancelled) throw const BackupCancelled();
          },
        ),
        throwsA(isA<BackupCancelled>()),
      );
      expect(await File(path('mid.csv')).exists(), isFalse);
    },
  );

  test(
    'empty CSV retains headings and invalid selections fail explicitly',
    () async {
      final w = Workspace.seed(examples: false);
      final file = await ArchiveTask.csv(snapshot(w), path('empty.csv')).result;
      final raw = await File(file.path).readAsBytes();
      expect(raw, utf8.encode(csvChunks(snapshot(w)).single));
      expect(csvColumns, hasLength(15));
      final r = csvFixture(count: 1).inspections.first;
      expect(() => CsvSnapshot([r], {}), throwsFormatException);
      expect(
        () => CsvSnapshot([r, r], {r.stationId: 'a'}),
        throwsFormatException,
      );
    },
  );
}

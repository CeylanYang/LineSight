import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/stream_backup.dart';

import '../test_support/workspace_fixtures.dart';

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'linesight-archive-test-',
    ),
  );
  tearDown(() async {
    // The target is the exact temporary directory issued by createTemp above.
    if (await directory.exists()) {
      final resolved = await directory.resolveSymbolicLinks();
      final root = await Directory.systemTemp.resolveSymbolicLinks();
      expect(
        resolved.startsWith(
          '$root${Platform.pathSeparator}linesight-archive-test-',
        ),
        isTrue,
      );
      await directory.delete(recursive: true);
    }
  });
  String path(String name) => '${directory.path}/$name';

  test(
    'streamed backup beyond 20 MB retains all objects, children and microseconds',
    () async {
      final w = archiveFixture(large: true);
      w.inspections.first.at = DateTime.utc(2026, 10, 14, 12, 1, 2, 3, 4);
      expect(() => BackupDocument.encode(w), throwsStateError);
      final archive = await ArchiveTask.write(w, path('large.lsb')).result;
      expect(archive.bytes, greaterThan(maxBackupBytes));
      expect(archive.bytes, await File(archive.path).length());
      expect(
        (await sha256.bind(File(archive.path).openRead()).first).toString(),
        archive.sha256,
      );
      final result = await ArchiveTask.read(archive.path).result;
      expect(result.format, 'LSB 2');
      expect(result.checksum, isNotNull);
      expect(result.workspace.toJson(), w.toJson());
      expect(result.bytes, archive.bytes);
      expect(result.readyToRestore, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'truncation, changed bytes and trailing content fail before restore',
    () async {
      final archive = await writeArchive(archiveFixture(), path('good.lsb'));
      final bytes = await File(archive.path).readAsBytes();
      for (final (name, bad) in [
        ('cut', bytes.sublist(0, bytes.length - 50)),
        ('tail', [...bytes, ...utf8.encode('{}\n')]),
        (
          'changed',
          utf8.encode(utf8.decode(bytes).replaceFirst('测试人员', '其他人员')),
        ),
        (
          'header',
          utf8.encode(utf8.decode(bytes).replaceFirst('BACKUP/2', 'BACKUP/9')),
        ),
      ]) {
        await File(path(name)).writeAsBytes(bad);
        await expectLater(
          readArchive(path(name)),
          throwsFormatException,
          reason: name,
        );
      }
    },
  );

  test(
    'even a recomputed checksum cannot hide count and ownership errors',
    () async {
      final archive = await writeArchive(archiveFixture(), path('good.lsb'));
      final text = await File(archive.path).readAsString();
      Future<void> reject(String name, String Function(String) edit) async {
        final lines = text.split('\n');
        lines.removeLast();
        lines.removeLast(); // Remove empty tail and checksum.
        final payload = utf8.encode('${edit(lines.join('\n'))}\n');
        final footer = jsonEncode({
          'type': 'checksum',
          'algorithm': 'SHA-256',
          'bytes': payload.length,
          'sha256': sha256.convert(payload).toString(),
        });
        await File(
          path(name),
        ).writeAsBytes([...payload, ...utf8.encode('$footer\n')]);
        await expectLater(
          readArchive(path(name)),
          throwsFormatException,
          reason: name,
        );
      }

      await reject(
        'count',
        (s) => s.replaceFirst('"inspection":96', '"inspection":95'),
      );
      await reject(
        'owner',
        (s) => s.replaceFirst('"auditId":"archive-0"', '"auditId":"other"'),
      );
      await reject(
        'time',
        (s) => s.replaceFirst(
          '2026-10-14T00:00:00.000Z',
          '2026-10-14T00:00:00.000',
        ),
      );
    },
  );

  test(
    'limits and cancellation remove incomplete output and preserve input',
    () async {
      final w = archiveFixture();
      await expectLater(
        writeArchive(w, path('small'), byteLimit: 256),
        throwsFormatException,
      );
      expect(await File(path('small')).exists(), isFalse);
      final job = ArchiveTask.write(
        archiveFixture(large: true),
        path('cancelled'),
      );
      final result = expectLater(job.result, throwsA(isA<BackupCancelled>()));
      job.cancel();
      await result;
      expect(await File(path('cancelled')).exists(), isFalse);
      final lateJob = ArchiveTask.write(w, path('cancelled-at-completion'));
      final lateResult = expectLater(
        lateJob.result,
        throwsA(isA<BackupCancelled>()),
      );
      lateJob.progress.addListener(() {
        if (lateJob.progress.value.fraction == 1) lateJob.cancel();
      });
      await lateResult;
      expect(await File(path('cancelled-at-completion')).exists(), isFalse);
      final archive = await writeArchive(w, path('good'));
      await expectLater(
        readArchive(archive.path, byteLimit: 256),
        throwsFormatException,
      );
      final read = ArchiveTask.read(archive.path);
      final cancelled = expectLater(
        read.result,
        throwsA(isA<BackupCancelled>()),
      );
      read.cancel();
      await cancelled;
      expect(await File(archive.path).length(), archive.bytes);
    },
  );

  test(
    'empty history remains a valid full workspace and old receipts load',
    () async {
      final w = Workspace.seed(examples: false);
      final file = await writeArchive(w, path('empty'));
      expect((await readArchive(file.path)).workspace.toJson(), w.toJson());
      final receipt = BackupReceipt.fromJson({
        'actor': 'a',
        'operationId': 'op',
        'savedAt': '2026-10-14T00:00:00Z',
        'records': 0,
      });
      expect(receipt.format, 'JSON');
      expect(receipt.bytes, isNull);
    },
  );
}

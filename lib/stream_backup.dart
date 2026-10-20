import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'backup.dart';
import 'models.dart';
import 'record_csv.dart';

const archiveMagic = 'LINESIGHT-BACKUP/2';
const maxArchiveLineBytes = 16 * 1024 * 1024;
const _sections = [
  'recipe',
  'station',
  'inspection',
  'audit',
  'target',
  'change',
];

class BackupCancelled implements Exception {
  const BackupCancelled();
}

class BackupProgress {
  final String message;
  final double fraction;
  final int bytes;
  const BackupProgress(this.message, this.fraction, this.bytes);
}

class PreparedArchive {
  final String path, sha256;
  final int bytes;
  const PreparedArchive(this.path, this.bytes, this.sha256);
}

class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

typedef BackupReporter =
    void Function(String message, double fraction, int bytes);

// File I/O and serialization run in a worker. Cancellation is cooperative and
// closes file handles before the task completes, including on Windows.
class ArchiveTask<T> {
  final progress = ValueNotifier(const BackupProgress('准备中…', 0, 0));
  final _completion = Completer<T>();
  final _messages = ReceivePort();
  SendPort? _control;
  bool _cancelled = false, _finished = false;
  Future<T> get result => _completion.future;
  bool get finished => _finished;

  ArchiveTask._(String mode, String path, Object? source) {
    _messages.listen((event) async {
      if (_finished) return;
      if (event is SendPort) {
        _control = event;
        if (_cancelled) event.send('cancel');
      } else if (event is List && event.first == 'progress') {
        progress.value = BackupProgress(event[1], event[2], event[3]);
      } else if (event is List && event.first == 'done') {
        _finish();
        if (_cancelled) {
          if (mode != 'read') {
            try {
              await File(path).delete();
            } on FileSystemException {
              /* Caller also owns scratch cleanup. */
            }
          }
          _completion.completeError(const BackupCancelled());
        } else {
          _completion.complete(event[1] as T);
        }
      } else if (event is List && event.first == 'cancelled') {
        _finish();
        _completion.completeError(const BackupCancelled());
      } else if (event is List && event.first == 'error') {
        _finish();
        _completion.completeError(FormatException(event[1] as String));
      } else {
        _finish();
        _completion.completeError(StateError('备份任务意外结束，请重试。'));
      }
    });
    Isolate.spawn(
          _archiveWorker,
          [mode, path, source, _messages.sendPort],
          onExit: _messages.sendPort,
          onError: _messages.sendPort,
        )
        .catchError((Object error) {
          if (!_finished) {
            _finish();
            _completion.completeError(error);
          }
          throw error;
        })
        .then<void>((_) {}, onError: (Object _) {});
  }

  static ArchiveTask<PreparedArchive> write(Workspace workspace, String path) =>
      ArchiveTask._('write', path, workspace);
  static ArchiveTask<BackupDocument> read(String path) =>
      ArchiveTask._('read', path, null);
  static ArchiveTask<PreparedArchive> csv(CsvSnapshot snapshot, String path) =>
      ArchiveTask._('csv', path, snapshot);

  void cancel() {
    if (_finished) return;
    _cancelled = true;
    _control?.send('cancel');
  }

  void _finish() {
    _finished = true;
    _messages.close();
  }
}

Future<void> _archiveWorker(List<Object?> input) async {
  final output = input[3] as SendPort, control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  output.send(control.sendPort);
  void check() {
    if (cancelled) throw const BackupCancelled();
  }

  void report(String text, double fraction, int bytes) =>
      output.send(['progress', text, fraction, bytes]);
  PreparedArchive? prepared;
  try {
    final Object result;
    if (input[0] == 'write') {
      result = prepared = await writeArchive(
        input[2] as Workspace,
        input[1] as String,
        check: check,
        report: report,
      );
    } else if (input[0] == 'csv') {
      result = prepared = await writeRecordCsv(
        input[2] as CsvSnapshot,
        input[1] as String,
        check: check,
        report: report,
      );
    } else {
      result = await readArchive(
        input[1] as String,
        check: check,
        report: report,
      );
    }
    check();
    output.send(['done', result]);
  } on BackupCancelled {
    // Cancellation can arrive during the final file close, after writeArchive's
    // last check. That successful output still belongs to this cancelled job.
    if (prepared != null) {
      try {
        await File(prepared.path).delete();
      } on FileSystemException {
        /* Caller also owns scratch cleanup. */
      }
    }
    output.send(['cancelled']);
  } catch (error) {
    output.send([
      'error',
      error is FormatException
          ? error.message
          : error is StateError
          ? error.message
          : '文件处理失败，请检查文件内容和可用空间。',
    ]);
  } finally {
    control.close();
  }
}

Future<PreparedArchive> writeRecordCsv(
  CsvSnapshot snapshot,
  String path, {
  VoidCallback? check,
  BackupReporter? report,
  int byteLimit = maxArchiveBytes,
}) async {
  check?.call();
  final output = await File(path).open(mode: FileMode.writeOnly);
  final digest = _DigestResult(), pending = BytesBuilder(copy: false);
  final hash = sha256.startChunkedConversion(digest);
  var bytes = 0, rows = -1, complete = false;
  try {
    report?.call('正在生成 CSV…', 0, 0);
    for (final chunk in csvChunks(snapshot)) {
      check?.call();
      final encoded = utf8.encode(chunk);
      if (encoded.length > maxArchiveLineBytes ||
          bytes + encoded.length > byteLimit) {
        throw const FormatException('CSV 超出文件限制，未生成完整文件。请缩小筛选范围后重试。');
      }
      bytes += encoded.length;
      hash.add(encoded);
      pending.add(encoded);
      rows++;
      if (pending.length >= 64 * 1024) {
        await output.writeFrom(pending.takeBytes());
      }
      if (rows % 128 == 0 || rows == snapshot.records.length) {
        report?.call(
          '正在生成 CSV · $rows / ${snapshot.records.length} 条',
          snapshot.records.isEmpty ? 1 : rows / snapshot.records.length,
          bytes,
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (pending.isNotEmpty) await output.writeFrom(pending.takeBytes());
    hash.close();
    await output.flush();
    check?.call();
    await output.close();
    check?.call();
    complete = true;
    return PreparedArchive(path, bytes, digest.value.toString());
  } finally {
    if (!complete) {
      try {
        await output.close();
      } on FileSystemException {
        /* Already closed. */
      }
      if (await File(path).exists()) await File(path).delete();
    }
  }
}

Map<String, int> _counts(Workspace w) => {
  'recipe': w.recipes.length,
  'station': w.stations.length,
  'inspection': w.inspections.length,
  'audit': w.audits.length,
  'target': w.audits.fold(0, (v, a) => v + a.targets.length),
  'change': w.audits.fold(0, (v, a) => v + a.changes.length),
};

Iterable<Json> _rows(Workspace w) sync* {
  for (final r in w.recipes) {
    yield {'type': 'recipe', 'value': r.toJson()};
  }
  for (final r in w.stations) {
    yield {'type': 'station', 'value': r.toJson()};
  }
  for (final r in w.inspections) {
    yield {'type': 'inspection', 'value': r.toJson()};
  }
  for (final a in w.audits) {
    yield {'type': 'audit', 'value': a.toJson(includeChildren: false)};
    for (final t in a.targets) {
      yield {'type': 'target', 'auditId': a.id, 'value': t.toJson()};
    }
    for (final c in a.changes) {
      yield {'type': 'change', 'auditId': a.id, 'value': c.toJson()};
    }
  }
}

Future<PreparedArchive> writeArchive(
  Workspace workspace,
  String path, {
  VoidCallback? check,
  BackupReporter? report,
  int byteLimit = maxArchiveBytes,
}) async {
  check?.call();
  workspace.validate();
  final counts = _counts(workspace),
      payloadDigest = _DigestResult(),
      fileDigest = _DigestResult();
  final payloadHash = sha256.startChunkedConversion(payloadDigest),
      fileHash = sha256.startChunkedConversion(fileDigest);
  final file = File(path);
  final output = await file.open(mode: FileMode.writeOnly);
  var bytes = 0, complete = false;
  try {
    Future<void> line(List<int> value, {bool payload = true}) async {
      check?.call();
      if (value.length > maxArchiveLineBytes) {
        throw const FormatException('单项内容超过 16 MB，未生成备份。请保留本机数据。');
      }
      final framed = Uint8List(value.length + 1)
        ..setRange(0, value.length, value);
      framed.last = 10;
      bytes += framed.length;
      if (bytes > byteLimit) {
        throw const FormatException('完整备份超过 256 MB，未保存文件。请保留本机数据。');
      }
      if (payload) payloadHash.add(framed);
      fileHash.add(framed);
      await output.writeFrom(framed);
    }

    await line(ascii.encode(archiveMagic));
    await line(
      JsonUtf8Encoder().convert({
        'type': 'manifest',
        'app': 'LineSight',
        'schema': 2,
        'exportedAt': instantJson(DateTime.now()),
        'counts': counts,
      }),
    );
    var done = 0;
    final total = counts.values.fold(0, (a, b) => a + b);
    for (final row in _rows(workspace)) {
      await line(JsonUtf8Encoder().convert(row));
      if (++done % 128 == 0) report?.call('正在准备完整备份…', done / total, bytes);
    }
    payloadHash.close();
    await line(
      JsonUtf8Encoder().convert({
        'type': 'checksum',
        'algorithm': 'SHA-256',
        'bytes': bytes,
        'sha256': payloadDigest.value.toString(),
      }),
      payload: false,
    );
    fileHash.close();
    await output.flush();
    check?.call();
    complete = true;
    report?.call('完整备份已准备，等待选择保存位置', 1, bytes);
    return PreparedArchive(path, bytes, fileDigest.value.toString());
  } finally {
    await output.close();
    if (!complete && await file.exists()) await file.delete();
  }
}

Future<bool> isArchiveFile(String path) async {
  final f = await File(path).open();
  try {
    return ascii.decode(
          await f.read(archiveMagic.length),
          allowInvalid: true,
        ) ==
        archiveMagic;
  } finally {
    await f.close();
  }
}

Future<BackupDocument> readArchive(
  String path, {
  VoidCallback? check,
  BackupReporter? report,
  int byteLimit = maxArchiveBytes,
}) async {
  final file = File(path), length = await File(path).length();
  if (length > byteLimit) throw const FormatException('完整备份不能超过 256 MB');
  final digest = _DigestResult();
  final payloadHash = sha256.startChunkedConversion(digest);
  final w = Workspace(recipes: [], stations: [], inspections: [], audits: []);
  final actual = {for (final key in _sections) key: 0};
  Map<String, int>? expected;
  DateTime? exportedAt;
  var lineNumber = 0, consumed = 0, phase = 0, finished = false;
  AuditEntry? pendingAudit;
  var targets = <AuditTarget>[], changes = <AuditChange>[];
  String? checksum;
  void finishAudit() {
    final a = pendingAudit;
    if (a == null) return;
    w.audits.add(
      AuditEntry(
        a.id,
        a.actor,
        a.action,
        a.detail,
        a.at,
        actorId: a.actorId,
        operationId: a.operationId,
        targets: targets,
        changes: changes,
      ),
    );
    pendingAudit = null;
    targets = [];
    changes = [];
  }

  void requireUtc(Json row, String key) {
    final v = row[key];
    if (v != null && (v is! String || !v.endsWith('Z'))) {
      throw const FormatException('完整备份中的时间必须带 UTC 标记');
    }
  }

  void parseLine(Uint8List bytes) {
    check?.call();
    if (finished) throw const FormatException('校验结尾之后还有多余内容');
    lineNumber++;
    if (lineNumber == 1) {
      if (utf8.decode(bytes) != archiveMagic) {
        throw const FormatException('不支持的完整备份格式');
      }
      payloadHash.add(bytes);
      payloadHash.add([10]);
      consumed += bytes.length + 1;
      return;
    }
    final row = Json.from(jsonDecode(utf8.decode(bytes))), type = row['type'];
    if (type == 'checksum') {
      if (expected == null ||
          row['algorithm'] != 'SHA-256' ||
          row['bytes'] != consumed) {
        throw const FormatException('备份长度校验失败，文件可能不完整');
      }
      payloadHash.close();
      if (row['sha256'] != digest.value.toString()) {
        throw const FormatException('备份完整性校验失败，文件已改变或损坏');
      }
      for (final key in _sections) {
        if (actual[key] != expected![key]) {
          throw const FormatException('备份数量不完整');
        }
      }
      finishAudit();
      finished = true;
      checksum = row['sha256'];
      consumed += bytes.length + 1;
      return;
    }
    payloadHash.add(bytes);
    payloadHash.add([10]);
    consumed += bytes.length + 1;
    if (lineNumber == 2) {
      if (type != 'manifest' ||
          row['app'] != 'LineSight' ||
          row['schema'] != 2) {
        throw const FormatException('不支持的完整备份版本');
      }
      requireUtc(row, 'exportedAt');
      exportedAt = parseInstant(row['exportedAt']);
      expected = Map<String, int>.from(row['counts']);
      const limits = {
        'recipe': 200,
        'station': 100,
        'inspection': 100000,
        'audit': 100000,
        'target': 10000000000,
        'change': 3000000,
      };
      if (expected!.length != limits.length ||
          limits.keys.any(
            (k) =>
                expected![k] == null ||
                expected![k]! < 0 ||
                expected![k]! > limits[k]!,
          )) {
        throw const FormatException('备份声明的数据规模无效');
      }
      return;
    }
    if (expected == null || !actual.containsKey(type)) {
      throw const FormatException('备份包含未知内容');
    }
    actual[type] = actual[type]! + 1;
    if (actual[type]! > expected![type]!) {
      throw const FormatException('备份数量与声明不一致');
    }
    final value = Json.from(row['value']);
    final rank = _sections.indexOf(type);
    if (rank < 4) {
      if (rank < phase) throw const FormatException('备份内容顺序无效');
      phase = rank;
      finishAudit();
    } else if (pendingAudit == null || row['auditId'] != pendingAudit!.id) {
      throw const FormatException('日志关联对象缺少对应的日志');
    }
    switch (type) {
      case 'recipe':
        w.recipes.add(Recipe.fromJson(value));
      case 'station':
        w.stations.add(Station.fromJson(value));
      case 'inspection':
        requireUtc(value, 'at');
        requireUtc(value, 'reviewedAt');
        w.inspections.add(Inspection.fromJson(value));
      case 'audit':
        if (value.containsKey('targets') || value.containsKey('changes')) {
          throw const FormatException('日志子项必须独立保存');
        }
        requireUtc(value, 'at');
        pendingAudit = AuditEntry.fromJson(value);
      case 'target':
        if (targets.length >= 100000 || changes.isNotEmpty) {
          throw const FormatException('日志关联数量或顺序无效');
        }
        targets.add(AuditTarget.fromJson(value));
      case 'change':
        if (changes.length >= 30) throw const FormatException('日志变更字段过多');
        changes.add(AuditChange.fromJson(value));
    }
  }

  final pending = BytesBuilder(copy: false);
  var read = 0;
  try {
    await for (final rawChunk in file.openRead()) {
      final chunk = rawChunk is Uint8List
          ? rawChunk
          : Uint8List.fromList(rawChunk);
      check?.call();
      read += chunk.length;
      if (read > byteLimit) throw const FormatException('完整备份不能超过 256 MB');
      var start = 0;
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] != 10) continue;
        if (pending.length + i - start > maxArchiveLineBytes) {
          throw const FormatException('备份单项内容过大');
        }
        pending.add(Uint8List.sublistView(chunk, start, i));
        parseLine(pending.takeBytes());
        start = i + 1;
      }
      if (pending.length + chunk.length - start > maxArchiveLineBytes) {
        throw const FormatException('备份单项内容过大');
      }
      pending.add(Uint8List.sublistView(chunk, start));
      report?.call(
        '正在读取并校验完整备份…',
        length == 0 ? 0 : (read / length).clamp(0, 1),
        read,
      );
      await Future<void>.delayed(Duration.zero);
    }
    if (pending.length != 0 || !finished) {
      throw const FormatException('备份缺少完整结尾，文件可能已截断');
    }
    check?.call();
    w.validate();
    return BackupDocument(
      w,
      bytes: consumed,
      exportedAt: exportedAt,
      format: 'LSB 2',
      checksum: checksum,
    );
  } on BackupCancelled {
    rethrow;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('备份内容不完整或字段格式无效');
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'backup.dart';
import 'models.dart';
import 'stream_backup.dart';

class RecoverySnapshot {
  final String id, actor, sourceName, format;
  final DateTime createdAt;
  final int records, bytes;
  const RecoverySnapshot({
    required this.id,
    required this.actor,
    required this.sourceName,
    required this.format,
    required this.createdAt,
    required this.records,
    required this.bytes,
  });
  factory RecoverySnapshot.fromRow(Map<String, Object?> row) =>
      RecoverySnapshot(
        id: row['id'] as String,
        actor: row['actor'] as String,
        sourceName: row['sourceName'] as String,
        format: row['format'] as String,
        createdAt: parseInstant(row['createdAt'] as String),
        records: row['records'] as int,
        bytes: row['bytes'] as int,
      );
}

class RecoveryStorage {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS recovery_snapshots '
      '(id TEXT PRIMARY KEY, createdAt TEXT NOT NULL, actor TEXT NOT NULL, '
      'actorId TEXT NOT NULL, sourceName TEXT NOT NULL, format TEXT NOT NULL, '
      'records INTEGER NOT NULL, bytes INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS recovery_state '
      '(snapshot TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, '
      'PRIMARY KEY (snapshot, key))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS recovery_chunks '
      '(snapshot TEXT NOT NULL, owner TEXT NOT NULL, part INTEGER NOT NULL, '
      'value TEXT NOT NULL, PRIMARY KEY (snapshot, owner, part))',
    );
  }

  // Copy the raw cells in SQLite, without decoding a damaged manifest or placing
  // oversized cells in an Android cursor. The caller owns the restore transaction.
  static Future<RecoverySnapshot> preserve(
    DatabaseExecutor tx, {
    required String id,
    required LocalUser actor,
    required String sourceName,
    required BackupDocument document,
  }) async {
    await tx.rawInsert(
      'INSERT INTO recovery_state (snapshot, key, value) SELECT ?, key, value FROM state',
      [id],
    );
    await tx.rawInsert(
      'INSERT INTO recovery_chunks (snapshot, owner, part, value) SELECT ?, owner, part, value FROM state_chunks',
      [id],
    );
    final size = Sqflite.firstIntValue(
      await tx.rawQuery(
        'SELECT COALESCE((SELECT SUM(length(CAST(value AS BLOB))) FROM recovery_state WHERE snapshot = ?), 0) '
        '+ COALESCE((SELECT SUM(length(CAST(value AS BLOB))) FROM recovery_chunks WHERE snapshot = ?), 0)',
        [id, id],
      ),
    )!;
    final row = <String, Object?>{
      'id': id,
      'createdAt': instantJson(DateTime.now()),
      'actor': actor.name,
      'actorId': actor.id,
      'sourceName': sourceName,
      'format': document.format,
      'records': document.workspace.inspections.length,
      'bytes': size,
    };
    await tx.insert('recovery_snapshots', row);
    return RecoverySnapshot.fromRow(row);
  }

  static Future<List<RecoverySnapshot>> history(DatabaseExecutor db) async =>
      (await db.query(
        'recovery_snapshots',
        orderBy: 'createdAt DESC, id DESC',
      )).map(RecoverySnapshot.fromRow).toList();
}

class _RecoveryDigest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

// Forensic export only. It preserves invalid raw values and orphaned chunks;
// it is deliberately a different format from an importable business backup.
Future<PreparedArchive> writeRecoveryOriginal(
  DatabaseExecutor db,
  String id,
  String path, {
  void Function()? check,
  BackupReporter? report,
  int byteLimit = maxArchiveBytes,
}) async {
  check?.call();
  final rows = await db.query(
    'recovery_snapshots',
    where: 'id = ?',
    whereArgs: [id],
  );
  if (rows.length != 1) throw StateError('恢复前原件不存在');
  final meta = rows.single;
  final file = await File(path).open(mode: FileMode.writeOnly);
  final payloadResult = _RecoveryDigest(), fileResult = _RecoveryDigest();
  final payloadHash = sha256.startChunkedConversion(payloadResult),
      fileHash = sha256.startChunkedConversion(fileResult);
  var bytes = 0, read = 0, complete = false;
  Future<void> line(Object value, {bool payload = true}) async {
    check?.call();
    final encoded = utf8.encode(
      '${value is String ? value : jsonEncode(value)}\n',
    );
    bytes += encoded.length;
    if (bytes > byteLimit) {
      throw const FormatException('恢复前原件超过 256 MB，请保留本机数据。');
    }
    if (payload) payloadHash.add(encoded);
    fileHash.add(encoded);
    await file.writeFrom(encoded);
  }

  try {
    await line('LINESIGHT-RECOVERY/1');
    await line({'type': 'manifest', 'snapshot': meta});
    for (final table in ['recovery_state', 'recovery_chunks']) {
      final chunked = table == 'recovery_chunks';
      final keys = await db.rawQuery(
        'SELECT ${chunked ? 'owner, part' : 'key'}, length(CAST(value AS BLOB)) AS bytes FROM $table WHERE snapshot = ? '
        'ORDER BY ${chunked ? 'owner, part' : 'key'}',
        [id],
      );
      for (final key in keys) {
        check?.call();
        final size = key['bytes'] as int;
        await line({
          'type': 'cell',
          'table': chunked ? 'chunks' : 'state',
          ...key,
        });
        var segment = 0;
        for (var offset = 1; offset <= size; offset += 64 * 1024) {
          check?.call();
          final slice = await db.rawQuery(
            'SELECT substr(CAST(value AS BLOB), ?, ?) AS value FROM $table WHERE snapshot = ? AND '
            '${chunked ? 'owner = ? AND part = ?' : 'key = ?'}',
            [
              offset,
              64 * 1024,
              id,
              if (chunked) ...[key['owner'], key['part']] else key['key'],
            ],
          );
          final value = slice.single['value'] as List<int>;
          await line({
            'type': 'segment',
            'index': segment++,
            'base64': base64Encode(value),
          });
          read += value.length;
          final total = meta['bytes'] as int;
          report?.call(
            '正在准备恢复前原件…',
            total == 0 ? 1 : (read / total).clamp(0, 1),
            bytes,
          );
        }
        await line({'type': 'endCell', 'segments': segment});
      }
    }
    payloadHash.close();
    await line({
      'type': 'checksum',
      'algorithm': 'SHA-256',
      'bytes': bytes,
      'sha256': payloadResult.value.toString(),
    }, payload: false);
    fileHash.close();
    await file.flush();
    check?.call();
    await file.close();
    check?.call();
    complete = true;
    return PreparedArchive(path, bytes, fileResult.value.toString());
  } finally {
    if (!complete) {
      try {
        await file.close();
      } on FileSystemException {
        /* Already closed. */
      }
      if (await File(path).exists()) await File(path).delete();
    }
  }
}

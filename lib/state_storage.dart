import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'state_codec.dart';
export 'state_codec.dart' show stateChunkUnits;

class StateStorage {
  static Future<void> create(DatabaseExecutor db) => db.execute(
    'CREATE TABLE IF NOT EXISTS state_chunks (owner TEXT NOT NULL, part INTEGER NOT NULL, value TEXT NOT NULL, PRIMARY KEY (owner, part))',
  );

  // The supplied transaction owns all batches: failure in any batch must roll
  // back the old chunks, new chunks, manifest and related business changes.
  static Future<void> write(
    DatabaseExecutor tx,
    String key,
    String value,
  ) async {
    final prepared = value.length > stateChunkUnits
        ? await compute(prepareStateValue, value)
        : prepareStateValue(value);
    var batch = tx.batch();
    batch.delete('state_chunks', where: 'owner = ?', whereArgs: [key]);
    var queued = 0;
    for (var part = 0; part < prepared.chunkEnds.length; part++) {
      batch.insert('state_chunks', {
        'owner': key,
        'part': part,
        'value': prepared.chunk(value, part),
      });
      if (++queued == 8) {
        await batch.commit(noResult: true, continueOnError: false);
        batch = tx.batch();
        queued = 0;
      }
    }
    batch.insert('state', {
      'key': key,
      'value': prepared.stored,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true, continueOnError: false);
  }

  static Future<String?> read(DatabaseExecutor tx, String key) async {
    final info = await tx.rawQuery(
      'SELECT length(value) AS chars FROM state WHERE key = ?',
      [key],
    );
    if (info.isEmpty) return null;
    final chars = info.single['chars'] as int;
    final raw = StringBuffer();
    // Legacy unchunked values use SQLite Unicode-code-point offsets so large
    // cells and supplementary characters do not cross cursor/surrogate limits.
    for (var start = 1; start <= chars; start += stateChunkUnits) {
      final part = await tx.rawQuery(
        'SELECT substr(value, ?, ?) AS part FROM state WHERE key = ?',
        [start, stateChunkUnits, key],
      );
      raw.write(part.single['part'] as String);
    }
    final value = raw.toString();
    if (!value.startsWith(stateChunkMarker)) return value;
    final manifest = StateChunkManifest.parse(value);
    final count = Sqflite.firstIntValue(
      await tx.rawQuery('SELECT count(*) FROM state_chunks WHERE owner = ?', [
        key,
      ]),
    );
    if (count != manifest.parts) throw const FormatException('本机数据分块缺失');
    final chunks = <String>[];
    var seen = 0;
    for (var first = 0; first < manifest.parts; first += 8) {
      final rows = await tx.query(
        'state_chunks',
        where: 'owner = ? AND part >= ? AND part < ?',
        whereArgs: [key, first, first + 8],
        orderBy: 'part',
      );
      for (final row in rows) {
        if (row['part'] != seen++) throw const FormatException('本机数据分块顺序无效');
        final chunk = row['value'] as String;
        if (chunk.length > stateChunkUnits) {
          throw const FormatException('本机数据分块过大');
        }
        chunks.add(chunk);
      }
    }
    if (seen != manifest.parts) throw const FormatException('本机数据分块缺失');
    return compute(assembleStateChunks, StateChunks(manifest, chunks));
  }

  static Future<List<Map<String, Object?>>> readAll(DatabaseExecutor tx) async {
    final keys = await tx.query('state', columns: ['key']);
    return [
      for (final row in keys)
        {'key': row['key'], 'value': await read(tx, row['key'] as String)},
    ];
  }

  static Future<void> remove(DatabaseExecutor tx, String key) async {
    await tx.delete('state_chunks', where: 'owner = ?', whereArgs: [key]);
    await tx.delete('state', where: 'key = ?', whereArgs: [key]);
  }
}

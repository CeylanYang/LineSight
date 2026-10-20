import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

// Keep each SQLite text cell below Android's cursor-window limit. Existing
// unchunked values are read with SQL substr(), including oversized legacy cells.
const stateChunkUnits = 128 * 1024;
const _marker = 'LineSightState/2:';

class _HashResult implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

class BaselineStateStorage {
  static Future<void> create(DatabaseExecutor db) => db.execute(
    'CREATE TABLE IF NOT EXISTS state_chunks (owner TEXT NOT NULL, part INTEGER NOT NULL, value TEXT NOT NULL, PRIMARY KEY (owner, part))',
  );

  // The caller supplies the business transaction so chunks, accounts, restore
  // points and their manifests either all commit or all roll back.
  static Future<void> write(
    DatabaseExecutor tx,
    String key,
    String value,
  ) async {
    await tx.delete('state_chunks', where: 'owner = ?', whereArgs: [key]);
    var stored = value;
    if (value.length > stateChunkUnits) {
      final result = _HashResult();
      final hash = sha256.startChunkedConversion(result);
      var index = 0, part = 0;
      while (index < value.length) {
        var end = (index + stateChunkUnits).clamp(0, value.length);
        if (end < value.length &&
            value.codeUnitAt(end - 1) >= 0xD800 &&
            value.codeUnitAt(end - 1) <= 0xDBFF) {
          end--;
        }
        final chunk = value.substring(index, end);
        hash.add(utf8.encode(chunk));
        await tx.insert('state_chunks', {
          'owner': key,
          'part': part++,
          'value': chunk,
        });
        index = end;
      }
      hash.close();
      stored =
          '$_marker${jsonEncode({'parts': part, 'units': value.length, 'sha256': result.digest.toString()})}';
    }
    await tx.insert('state', {
      'key': key,
      'value': stored,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> read(DatabaseExecutor tx, String key) async {
    final info = await tx.rawQuery(
      'SELECT length(value) AS chars FROM state WHERE key = ?',
      [key],
    );
    if (info.isEmpty) return null;
    final chars = info.single['chars'] as int;
    final raw = StringBuffer();
    // SQLite offsets count Unicode code points, never half a surrogate pair.
    for (var start = 1; start <= chars; start += stateChunkUnits) {
      final part = await tx.rawQuery(
        'SELECT substr(value, ?, ?) AS part FROM state WHERE key = ?',
        [start, stateChunkUnits, key],
      );
      raw.write(part.single['part'] as String);
    }
    final value = raw.toString();
    if (!value.startsWith(_marker)) return value;
    final manifest = jsonDecode(value.substring(_marker.length)) as Map;
    final parts = manifest['parts'] as int, units = manifest['units'] as int;
    if (parts < 1 || units < 1 || parts > units) {
      throw const FormatException('本机数据分块信息无效');
    }
    final count = Sqflite.firstIntValue(
      await tx.rawQuery('SELECT count(*) FROM state_chunks WHERE owner = ?', [
        key,
      ]),
    );
    if (count != parts) throw const FormatException('本机数据分块缺失');
    final result = _HashResult(), output = StringBuffer();
    final hash = sha256.startChunkedConversion(result);
    var seen = 0;
    for (var first = 0; first < parts; first += 8) {
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
        output.write(chunk);
        hash.add(utf8.encode(chunk));
      }
    }
    hash.close();
    if (seen != parts ||
        output.length != units ||
        result.digest.toString() != manifest['sha256']) {
      throw const FormatException('本机数据分块校验失败');
    }
    return output.toString();
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

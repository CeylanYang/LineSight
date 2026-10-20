import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/state_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';
import '../test_support/baseline_state_storage.dart' as baseline;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'batched chunks roll back across batches and reject damaged persisted data',
    (tester) async {
      final path = '${await getDatabasesPath()}/state-batches-${uid()}.db';
      final store = AppStore();
      await store.init(path: path);
      final db = store.db;
      final original = '${'旧' * (stateChunkUnits * 14)}😀结束';
      final replacement = '${'新' * (stateChunkUnits * 11)}𠀋';
      Future<String?> read(String key) =>
          db.transaction((tx) => StateStorage.read(tx, key));
      Future<void> write(String key, String value) =>
          db.transaction((tx) => StateStorage.write(tx, key, value));
      try {
        await write('value', original);
        await write('related', 'old related state');
        expect(await read('value'), original);
        final beforeHeader = await db.query(
          'state',
          where: 'key = ?',
          whereArgs: ['value'],
        );
        final beforeChunks = await db.query(
          'state_chunks',
          where: 'owner = ?',
          whereArgs: ['value'],
          orderBy: 'part',
        );
        expect(beforeChunks.length, greaterThan(8));
        await db.execute(
          "CREATE TEMP TRIGGER reject_late_batch BEFORE INSERT ON state_chunks "
          "WHEN NEW.owner = 'value' AND NEW.part = 9 BEGIN SELECT RAISE(ABORT, 'forced second batch failure'); END",
        );
        await expectLater(
          db.transaction((tx) async {
            await StateStorage.write(tx, 'related', 'new related state');
            await StateStorage.write(tx, 'value', replacement);
          }),
          throwsA(isA<DatabaseException>()),
        );
        expect(await read('related'), 'old related state');
        expect(await read('value'), original);
        expect(
          await db.query('state', where: 'key = ?', whereArgs: ['value']),
          beforeHeader,
        );
        expect(
          await db.query(
            'state_chunks',
            where: 'owner = ?',
            whereArgs: ['value'],
            orderBy: 'part',
          ),
          beforeChunks,
        );
        await db.execute('DROP TRIGGER reject_late_batch');
        await write('value', replacement);
        expect(await read('value'), replacement);
        expect(
          await db.transaction(
            (tx) => baseline.BaselineStateStorage.read(tx, 'value'),
          ),
          replacement,
        );
        await write('value', '{}');
        expect(await read('value'), '{}');
        expect(
          await db.query(
            'state_chunks',
            where: 'owner = ?',
            whereArgs: ['value'],
          ),
          isEmpty,
        );
        await write('value', '');
        expect(await read('value'), '');
        expect(await read('absent'), isNull);

        // A pre-chunking cell still exceeds the cursor window and contains Unicode.
        await db.insert('state', {'key': 'legacy', 'value': original});
        expect(await read('legacy'), original);

        for (final damage in [
          'missing',
          'order',
          'content',
          'oversized',
          'hash',
          'units',
          'extra',
        ]) {
          await write('value', replacement);
          if (damage == 'missing') {
            await db.delete(
              'state_chunks',
              where: 'owner = ? AND part = 9',
              whereArgs: ['value'],
            );
          } else if (damage == 'order') {
            await db.update(
              'state_chunks',
              {'part': 999},
              where: 'owner = ? AND part = 9',
              whereArgs: ['value'],
            );
          } else if (damage == 'content' || damage == 'oversized') {
            await db.update(
              'state_chunks',
              {
                'value':
                    'x' * (stateChunkUnits + (damage == 'oversized' ? 1 : 0)),
              },
              where: 'owner = ? AND part = 9',
              whereArgs: ['value'],
            );
          } else if (damage == 'extra') {
            await db.insert('state_chunks', {
              'owner': 'value',
              'part': 999,
              'value': 'orphan',
            });
          } else {
            final header =
                (await db.query(
                      'state',
                      where: 'key = ?',
                      whereArgs: ['value'],
                    )).single['value']
                    as String;
            const marker = 'LineSightState/2:';
            final metadata = jsonDecode(header.substring(marker.length));
            if (damage == 'hash') {
              metadata['sha256'] = '0' * 64;
            }
            if (damage == 'units') {
              metadata['units'] = (metadata['units'] as int) - 1;
            }
            await db.update(
              'state',
              {'value': '$marker${jsonEncode(metadata)}'},
              where: 'key = ?',
              whereArgs: ['value'],
            );
          }
          await expectLater(
            read('value'),
            throwsFormatException,
            reason: damage,
          );
          expect(
            await db.query('state', where: 'key = ?', whereArgs: ['value']),
            isNotEmpty,
          );
        }
        await write('value', replacement);
        expect(await read('value'), replacement);
        await db.transaction(
          (tx) => baseline.BaselineStateStorage.write(tx, 'from-old', original),
        );
        expect(await read('from-old'), original);
        expect(await db.getVersion(), 3);
      } finally {
        await db.close();
        store.dispose();
        await deleteDatabase(path);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

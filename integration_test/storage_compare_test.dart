import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/state_codec.dart';
import 'package:linesight_flutter/state_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';
import '../test_support/baseline_state_storage.dart' as baseline;
import '../test_support/csv_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'alternating baseline and candidate storage in one process',
    (tester) async {
      final path = '${await getDatabasesPath()}/storage-compare-${uid()}.db';
      final store = AppStore();
      await store.init(path: path);
      final source = jsonEncode(csvFixture().toJson());
      Future<T> measure<T>(
        String phase,
        int run,
        Future<T> Function() task,
      ) async {
        final watch = Stopwatch()..start();
        var previous = 0, maxGap = 0;
        void tick() {
          final now = watch.elapsedMicroseconds;
          if (now - previous > maxGap) maxGap = now - previous;
          previous = now;
        }

        final timer = Timer.periodic(
          const Duration(milliseconds: 16),
          (_) => tick(),
        );
        try {
          final result = await task();
          tick();
          // ignore: avoid_print
          print(
            'STORAGE_COMPARE ${jsonEncode({'phase': phase, 'run': run, 'elapsedUs': watch.elapsedMicroseconds, 'maxGapUs': maxGap})}',
          );
          return result;
        } finally {
          timer.cancel();
        }
      }

      try {
        for (var run = 1; run <= 4; run++) {
          for (final worker in run.isOdd ? [false, true] : [true, false]) {
            final label = worker ? 'worker' : 'baseline';
            final prepared = await measure(
              'prepare-$label',
              run,
              () async => worker
                  ? await compute(prepareStateValue, source)
                  : prepareStateValue(source),
            );
            expect(
              [
                for (var part = 0; part < prepared.chunkEnds.length; part++)
                  prepared.chunk(source, part),
              ].join(),
              source,
            );
            await measure(
              'write-$label',
              run,
              () => store.db.transaction(
                (tx) => worker
                    ? StateStorage.write(tx, 'comparison', source)
                    : baseline.BaselineStateStorage.write(
                        tx,
                        'comparison',
                        source,
                      ),
              ),
            );
            final value = await measure(
              'read-$label',
              run,
              () => store.db.transaction(
                (tx) => worker
                    ? StateStorage.read(tx, 'comparison')
                    : baseline.BaselineStateStorage.read(tx, 'comparison'),
              ),
            );
            expect(value, source);
          }
        }
      } finally {
        await store.db.close();
        store.dispose();
        await deleteDatabase(path);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/backup.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/state_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';
import '../test_support/workspace_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'startup timing and exact canonical state preservation',
    (tester) async {
      final path = '${await getDatabasesPath()}/startup-profile-${uid()}.db';
      var store = AppStore();
      await store.init(path: path);
      try {
        for (final scenario in ['small', 'large', 'large-with-undo']) {
          final fixture = scenario == 'small'
              ? Workspace.seed()
              : archiveFixture(large: true);
          final raw = jsonEncode(fixture.toJson());
          await store.db.transaction((tx) async {
            await StateStorage.write(tx, 'workspace', raw);
            if (scenario == 'large-with-undo') {
              await StateStorage.write(tx, 'restorePoint', raw);
            }
            await StateStorage.write(tx, 'preferences', '{"dark":true}');
            await StateStorage.write(
              tx,
              'backupReceipt',
              jsonEncode(
                BackupReceipt(
                  'profile',
                  'receipt',
                  DateTime.utc(2026, 10, 14),
                  fixture.inspections.length,
                ).toJson(),
              ),
            );
          });
          // Canonical startup must never rewrite state, even with a legacy point
          // lacking metadata. Any hidden migration will fail this trigger.
          await store.db.execute(
            "CREATE TRIGGER profile_no_write BEFORE INSERT ON state "
            "BEGIN SELECT RAISE(ABORT, 'startup must not write'); END",
          );
          for (var run = 0; run < 3; run++) {
            await store.db.close();
            store.dispose();
            store = AppStore();
            final watch = Stopwatch()..start();
            var previous = 0, maxGap = 0, ticks = 0;
            void tick() {
              final now = watch.elapsedMicroseconds;
              final gap = now - previous;
              if (gap > maxGap) maxGap = gap;
              previous = now;
              ticks++;
            }

            final timer = Timer.periodic(
              const Duration(milliseconds: 16),
              (_) => tick(),
            );
            try {
              await store.init(path: path);
              tick();
              final elapsed = watch.elapsedMicroseconds;
              expect(store.startupError, isNull);
              expect(store.ready, isTrue);
              expect(store.user, isNull);
              expect(store.dark, isTrue);
              expect(store.timeArchives, isEmpty);
              expect(store.lastBackup!.operationId, 'receipt');
              expect(store.data.toJson(), fixture.toJson());
              if (scenario == 'large-with-undo') {
                expect(store.restorePoint!.id, 'legacy');
                expect(store.restorePoint!.records, fixture.inspections.length);
              }
              // Machine-readable observations; no fragile speed assertions.
              // ignore: avoid_print
              print(
                'STARTUP_PROFILE ${jsonEncode({'label': const String.fromEnvironment('PROFILE_LABEL', defaultValue: 'baseline'), 'scenario': scenario, 'run': run + 1, 'workspaceBytes': utf8.encode(raw).length, 'elapsedUs': elapsed, 'maxHeartbeatGapUs': maxGap, 'ticks': ticks})}',
              );
            } finally {
              timer.cancel();
            }
          }
          expect(
            await store.db.transaction(
              (tx) => StateStorage.read(tx, 'workspace'),
            ),
            raw,
          );
          await store.db.execute('DROP TRIGGER profile_no_write');
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

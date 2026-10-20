import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/state_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';
import '../test_support/csv_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'measure storage and real archive transactions with exact round trips',
    (tester) async {
      final path = '${await getDatabasesPath()}/storage-profile-${uid()}.db';
      final s = AppStore();
      await s.init(path: path);
      try {
        await s.register(
          'profile.admin',
          '存储测量',
          'Profile-password-42',
          examples: false,
        );
        await s.login('profile.admin', 'Profile-password-42');
        Future<T> measure<T>(
          String phase,
          int run,
          Future<T> Function() task,
        ) async {
          final watch = Stopwatch()..start();
          var previous = 0, maxGap = 0, ticks = 0;
          void tick() {
            final now = watch.elapsedMicroseconds;
            if (now - previous > maxGap) maxGap = now - previous;
            previous = now;
            ticks++;
          }

          final timer = Timer.periodic(
            const Duration(milliseconds: 16),
            (_) => tick(),
          );
          try {
            final value = await task();
            tick();
            // ignore: avoid_print
            print(
              'STORAGE_PROFILE ${jsonEncode({'label': const String.fromEnvironment('PROFILE_LABEL', defaultValue: 'baseline'), 'phase': phase, 'run': run, 'elapsedUs': watch.elapsedMicroseconds, 'maxHeartbeatGapUs': maxGap, 'ticks': ticks})}',
            );
            return value;
          } finally {
            timer.cancel();
          }
        }

        final fixture = csvFixture();
        String source = '';
        for (var run = 1; run <= 3; run++) {
          source = await measure(
            'encode',
            run,
            () async => jsonEncode(fixture.toJson()),
          );
          await measure(
            'write',
            run,
            () => s.db.transaction(
              (tx) => StateStorage.write(tx, 'profile', source),
            ),
          );
          final read = await measure(
            'read',
            run,
            () => s.db.transaction((tx) => StateStorage.read(tx, 'profile')),
          );
          expect(read, source);
        }
        // ignore: avoid_print
        print(
          'STORAGE_FIXTURE ${jsonEncode({'bytes': utf8.encode(source).length, 'records': fixture.inspections.length})}',
        );
        await s.db.transaction((tx) async {
          await StateStorage.remove(tx, 'profile');
          await StateStorage.write(tx, 'workspace', source);
        });
        s.data = fixture;
        final id = fixture.inspections.first.id;
        final originalResult = fixture.inspections.first.passed;
        for (var run = 1; run <= 3; run++) {
          final archived = run.isEven;
          final revision = s.revision;
          await measure('archive', run, () => s.archive({id}, archived));
          expect(s.revision, revision + 1);
          expect(s.data.inspections.first.archived, archived);
          expect(s.data.inspections.first.passed, originalResult);
          final raw = await s.db.transaction(
            (tx) => StateStorage.read(tx, 'workspace'),
          );
          expect(jsonDecode(raw!), s.data.toJson());
        }
      } finally {
        await s.db.close();
        s.dispose();
        await deleteDatabase(path);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/state_storage.dart';
import 'package:linesight_flutter/store.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'invalid settings cannot partially migrate or expose a workspace; retry succeeds',
    (tester) async {
      final path = '${await getDatabasesPath()}/startup-validation-${uid()}.db';
      final store = AppStore();
      await store.init(path: path);
      final workspace = Workspace.seed().toJson();
      workspace['inspections'][0]['at'] = '2026-10-14T09:12:13.123456';
      final raw = jsonEncode(workspace);
      try {
        await store.db.transaction((tx) async {
          await StateStorage.write(tx, 'workspace', raw);
          await StateStorage.write(tx, 'preferences', '[]');
        });
        await store.init();
        expect(store.ready, isFalse);
        expect(store.startupError, isNotNull);
        expect(store.startupStage, '检查工作区与还原点');
        expect(store.user, isNull);
        expect(store.data.inspections, isEmpty);
        expect(store.timeArchives, isEmpty);
        expect(
          await store.db.transaction(
            (tx) => StateStorage.read(tx, 'workspace'),
          ),
          raw,
        );
        expect(
          await store.db.transaction(
            (tx) => StateStorage.read(tx, 'timeArchives'),
          ),
          isNull,
        );
        await store.db.transaction(
          (tx) => StateStorage.write(tx, 'preferences', '{"dark":true}'),
        );
        await store.init();
        expect(store.startupError, isNull);
        expect(store.ready, isTrue);
        expect(store.user, isNull);
        expect(store.dark, isTrue);
        expect(store.data.inspections.length, 96);
        expect(store.timeArchives.single.originals['workspace'], raw);
        expect(store.timeArchives.single.count, 1);
        final archiveId = store.timeArchives.single.id;
        await store.init();
        expect(store.timeArchives.single.id, archiveId);
      } finally {
        await store.db.close();
        store.dispose();
        await deleteDatabase(path);
      }
    },
  );
}

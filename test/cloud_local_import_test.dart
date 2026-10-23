import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/cloud_account.dart';
import 'package:linesight_flutter/cloud_local_import.dart';
import 'package:linesight_flutter/models.dart';
import 'package:linesight_flutter/store.dart';

class ImportAccount extends CloudAccount {
  final seen = <String>{};
  final bodies = <Map>[];
  void Function()? afterBatch;
  @override
  bool get signedIn => true;
  ImportAccount() {
    profile = {'id': 'user-1'};
    activeWorkspace = {'id': 5, 'role': 'owner'};
  }
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
  }) async {
    final data = body as Map;
    bodies.add(data);
    var imported = 0, skipped = 0;
    for (final row in data['records'] as List) {
      if (seen.add('${row['id']}')) {
        imported++;
      } else {
        skipped++;
      }
    }
    afterBatch?.call();
    return {'imported': imported, 'skipped': skipped};
  }
}

Inspection record(String id, {bool sample = false}) => Inspection(
  id: id,
  stationId: 'station',
  recipeName: 'Imported part',
  serial: id,
  at: DateTime.utc(2026, 10, 23),
  passed: true,
  defect: '',
  confidence: .9,
  operatorName: 'Local engineer',
  sample: sample,
);
AppStore authorizedStore() => AppStore()
  ..ready = true
  ..user = const LocalUser(
    'local-1',
    'engineer',
    'Local engineer',
    'engineer',
    true,
  );

void main() {
  test('local authorization is required before a preview can capture data', () {
    final local = AppStore()..ready = true, cloud = ImportAccount();
    expect(() => CloudImportPlan.capture(local, cloud), throwsStateError);
    local.dispose();
    cloud.dispose();
  });
  test(
    'preview freezes records, excludes samples and repeat sends retain stable IDs',
    () async {
      final local = authorizedStore(), cloud = ImportAccount();
      local.data.inspections.addAll([
        record('real'),
        record('sample', sample: true),
      ]);
      final plan = CloudImportPlan.capture(local, cloud);
      local.data.inspections.first.note = 'changed after preview';
      final first = await plan.upload();
      expect(first, {'imported': 1, 'skipped': 0});
      expect((cloud.bodies.first['records'] as List).single['note'], '');
      expect(cloud.bodies.first['include_samples'], false);
      expect(await plan.upload(), {'imported': 0, 'skipped': 1});
      expect(await plan.upload(includeSamples: true), {
        'imported': 1,
        'skipped': 1,
      });
      local.dispose();
      cloud.dispose();
    },
  );
  test(
    'local logout or workspace switch stops the remaining batches',
    () async {
      final local = authorizedStore(), cloud = ImportAccount();
      local.data.inspections.addAll(
        List.generate(251, (i) => record('row-$i')),
      );
      final plan = CloudImportPlan.capture(local, cloud);
      cloud.afterBatch = () => local.session++;
      await expectLater(plan.upload(), throwsStateError);
      expect(cloud.bodies, hasLength(1));
      expect(cloud.seen, hasLength(250));
      cloud.afterBatch = null;
      final retry = CloudImportPlan.capture(local, cloud);
      cloud.activeWorkspace = {'id': 6, 'role': 'owner'};
      await expectLater(retry.upload(), throwsA(isA<Exception>()));
      expect(cloud.bodies, hasLength(1));
      local.dispose();
      cloud.dispose();
    },
  );
}

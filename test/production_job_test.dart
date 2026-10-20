import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/models.dart';

void main() {
  test('production jobs survive workspace persistence and validate', () {
    final workspace = Workspace.seed(examples: false);
    workspace.jobs.add(
      ProductionJob(
        id: 'job-1',
        partName: 'Bracket',
        printer: 'Bambu Lab A1',
        quantity: '12',
        status: 'inspection',
        note: 'Shift A',
        createdAt: DateTime.utc(2026, 10, 21),
      ),
    );

    final restored = Workspace.fromJson(workspace.toJson());
    restored.validate();

    expect(restored.jobs, hasLength(1));
    expect(restored.jobs.single.partName, 'Bracket');
    expect(restored.jobs.single.status, 'inspection');
  });

  test('legacy workspace data without jobs remains readable', () {
    final legacy = Workspace.seed(examples: false).toJson()..remove('jobs');
    final restored = Workspace.fromJson(legacy);
    restored.validate();
    expect(restored.jobs, isEmpty);
  });

  test('production job audit targets are accepted by workspace validation', () {
    final workspace = Workspace.seed(examples: false);
    workspace.audits.add(
      AuditEntry(
        'audit-1',
        'QA',
        '创建生产任务',
        'job-1',
        DateTime.utc(2026, 10, 21),
        targets: const [AuditTarget('job', 'job-1', 'Bracket')],
      ),
    );
    expect(workspace.validate, returnsNormally);
  });

  test('invalid production quantity is rejected', () {
    final workspace = Workspace.seed(examples: false);
    workspace.jobs.add(
      ProductionJob(
        id: 'job-1',
        partName: 'Bracket',
        printer: 'Bambu Lab A1',
        quantity: '0',
        status: 'queued',
        note: '',
        createdAt: DateTime.utc(2026, 10, 21),
      ),
    );
    expect(workspace.validate, throwsFormatException);
  });
}

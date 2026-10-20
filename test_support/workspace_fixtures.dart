import 'package:linesight_flutter/models.dart';

Workspace archiveFixture({bool large = false}) {
  final w = Workspace.seed();
  final detail = large ? '质' * 4096 : '复核依据与原始结果';
  for (var i = 0; i < (large ? 1800 : 2); i++) {
    w.audits.add(
      AuditEntry(
        'archive-$i',
        '测试人员',
        '质量复核',
        detail,
        DateTime.utc(2026, 10, 14),
        actorId: 'actor',
        operationId: 'op-$i',
        targets: [
          AuditTarget(
            'record',
            w.inspections.first.id,
            w.inspections.first.serial,
          ),
        ],
        changes: const [AuditChange('复核结论', '未复核', '放行')],
      ),
    );
  }
  return w;
}

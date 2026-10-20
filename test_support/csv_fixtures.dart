import 'package:linesight_flutter/models.dart';

Workspace csvFixture({int count = 4000, bool large = true}) {
  final w = Workspace.seed(examples: false);
  final note = large ? '质' * 2000 : '一行,"引号"\r\n第二行 😀';
  w.inspections = List.generate(
    count,
    (i) => Inspection(
      id: 'csv-$i',
      serial: 'CSV-${i.toString().padLeft(6, '0')}',
      stationId: w.stations[i % w.stations.length].id,
      recipeName: 'CSV 测试快照',
      at: DateTime.utc(2026, 10, 14, 1, 2, 3, 4, i),
      passed: i % 2 == 0,
      defect: i % 2 == 0 ? '' : '表面划痕',
      confidence: .98,
      operatorName: '测试操作员',
      note: note,
      archived: i % 3 == 0,
      sample: true,
    ),
  );
  w.validate();
  return w;
}

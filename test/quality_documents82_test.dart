import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:linesight_flutter/quality_documents.dart';
import 'package:linesight_flutter/runtime_defaults.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'generates searchable A4 procedures and paginated report with real assets',
    () async {
      final folder = Directory('.artifact-work/cloud82/pdf')
        ..createSync(recursive: true);
      final definitions = defaultRuntimeContent['documents'] as List;
      for (final definition in definitions) {
        final bytes = await buildProcedureDocument(definition);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        File('${folder.path}/${definition['id']}.pdf').writeAsBytesSync(bytes);
      }
      final bytes = await buildQualityReport(
        snapshot: {
          'sample': true,
          'report_id': 'LS-SAMPLE-20261024',
          'workspace': 'LineSight 样例团队',
          'generated_at': '2026-10-24T09:30:00+08:00',
          'metrics': {
            'first_pass_rate': .96,
            'final_release_rate': .99,
            'first_inspected_pieces': 100,
            'final_released_pieces': 99,
            'latest_fail_pieces': 1,
            'latest_scrap_pieces': 0,
          },
          'jobs': [
            for (var i = 0; i < 5; i++)
              {
                'id': 'LS-20261024-00$i',
                'part_name': '铝合金壳体',
                'batch_code': 'AL-1024-$i',
                'printer': '一号生产线',
                'quantity': 20,
                'inspections': [
                  {
                    'round_no': 1,
                    'inspector': '林知远',
                    'created_at': '2026-10-24 09:10',
                    'verdict': i == 0 ? 'fail' : 'pass',
                    'pass_qty': i == 0 ? 19 : 20,
                    'fail_qty': i == 0 ? 1 : 0,
                    'scrap_qty': 0,
                    'template_snapshot': {
                      'name': '壳体外观检查',
                      'version': 3,
                      'items': [
                        {'id': 'VIS-01', 'label': '表面清洁'},
                        {'id': 'VIS-02', 'label': '外观面及边缘'},
                      ],
                    },
                    'answers': [
                      {'id': 'VIS-01', 'result': 'pass'},
                      {
                        'id': 'VIS-02',
                        'result': i == 0 ? 'fail' : 'pass',
                        'note': i == 0 ? '外观面划伤，隔离后复核。' : '',
                      },
                    ],
                  },
                ],
                'exceptions': i == 0
                    ? [
                        {
                          'assignee': 'LineSight 质量团队',
                          'note': '外观面划伤',
                          'resolution': '已隔离，待复核',
                        },
                      ]
                    : [],
              },
          ],
        },
      );
      expect(bytes.length, greaterThan(10000));
      File('${folder.path}/quality-report.pdf').writeAsBytesSync(bytes);
    },
  );
}

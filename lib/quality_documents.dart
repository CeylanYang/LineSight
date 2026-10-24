import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'runtime_content.dart';

const _navy = PdfColor.fromInt(0xFF183D5D);
const _pale = PdfColor.fromInt(0xFFE8EFF5);
const _line = PdfColor.fromInt(0xFF8BA0B3);
String _value(Object? value) =>
    value == null || '$value'.isEmpty ? '—' : '$value';

class _DocumentStyle {
  final pw.Font font, bold;
  final bool compact;
  final pw.MemoryImage logo, seal;
  final Map<String, dynamic> brand;
  _DocumentStyle(
    this.font,
    this.bold,
    this.logo,
    this.seal,
    this.brand,
    this.compact,
  );

  static Future<_DocumentStyle> load(
    Map<String, dynamic>? branding, {
    bool compact = false,
  }) async {
    final brand = branding ?? RuntimeContent.instance.report;
    return _DocumentStyle(
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf')),
      pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansSC-SemiBold.ttf'),
      ),
      pw.MemoryImage(
        (await rootBundle.load(
          'assets/templates/linesight_logo.png',
        )).buffer.asUint8List(),
      ),
      pw.MemoryImage(
        await RuntimeContent.instance.image(
          brand,
          fallback: 'assets/templates/linesight_embossed_seal.png',
        ),
      ),
      brand,
      compact,
    );
  }

  pw.Widget header(String title, String code, String version) => pw.Column(
    children: [
      pw.Container(height: 5, color: _navy),
      pw.SizedBox(height: 10),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Image(logo, width: 32, height: 32),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${brand['organization']}',
                  style: const pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy,
                  ),
                ),
                pw.Text(
                  '工业视觉质量管理 / QUALITY CONTROL',
                  style: const pw.TextStyle(fontSize: 8, color: _navy),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                code,
                style: const pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
              pw.Text('版本 $version', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 13),
      pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: compact ? 17 : 20,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
      ),
      pw.Divider(color: _navy, thickness: 1.2),
    ],
  );

  pw.Widget footer(pw.Context context, String code) => pw.Column(
    children: [
      pw.Divider(color: _line, thickness: .5),
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '${brand['organization']} | ${brand['department']}',
              style: const pw.TextStyle(fontSize: 8, color: _navy),
            ),
          ),
          pw.Text(
            '$code    第 ${context.pageNumber} / ${context.pagesCount} 页',
            style: const pw.TextStyle(fontSize: 8, color: _navy),
          ),
        ],
      ),
    ],
  );

  pw.Widget section(String title) => pw.Padding(
    padding: pw.EdgeInsets.only(top: compact ? 7 : 12, bottom: compact ? 4 : 6),
    child: pw.Text(
      title,
      style: const pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: _navy,
      ),
    ),
  );

  pw.Widget table(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.TableColumnWidth>? widths,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    columnWidths: widths,
    headerDecoration: const pw.BoxDecoration(color: _pale),
    headerStyle: const pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: _navy,
    ),
    cellStyle: pw.TextStyle(
      fontSize: compact ? 8.5 : 9,
      lineSpacing: compact ? 1 : 2,
    ),
    border: pw.TableBorder.all(color: _line, width: .5),
    cellPadding: pw.EdgeInsets.symmetric(
      horizontal: 6,
      vertical: compact ? 4 : 7,
    ),
    cellAlignment: pw.Alignment.centerLeft,
  );

  pw.Widget signoff(String reference, {String? inspector}) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                color: _pale,
                width: double.infinity,
                padding: const pw.EdgeInsets.all(7),
                child: pw.Text(
                  '签印与文件编号',
                  style: const pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: _navy,
                    fontSize: 10,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                '出具单位：${brand['organization']}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                '编制 / 签印：${brand['signature']}',
                style: const pw.TextStyle(fontSize: 10),
              ),
              if (inspector != null) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  '检验人：$inspector',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
              pw.SizedBox(height: 10),
              pw.Row(
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: reference,
                    width: 48,
                    height: 48,
                  ),
                  pw.SizedBox(width: 9),
                  pw.Expanded(
                    child: pw.Text(
                      reference,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 18),
        pw.Image(seal, width: compact ? 90 : 116, height: compact ? 90 : 116),
      ],
    ),
  );
}

Future<Uint8List> buildQualityReport({
  required Map snapshot,
  Map<int, Uint8List> images = const {},
  Map<String, dynamic>? branding,
  String? scopeLabel,
}) async {
  final style = await _DocumentStyle.load(branding);
  final brand = style.brand;
  final code = '${brand['document_code']}';
  final document = pw.Document(
    title: '质量检验报告',
    author: '${brand['organization']}',
    creator: 'LineSight',
  );
  final metrics = snapshot['metrics'] as Map? ?? {};
  final jobs = snapshot['jobs'] as List? ?? [];
  final singleInspection = snapshot['kind'] == 'inspection';
  String rate(Object? value) =>
      value is num ? '${(value * 100).toStringAsFixed(1)}%' : '—';
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      maxPages: 200,
      theme: pw.ThemeData.withFont(base: style.font, bold: style.bold),
      header: (_) => style.header(
        singleInspection
            ? '工件检验记录'
            : snapshot['sample'] == true
            ? '质量检验报告（样例）'
            : '质量检验报告',
        code,
        '${brand['version']}',
      ),
      footer: (context) => style.footer(context, code),
      build: (_) => [
        style.section('1  报告信息'),
        style.table(
          ['字段', '内容'],
          [
            ['报告编号', _value(snapshot['report_id'])],
            ['团队 / 工作区', _value(snapshot['workspace'])],
            ['生成时间', _value(snapshot['generated_at'])],
            ['检验范围', scopeLabel ?? (singleInspection ? '指定检验记录' : '当前查询范围')],
          ],
          widths: {0: const pw.FixedColumnWidth(85)},
        ),
        if (!singleInspection) ...[
          style.section('2  质量概况'),
          style.table(
            ['首次通过率', '最终放行率', '首次送检', '最终放行', '异常', '报废'],
            [
              [
                rate(metrics['first_pass_rate']),
                rate(metrics['final_release_rate']),
                _value(metrics['first_inspected_pieces']),
                _value(metrics['final_released_pieces']),
                _value(metrics['latest_fail_pieces']),
                _value(metrics['latest_scrap_pieces']),
              ],
            ],
          ),
        ],
        style.section(singleInspection ? '2  检验明细' : '3  任务与检验明细'),
        if (jobs.isEmpty) pw.Text('当前范围暂无检验记录。'),
        for (final job in jobs) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            _value(job['part_name']),
            style: const pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _navy,
            ),
          ),
          pw.SizedBox(height: 5),
          style.table(
            ['工单号', '产品 / 批次', '设备', '计划数量'],
            [
              [
                _value(job['id']),
                _value(job['batch_code']),
                _value(job['printer']),
                _value(job['quantity']),
              ],
            ],
          ),
          for (final check in job['inspections'] as List? ?? []) ...[
            pw.SizedBox(height: 8),
            style.table(
              ['轮次', '检验人', '检验时间', '结论', '合格 / 异常 / 报废'],
              [
                [
                  _value(check['round_no']),
                  _value(check['inspector']),
                  _value(check['created_at']),
                  check['verdict'] == 'pass' ? '合格' : '异常',
                  '${_value(check['pass_qty'])} / ${_value(check['fail_qty'])} / ${_value(check['scrap_qty'])}',
                ],
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              '检查模板：${_value(check['template_snapshot']?['name'])} / v${_value(check['template_snapshot']?['version'])}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            if ((check['template_snapshot']?['items'] as List? ?? [])
                .isNotEmpty)
              style.table(
                ['项目编号 / 名称', '结果', '问题说明'],
                [
                  for (final item
                      in check['template_snapshot']['items'] as List)
                    for (final answer in [
                      (check['answers'] as List? ?? [])
                          .cast<Map>()
                          .where((row) => row['id'] == item['id'])
                          .firstOrNull,
                    ])
                      [
                        '${item['id']} / ${item['label']}',
                        {
                              'pass': '合格',
                              'fail': '异常',
                              'na': '不适用',
                            }[answer?['result']] ??
                            '未填写',
                        _value(answer?['note']),
                      ],
                ],
                widths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FixedColumnWidth(45),
                  2: const pw.FlexColumnWidth(3),
                },
              ),
            if ('${check['note'] ?? ''}'.isNotEmpty)
              pw.Text(
                '检验说明：${check['note']}',
                style: const pw.TextStyle(fontSize: 9),
              ),
          ],
          if ((job['exceptions'] as List? ?? []).isNotEmpty) ...[
            style.section('异常处置'),
            style.table(
              ['责任人', '异常说明', '处置结果'],
              [
                for (final issue in job['exceptions'] as List)
                  [
                    _value(issue['assignee']),
                    _value(issue['note']),
                    _value(issue['resolution']),
                  ],
              ],
            ),
          ],
          for (final photo in job['evidence'] as List? ?? [])
            if (images[photo['id']] != null) ...[
              pw.SizedBox(height: 8),
              pw.Text(
                '影像记录 #${photo['id']} / ${_value(photo['stage'])}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Image(
                pw.MemoryImage(images[photo['id']]!),
                width: 250,
                height: 160,
                fit: pw.BoxFit.contain,
              ),
            ],
        ],
        style.signoff(_value(snapshot['report_id'])),
      ],
    ),
  );
  return document.save();
}

Future<Uint8List> buildProcedureDocument(
  Map definition, {
  Map<String, dynamic>? branding,
  Map<String, String> results = const {},
  Map<String, String> record = const {},
}) async {
  final style = await _DocumentStyle.load(branding, compact: true);
  final code = '${definition['code']}';
  final document = pw.Document(
    title: '${definition['title']}',
    author: '${style.brand['organization']}',
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      maxPages: 20,
      theme: pw.ThemeData.withFont(base: style.font, bold: style.bold),
      header: (_) => style.header(
        '${definition['title']}',
        code,
        '${definition['version']}',
      ),
      footer: (context) => style.footer(context, code),
      build: (_) => [
        style.table(
          ['文件编号', '版本', '归口部门', '适用范围'],
          [
            [
              code,
              '${definition['version']}',
              '${definition['department']}',
              '${definition['scope']}',
            ],
          ],
        ),
        if ((definition['preparation'] as List? ?? []).isNotEmpty) ...[
          style.section('检验准备'),
          style.table(
            ['准备项目', '作业要求'],
            [
              for (final row in definition['preparation'] as List)
                List<String>.from(row as List),
            ],
          ),
        ],
        for (final section in definition['sections'] as List) ...[
          style.section('${section['title']}'),
          style.table(
            ['项目编号', '检查部位 / 位号', '检查方法与判定依据', '结果'],
            [
              for (final row in section['items'] as List)
                [
                  ...List<String>.from(row as List),
                  {'pass': '合格', 'fail': '异常', 'na': '不适用'}[results[row[0]]] ??
                      '未填写',
                ],
            ],
            widths: {
              0: const pw.FixedColumnWidth(52),
              1: const pw.FixedColumnWidth(85),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FixedColumnWidth(44),
            },
          ),
        ],
        style.section('异常处置'),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _pale,
            border: pw.Border.all(color: _line, width: .5),
          ),
          child: pw.Text(
            '${definition['disposition']}',
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 3),
          ),
        ),
        style.section('检验记录'),
        style.table(
          ['工单号', '产品 / 批次', '检验人', '完成项目 / 总项目'],
          [
            [
              record['order'] ?? '',
              record['batch'] ?? '',
              record['inspector'] ?? '',
              '${results.length} / ${(definition['sections'] as List).fold<int>(0, (sum, section) => sum + (section['items'] as List).length)}',
            ],
          ],
        ),
        style.signoff(
          'LS-$code-R${definition['version']}',
          inspector: record['inspector'],
        ),
      ],
    ),
  );
  return document.save();
}

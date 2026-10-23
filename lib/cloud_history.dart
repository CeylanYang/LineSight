import 'package:flutter/material.dart';
import 'l10n.dart';
import 'time.dart';
import 'ui.dart';

class CloudSerialResults extends StatelessWidget {
  final Map<String, dynamic> results;
  const CloudSerialResults({super.key, required this.results});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(tr(context, '逐件检验结果'), icon: Icons.qr_code),
      GlassPanel(
        child: Column(
          children: [
            for (final row in results.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        row.key,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tag(
                      tr(
                        context,
                        row.value == 'pass'
                            ? '合格'
                            : row.value == 'fail'
                            ? '异常'
                            : '报废',
                      ),
                      color: row.value == 'pass' ? green : red,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class CloudHistoryEvent extends StatelessWidget {
  final Map<String, dynamic> event;
  const CloudHistoryEvent({super.key, required this.event});
  @override
  Widget build(BuildContext context) {
    final actor = '${event['actor'] ?? ''}';
    final details = (event['details'] as Map?) ?? const {};
    final record = (event['record'] as Map?) ?? const {};
    const statuses = {
      'queued': '待打印',
      'printing': '打印中',
      'inspection': '待质检',
      'exception': '异常处理中',
      'closed': '已关闭',
    };
    const stages = {'inspection': '检验照片', 'before': '整改前', 'after': '整改后'};
    final at = DateTime.tryParse('${event['created_at']}');
    final title = switch (event['action']) {
      'job.created' => '创建任务',
      'job.status' => '任务状态更新',
      'inspection.pass' => '检验合格',
      'inspection.fail' => '检验异常',
      'exception.created' => '创建异常',
      'exception.resolved' => '完成异常处置',
      'evidence.uploaded' => '上传照片',
      _ => '任务操作',
    };
    final values = <String, String>{
      if (event['version'] != null) '任务版本': '${event['version']}',
      '记录编号': '${event['object_id'] ?? ''}',
      if (record['round_no'] != null) '检验轮次': '${record['round_no']}',
      if (record['inspected_qty'] != null) '送检数': '${record['inspected_qty']}',
      if (record['pass_qty'] != null) '合格数': '${record['pass_qty']}',
      if (record['fail_qty'] != null) '异常数': '${record['fail_qty']}',
      if (record['scrap_qty'] != null) '报废数': '${record['scrap_qty']}',
      if (record['template_version'] != null)
        '模板版本': '${record['template_version']}',
      if (details['stage'] != null)
        '照片阶段': tr(context, stages[details['stage']] ?? '${details['stage']}'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          leading: CircleAvatar(
            backgroundColor: blue.withValues(alpha: .09),
            child: Text(
              actor.isEmpty ? 'L' : actor.characters.first,
              style: const TextStyle(color: blue),
            ),
          ),
          title: Text(
            tr(context, title),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${actor.isEmpty ? tr(context, '未记录操作者') : actor} · ${at == null ? '${event['created_at'] ?? ''}' : zonedStamp(at)}',
                style: const TextStyle(fontSize: 10, color: muted),
              ),
              if (details['previous'] != null && details['status'] != null)
                Text(
                  '${tr(context, statuses[details['previous']] ?? '${details['previous']}')} → ${tr(context, statuses[details['status']] ?? '${details['status']}')}',
                  style: const TextStyle(fontSize: 11, color: blue),
                ),
            ],
          ),
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (final value in values.entries)
                  Text(
                    '${tr(context, value.key)} · ${value.value}',
                    style: const TextStyle(fontSize: 11, color: ink),
                  ),
              ],
            ),
            for (final key in ['resolution', 'closure_reason'])
              if ('${details[key] ?? ''}'.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${details[key]}'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

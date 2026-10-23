import 'package:flutter/material.dart';
import 'cloud_account.dart';
import 'l10n.dart';
import 'screens/cloud_tasks.dart';
import 'ui.dart';

/// Today follows the device calendar; the identical UTC bounds reach the API.
Map<String, String> cloudTodayBounds(DateTime now) {
  final start = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day + 1);
  return {
    'updated_from': start.toUtc().toIso8601String(),
    'updated_to': end.toUtc().toIso8601String(),
  };
}

class CloudWorkbenchSummary extends StatelessWidget {
  final CloudAccount account;
  final DateTime? now;
  const CloudWorkbenchSummary({super.key, required this.account, this.now});

  @override
  Widget build(BuildContext context) {
    final bounds = cloudTodayBounds(now ?? DateTime.now());
    final start = DateTime.parse(bounds['updated_from']!);
    final end = DateTime.parse(bounds['updated_to']!);
    int count(String status, {bool today = false}) => account.jobs.where((job) {
      if (job['status'] != status) return false;
      if (!today) return true;
      final at = DateTime.tryParse('${job['updated_at']}');
      return at != null && !at.isBefore(start) && at.isBefore(end);
    }).length;
    final notices = account.notifications;
    final trend = (account.metrics['trend'] as List?) ?? const [];
    Widget metric(String label, String status, Color color, bool today) =>
        StatCard(
          label: tr(context, label),
          value: '${count(status, today: today)}',
          color: color,
          icon: status == 'closed' ? Icons.task_alt : Icons.pending_actions,
          onTap: () => openPage(
            context,
            CloudTaskListPage(
              status: status,
              filters: today ? bounds : const {},
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          tr(context, '质量概览'),
          caption: tr(context, '今日按进度更新时间统计'),
          icon: Icons.speed,
        ),
        AdaptiveGrid(
          minWidth: 155,
          children: [
            metric('今日待检', 'inspection', amber, true),
            metric('异常处理中', 'exception', red, false),
            metric('今日已关闭', 'closed', green, true),
          ],
        ),
        SectionHeader(tr(context, '我的待办'), icon: Icons.checklist),
        GlassPanel(
          child: Column(
            children: [
              for (final category in [
                'inspection',
                'exception',
                'reinspection',
              ])
                Builder(
                  builder: (context) {
                    final rows = notices
                        .where(
                          (n) => category == 'exception'
                              ? n['status'] == 'exception'
                              : n['status'] == 'inspection' &&
                                    (n['reinspection'] == true) ==
                                        (category == 'reinspection'),
                        )
                        .toList();
                    final label = category == 'exception'
                        ? '待异常处理'
                        : category == 'reinspection'
                        ? '待复检'
                        : '待质检';
                    return ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(tr(context, label)),
                      trailing: Text('${rows.length}'),
                      children: [
                        if (rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(tr(context, '暂无待办')),
                          ),
                        for (final notice in rows)
                          ListTile(
                            title: Text(
                              '${notice['part_name']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              final jobs = account.jobs.where(
                                (j) => '${j['id']}' == '${notice['task_id']}',
                              );
                              if (jobs.isNotEmpty &&
                                  account.activeWorkspace != null) {
                                openPage(
                                  context,
                                  CloudTaskPage(
                                    job: jobs.first,
                                    workspaceId:
                                        account.activeWorkspace!['id'] as int,
                                  ),
                                );
                              }
                            },
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        SectionHeader(
          tr(context, '近7日首次检验'),
          caption: tr(context, '合格数 / 送检数'),
          icon: Icons.insights,
        ),
        GlassPanel(
          child: Column(
            children: [
              if (trend.isEmpty) Text(tr(context, '暂无检验数据')),
              for (final day in trend)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${day['day']}'),
                  subtitle: LinearProgressIndicator(
                    value: (day['inspected'] as num? ?? 0) == 0
                        ? 0
                        : ((day['passed'] as num) / (day['inspected'] as num))
                              .clamp(0, 1),
                  ),
                  trailing: Text(
                    '${day['passed'] ?? 0}/${day['inspected'] ?? 0}',
                  ),
                  onTap: () => openPage(
                    context,
                    CloudTaskListPage(filters: {'first_day': '${day['day']}'}),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

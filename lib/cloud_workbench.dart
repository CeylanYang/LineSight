import 'package:flutter/material.dart';
import 'cloud_account.dart';
import 'cloud_feedback.dart';
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
    if (!account.workspaceDataReady) {
      return CloudWorkspaceStatus(account: account);
    }
    final bounds = cloudTodayBounds(now ?? DateTime.now());
    final start = DateTime.parse(bounds['updated_from']!);
    final end = DateTime.parse(bounds['updated_to']!);
    int count(String status, {bool today = false}) => account.jobs.where((job) {
      if (job['status'] != status) return false;
      if (!today) return true;
      final at = DateTime.tryParse('${job['updated_at']}');
      return at != null && !at.isBefore(start) && at.isBefore(end);
    }).length;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, '质检概况'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in [
                ('今日待检', 'inspection', amber, true),
                ('异常处理中', 'exception', red, false),
                ('今日已关闭', 'closed', green, true),
              ])
                Expanded(
                  child: CloudSummaryMetric(
                    label: tr(context, entry.$1),
                    value: '${count(entry.$2, today: entry.$4)}',
                    color: entry.$3,
                    onTap: () => openPage(
                      context,
                      CloudTaskListPage(
                        status: entry.$2,
                        filters: entry.$4 ? bounds : const {},
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CloudSummaryMetric extends StatelessWidget {
  final String label, value;
  final Color color;
  final VoidCallback onTap;
  const CloudSummaryMetric({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    ),
  );
}

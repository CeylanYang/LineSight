import '../l10n.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../ui.dart';
import 'csv_export.dart';
import 'records.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  int days = 7;
  String? stationId;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), now = DateTime.now();
    final start = localDay(now, 1 - days);
    final end = localDay(now, 1);
    final records = s.records
        .where(
          (r) =>
              !r.at.isBefore(start) &&
              r.at.isBefore(end) &&
              (stationId == null || r.stationId == stationId),
        )
        .toList();
    final original = records.where((r) => r.passed).length,
        finalPass = records.where((r) => r.finalPassed).length;
    final defects = <String, int>{};
    for (final r in records.where((r) => !r.passed)) {
      defects.update(r.defect, (v) => v + 1, ifAbsent: () => 1);
    }
    final ranked = defects.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final buckets = List.generate(days, (i) {
      final date = localDay(start, i);
      return records.where((r) => sameLocalDay(r.at, date)).toList();
    });
    final range = DateTimeRange(start: start, end: localDay(end, -1));
    return DetailScaffold(
      title: tr(context, "质量洞察"),
      actions: [
        if (s.engineer)
          IconButton(
            tooltip: tr(context, "导出当前统计范围的记录"),
            onPressed: records.isEmpty
                ? null
                : () => perform(
                    context,
                    () async => openPage(
                      context,
                      CsvExportPage(
                        snapshot: s.captureCsv(records),
                        session: s.session,
                        scope: tr(context, "当前统计范围"),
                        filterSummary: [
                          tr(context, '{0} 至 {1}', [
                            stamp(range.start).split(' ').first,
                            stamp(range.end).split(' ').first,
                          ]),
                          stationId == null
                              ? tr(context, "全部工位")
                              : s.station(stationId!).name,
                          tr(context, '未归档'),
                          tr(context, '时间从新到旧'),
                        ].join(' · '),
                      ),
                    ),
                  ),
            icon: const Icon(Icons.file_download_outlined),
          ),
      ],
      children: [
        PageHeading(
          eyebrow: 'ANALYTICS / QUALITY',
          title: tr(context, "从数据，到判断。"),
          subtitle: tr(context, "按设备本地日期统计未归档记录，包含已标记的示例数据。"),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in {
              1: tr(context, '今天'),
              7: tr(context, '近 7 天'),
              30: tr(context, '近 30 天'),
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: days == entry.key,
                onSelected: (_) => setState(() => days = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: stationId ?? 'all',
          isExpanded: true,
          decoration: InputDecoration(labelText: tr(context, "工位范围")),
          items: [
            DropdownMenuItem(value: 'all', child: Text(tr(context, "全部工位"))),
            ...s.data.stations.map(
              (x) => DropdownMenuItem(value: x.id, child: Text(x.name)),
            ),
          ],
          onChanged: (v) => setState(() => stationId = v == 'all' ? null : v),
        ),
        const SizedBox(height: 20),
        AdaptiveGrid(
          minWidth: 130,
          children: [
            Metric(
              label: tr(context, "检测总数"),
              value: '${records.length}',
              icon: Icons.fact_check_outlined,
            ),
            Metric(
              label: tr(context, "原始合格率"),
              value: records.isEmpty
                  ? '—'
                  : '${(original / records.length * 100).toStringAsFixed(1)}%',
              icon: Icons.verified_outlined,
              color: green,
            ),
            Metric(
              label: tr(context, "复核后合格率"),
              value: records.isEmpty
                  ? '—'
                  : '${(finalPass / records.length * 100).toStringAsFixed(1)}%',
              icon: Icons.rule_outlined,
              color: blue,
            ),
            Metric(
              label: tr(context, "范围内待复核"),
              value: '${records.where((r) => r.pending).length}',
              icon: Icons.pending_actions,
              color: amber,
            ),
          ],
        ),
        if (records.isEmpty) ...[
          const SizedBox(height: 20),
          EmptyState(
            title: tr(context, "此范围还没有数据"),
            subtitle: tr(context, "调整日期或工位，或生成一条模拟检测记录。"),
          ),
        ],
        SectionHeading(
          tr(context, "每日检测量"),
          action: TextButton(
            onPressed: () => openPage(
              context,
              RecordsScreen(stationId: stationId, range: range),
            ),
            child: Text(tr(context, "查看记录 →")),
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 14,
                children: [
                  Tag(tr(context, "合格"), color: green),
                  Tag(tr(context, "不合格"), color: red),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 130 + MediaQuery.textScalerOf(context).scale(40),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final maxValue = max(
                      1,
                      buckets.fold<int>(0, (m, r) => max(m, r.length)),
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(days, (i) {
                        final list = buckets[i],
                            fail = list.where((r) => !r.passed).length;
                        final date = localDay(start, i);
                        return Expanded(
                          child: Tooltip(
                            message: tr(context, "{0}/{1}：{2} 次，{3} 次不合格", [
                              date.month,
                              date.day,
                              list.length,
                              fail,
                            ]),
                            child: InkWell(
                              onTap: () => openPage(
                                context,
                                RecordsScreen(
                                  stationId: stationId,
                                  range: DateTimeRange(start: date, end: date),
                                ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: days > 7 ? 2 : 6,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (days <= 7)
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${list.length}',
                                          maxLines: 1,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    const SizedBox(height: 5),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Column(
                                        children: [
                                          Container(
                                            height: fail / maxValue * 115,
                                            color: red,
                                          ),
                                          Container(
                                            height:
                                                (list.length - fail) /
                                                maxValue *
                                                115,
                                            color: green,
                                          ),
                                          if (list.isEmpty)
                                            Container(
                                              height: 2,
                                              color: Colors.blueGrey.withValues(
                                                alpha: .15,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        days > 7 && i % 5 != 0
                                            ? ''
                                            : '${date.day}',
                                        maxLines: 1,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${stamp(start).split(' ').first} — ${stamp(localDay(end, -1)).split(' ').first}',
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "缺陷分布 · 原始判定")),
        if (ranked.isEmpty)
          GlassPanel(child: Text(tr(context, "当前范围没有检出的缺陷。"))),
        ...ranked.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassPanel(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text(tr(context, e.key)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(
                    value: e.value / max(1, records.length - original),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                    color: red,
                    backgroundColor: red.withValues(alpha: .08),
                  ),
                ),
                trailing: Text(
                  tr(context, "{0} 次", [e.value]),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => openPage(
                  context,
                  RecordsScreen(
                    stationId: stationId,
                    defect: e.key,
                    range: range,
                  ),
                ),
              ),
            ),
          ),
        ),
        SectionHeading(tr(context, "工位对比")),
        ...s.data.stations
            .where((x) => stationId == null || x.id == stationId)
            .map((station) {
              final subset = records
                  .where((r) => r.stationId == station.id)
                  .toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(
                      Icons.precision_manufacturing_outlined,
                      color: blue,
                    ),
                    title: Text(station.name),
                    subtitle: Text(
                      tr(context, "{0} 次检测 · {1} 条待复核", [
                        subset.length,
                        subset.where((r) => r.pending).length,
                      ]),
                    ),
                    trailing: Text(
                      subset.isEmpty
                          ? '—'
                          : '${(subset.where((r) => r.passed).length / subset.length * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: green,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: () => openPage(
                      context,
                      RecordsScreen(stationId: station.id, range: range),
                    ),
                  ),
                ),
              );
            }),
        const SizedBox(height: 16),
        Text(
          tr(
            context,
            "原始合格率 = 原始合格数 / 检测数。复核后合格率使用最近一次复核结论；未复核记录沿用原始判定。归档记录不计入统计。",
          ),
          style: const TextStyle(
            fontSize: 12,
            height: 1.8,
            color: Colors.blueGrey,
          ),
        ),
      ],
    );
  }
}

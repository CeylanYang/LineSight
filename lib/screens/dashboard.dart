import '../l10n.dart';
import 'audit.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../ui.dart';
import 'records.dart';
import 'modules.dart';
import 'statistics.dart';
import 'production.dart';

class DashboardPage extends StatelessWidget {
  final VoidCallback onRecords;
  const DashboardPage({super.key, required this.onRecords});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), now = DateTime.now();
    final today = s.records.where((r) => sameLocalDay(r.at, now)).toList();
    final pass = today.where((r) => r.passed).length;
    return PageBody(
      children: [
        if (s.fileNotice != null) ...[
          Semantics(
            liveRegion: true,
            child: GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.file_present_outlined, color: blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr(context, "上次文件操作"),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: tr(context, "关闭文件操作提示"),
                        onPressed: s.dismissFileNotice,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    trMessage(context, s.fileNotice!),
                    style: const TextStyle(height: 1.6),
                  ),
                  TextButton.icon(
                    onPressed: () => openPage(context, const AuditPage()),
                    icon: const Icon(Icons.history_rounded),
                    label: Text(tr(context, "查看操作日志")),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        PageHeading(
          eyebrow: tr(context, "质量管理"),
          title: tr(context, "质量工作台"),
          subtitle:
              '${s.user?.name ?? ''}，${now.hour < 12
                  ? tr(context, "上午好")
                  : now.hour < 18
                  ? tr(context, "下午好")
                  : tr(context, "晚上好")}  ·  ${stamp(now).split(' ').first}',
          trailing: IconButton.filledTonal(
            tooltip: tr(context, "待复核异常"),
            onPressed: () => openPage(context, const AlertsPage()),
            icon: Badge(
              isLabelVisible: s.pending.isNotEmpty,
              label: Text('${s.pending.length}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
        ),
        GlassPanel(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [Tag(tr(context, "质量协同"), color: green)],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, "{0} 个工位运行中", [
                            s.data.stations.where((x) => x.running).length,
                          ]),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr(context, "本机记录，实时追溯。\n从一次检测开始，建立完整质量档案。"),
                          style: const TextStyle(height: 1.7),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const BrandMark(size: 56),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => openPage(
                      context,
                      StationPage(id: s.data.stations.first.id),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(tr(context, "进入检测台")),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openPage(context, const StatisticsPage()),
                    icon: const Icon(Icons.insights_rounded),
                    label: Text(tr(context, "质量洞察")),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AdaptiveGrid(
          minWidth: 95,
          children: [
            Metric(
              label: tr(context, "今日检测"),
              value: '${today.length}',
              icon: Icons.center_focus_strong,
            ),
            Metric(
              label: tr(context, "原始合格率"),
              value: today.isEmpty
                  ? '—'
                  : '${(pass / today.length * 100).toStringAsFixed(1)}%',
              icon: Icons.verified_outlined,
              color: green,
            ),
            Metric(
              label: tr(context, "待复核异常"),
              value: '${s.pending.length}',
              icon: Icons.rule_folder_outlined,
              color: amber,
            ),
          ],
        ),
        const SizedBox(height: 14),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 7,
            ),
            leading: const Icon(
              Icons.precision_manufacturing_outlined,
              color: blue,
            ),
            title: Text(tr(context, "生产任务")),
            subtitle: Text(tr(context, "把打印任务、质检决定和异常处理放在同一条流程里。")),
            trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
            onTap: () => openPage(context, const ProductionPage()),
          ),
        ),
        if (s.pending.isNotEmpty) ...[
          const SizedBox(height: 14),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 7,
              ),
              leading: const Icon(Icons.warning_amber_rounded, color: amber),
              title: Text(tr(context, "{0} 条异常等待确认", [s.pending.length])),
              subtitle: Text(tr(context, "查看缺陷证据并完成质量复核")),
              trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
              onTap: () => openPage(context, const AlertsPage()),
            ),
          ),
        ],
        SectionHeading(
          tr(context, "产线工位"),
          action: Tag(tr(context, "工位概览"), color: green),
        ),
        AdaptiveGrid(
          children: s.data.stations.map((station) {
            final records = s.records
                .where((r) => r.stationId == station.id)
                .toList();
            final pending = records.where((r) => r.pending).length;
            return GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: blue.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.precision_manufacturing_outlined,
                          color: blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trWorkspaceLabel(context, station.name),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              trWorkspaceLabel(context, station.line),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.blueGrey,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tag(
                        station.running
                            ? tr(context, "运行中")
                            : tr(context, "已暂停"),
                        color: station.running ? green : amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    s.recipe(station.recipeId).label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(context, "{0} 条记录  ·  {1} 条待复核", [
                      records.length,
                      pending,
                    ]),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          openPage(context, StationPage(id: station.id)),
                      icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                      label: Text(tr(context, "查看工位")),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        SectionHeading(
          tr(context, "最近检测"),
          action: TextButton(
            onPressed: onRecords,
            child: Text(tr(context, "全部记录 →")),
          ),
        ),
        if (s.records.isEmpty)
          EmptyState(
            title: tr(context, "第一条记录，从这里开始"),
            subtitle: tr(context, "进入任一工位，点击「添加示例记录」即可生成示例。"),
          ),
        ...s.records
            .take(4)
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RecordTile(record: r),
              ),
            ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            tr(context, "所有指标来自本机记录 · 示例数据均有标记"),
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
        ),
      ],
    );
  }
}

class StationPage extends StatefulWidget {
  final String id;
  const StationPage({super.key, required this.id});
  @override
  State<StationPage> createState() => _StationPageState();
}

class _StationPageState extends State<StationPage> {
  bool scanning = false;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.data.stations.any((x) => x.id == widget.id)) {
      return DetailScaffold(
        title: tr(context, "工位"),
        children: [
          EmptyState(
            title: tr(context, "该工位已不存在"),
            subtitle: tr(context, "数据恢复后，工位列表可能发生变化。"),
          ),
        ],
      );
    }
    final station = s.station(widget.id), recipe = s.recipe(station.recipeId);
    final records = s.records.where((r) => r.stationId == widget.id).toList();
    final latest = records.isEmpty ? null : records.first;
    return DetailScaffold(
      title: trWorkspaceLabel(context, station.name),
      actions: [
        IconButton(
          tooltip: tr(context, "工位操作轨迹"),
          icon: const Icon(Icons.history_rounded),
          onPressed: () =>
              openPage(context, AuditPage(target: s.stationTarget(station.id))),
        ),
      ],
      children: [
        PageHeading(
          eyebrow: '${trWorkspaceLabel(context, station.line)} / INSPECTION',
          title: tr(context, "工位检测台"),
          subtitle: tr(context, "检测流程 · 结果自动保存至工作区"),
          trailing: Tag(
            station.running ? tr(context, "运行中") : tr(context, "已暂停"),
            color: station.running ? green : amber,
          ),
        ),
        AnimatedOpacity(
          opacity: scanning ? .45 : 1,
          duration: Duration(milliseconds: s.reduceMotion ? 0 : 250),
          child: PartPreview(
            defect: latest != null && !latest.passed,
            height: 280,
            part: partArtKey(station.name),
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scanning
                          ? tr(context, "正在生成示例记录…")
                          : latest == null
                          ? tr(context, "等待首次检测")
                          : latest.passed
                          ? tr(context, "PASS · 原始判定合格")
                          : tr(context, "FAIL · 原始判定异常"),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: scanning || latest == null
                            ? blue
                            : latest.passed
                            ? green
                            : red,
                      ),
                    ),
                  ),
                  if (scanning)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                latest == null
                    ? tr(context, "启动工位后可添加示例记录。")
                    : tr(context, "{0}\n{1} · 置信度 {2}%", [
                        latest.serial,
                        stamp(latest.at),
                        (latest.confidence * 100).toStringAsFixed(1),
                      ]),
                style: const TextStyle(height: 1.7),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  BusyButton(
                    label: tr(context, "添加示例记录"),
                    icon: Icons.center_focus_strong,
                    onPressed: !station.running
                        ? null
                        : () async {
                            final startedSession = s.session;
                            setState(() => scanning = true);
                            try {
                              if (!s.reduceMotion) {
                                await Future<void>.delayed(
                                  const Duration(milliseconds: 600),
                                );
                              }
                              s.requireSession(startedSession);
                              await s.simulate(widget.id);
                            } finally {
                              if (mounted) setState(() => scanning = false);
                            }
                          },
                  ),
                  OutlinedButton.icon(
                    onPressed: scanning
                        ? null
                        : () => perform(
                            context,
                            () => s.toggleStation(widget.id),
                          ),
                    icon: Icon(
                      station.running
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      station.running
                          ? tr(context, "暂停工位")
                          : tr(context, "启动工位"),
                    ),
                  ),
                  if (latest != null)
                    TextButton(
                      onPressed: () =>
                          openPage(context, RecordDetailPage(id: latest.id)),
                      child: Text(tr(context, "查看最新记录 →")),
                    ),
                ],
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "当前配方")),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(recipe.label, style: Theme.of(context).textTheme.titleLarge),
              InfoRow(tr(context, "工件材料"), recipe.material),
              InfoRow(tr(context, "灵敏度"), '${recipe.sensitivity.round()}%'),
              InfoRow(
                tr(context, "置信度阈值"),
                '${(recipe.confidence * 100).round()}%',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recipe.defects
                    .map((d) => Tag(tr(context, d)))
                    .toList(),
              ),
              const SizedBox(height: 18),
              if (s.engineer)
                OutlinedButton.icon(
                  onPressed: () =>
                      openPage(context, ChangeoverPage(stationId: widget.id)),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(tr(context, "更换配方")),
                ),
            ],
          ),
        ),
        SectionHeading(
          tr(context, "此工位的检测记录"),
          action: TextButton(
            onPressed: () =>
                openPage(context, RecordsScreen(stationId: widget.id)),
            child: Text(tr(context, "查看全部")),
          ),
        ),
        ...records
            .take(5)
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: RecordTile(record: r),
              ),
            ),
        if (records.isEmpty)
          EmptyState(
            title: tr(context, "暂无检测记录"),
            subtitle: tr(context, "检测完成后，记录会显示在这里。"),
          ),
      ],
    );
  }
}

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DetailScaffold(
      title: tr(context, "异常待办"),
      children: [
        PageHeading(
          eyebrow: 'QUALITY / INBOX',
          title: tr(context, "{0} 条待复核", [s.pending.length]),
          subtitle: tr(context, "按检测时间排列，打开记录查看缺陷和判定依据。"),
        ),
        if (s.pending.isEmpty)
          EmptyState(
            title: tr(context, "所有异常已处理"),
            subtitle: tr(context, "新的检测异常会自动出现在这里。"),
            icon: Icons.task_alt_rounded,
          ),
        ...s.pending.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RecordTile(record: r),
          ),
        ),
      ],
    );
  }
}

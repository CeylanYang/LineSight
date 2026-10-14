import 'audit.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../ui.dart';
import 'records.dart';
import 'modules.dart';
import 'statistics.dart';

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
                      const Expanded(
                        child: Text(
                          '上次文件操作',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭文件操作提示',
                        onPressed: s.dismissFileNotice,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(s.fileNotice!, style: const TextStyle(height: 1.6)),
                  TextButton.icon(
                    onPressed: () => openPage(context, const AuditPage()),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('查看操作日志'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        PageHeading(
          eyebrow: 'LINESIGHT / WORKSPACE',
          title: '质量工作台',
          subtitle:
              '${s.user?.name ?? ''}，${now.hour < 12
                  ? '上午好'
                  : now.hour < 18
                  ? '下午好'
                  : '晚上好'}  ·  ${stamp(now).split(' ').first}',
          trailing: IconButton.filledTonal(
            tooltip: '待复核异常',
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
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Tag('LOCAL FIRST', color: green),
                  Tag('模拟产线 · 示例环境'),
                ],
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
                          '${s.data.stations.where((x) => x.running).length} 个工位运行中',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '本机记录，实时追溯。\n从一次检测开始，建立完整质量档案。',
                          style: TextStyle(height: 1.7),
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
                    label: const Text('进入检测台'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openPage(context, const StatisticsPage()),
                    icon: const Icon(Icons.insights_rounded),
                    label: const Text('质量洞察'),
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
              label: '今日检测',
              value: '${today.length}',
              icon: Icons.center_focus_strong,
            ),
            Metric(
              label: '原始合格率',
              value: today.isEmpty
                  ? '—'
                  : '${(pass / today.length * 100).toStringAsFixed(1)}%',
              icon: Icons.verified_outlined,
              color: green,
            ),
            Metric(
              label: '待复核异常',
              value: '${s.pending.length}',
              icon: Icons.rule_folder_outlined,
              color: amber,
            ),
          ],
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
              title: Text('${s.pending.length} 条异常等待确认'),
              subtitle: const Text('查看缺陷证据并完成质量复核'),
              trailing: const Icon(Icons.arrow_forward_rounded, size: 20),
              onTap: () => openPage(context, const AlertsPage()),
            ),
          ),
        ],
        const SectionHeading('产线工位', action: Tag('本机工作区', color: green)),
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
                              station.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              station.line,
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
                        station.running ? '运行中' : '已暂停',
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
                    '${records.length} 条记录  ·  $pending 条待复核',
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
                      label: const Text('查看工位'),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        SectionHeading(
          '最近检测',
          action: TextButton(onPressed: onRecords, child: const Text('全部记录 →')),
        ),
        if (s.records.isEmpty)
          const EmptyState(
            title: '第一条记录，从这里开始',
            subtitle: '进入任一工位，点击「模拟检测」即可生成记录。',
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
        const Center(
          child: Text(
            '所有指标来自本机记录 · 示例数据均有标记',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
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
      return const DetailScaffold(
        title: '工位',
        children: [EmptyState(title: '该工位已不存在', subtitle: '数据恢复后，工位列表可能发生变化。')],
      );
    }
    final station = s.station(widget.id), recipe = s.recipe(station.recipeId);
    final records = s.records.where((r) => r.stationId == widget.id).toList();
    final latest = records.isEmpty ? null : records.first;
    return DetailScaffold(
      title: station.name,
      actions: [
        IconButton(
          tooltip: '工位操作轨迹',
          icon: const Icon(Icons.history_rounded),
          onPressed: () =>
              openPage(context, AuditPage(target: s.stationTarget(station.id))),
        ),
      ],
      children: [
        PageHeading(
          eyebrow: '${station.line} / INSPECTION',
          title: '工位检测台',
          subtitle: '模拟相机与检测引擎 · 每次操作都会保存至本机',
          trailing: Tag(
            station.running ? '运行中' : '已暂停',
            color: station.running ? green : amber,
          ),
        ),
        AnimatedOpacity(
          opacity: scanning ? .45 : 1,
          duration: Duration(milliseconds: s.reduceMotion ? 0 : 250),
          child: PartPreview(
            defect: latest != null && !latest.passed,
            height: 280,
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
                          ? '正在分析示例画面…'
                          : latest == null
                          ? '等待首次检测'
                          : latest.passed
                          ? 'PASS · 原始判定合格'
                          : 'FAIL · 原始判定异常',
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
                    ? '启动工位后可生成一条模拟检测记录。'
                    : '${latest.serial}\n${stamp(latest.at)} · 置信度 ${(latest.confidence * 100).toStringAsFixed(1)}%',
                style: const TextStyle(height: 1.7),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  BusyButton(
                    label: '模拟检测',
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
                    label: Text(station.running ? '暂停工位' : '启动工位'),
                  ),
                  if (latest != null)
                    TextButton(
                      onPressed: () =>
                          openPage(context, RecordDetailPage(id: latest.id)),
                      child: const Text('查看最新记录 →'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SectionHeading('当前配方'),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(recipe.label, style: Theme.of(context).textTheme.titleLarge),
              InfoRow('工件材料', recipe.material),
              InfoRow('灵敏度', '${recipe.sensitivity.round()}%'),
              InfoRow('置信度阈值', '${(recipe.confidence * 100).round()}%'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recipe.defects.map((d) => Tag(d)).toList(),
              ),
              const SizedBox(height: 18),
              if (s.engineer)
                OutlinedButton.icon(
                  onPressed: () =>
                      openPage(context, ChangeoverPage(stationId: widget.id)),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('更换配方'),
                ),
            ],
          ),
        ),
        SectionHeading(
          '此工位的检测记录',
          action: TextButton(
            onPressed: () =>
                openPage(context, RecordsScreen(stationId: widget.id)),
            child: const Text('查看全部'),
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
          const EmptyState(title: '暂无检测记录', subtitle: '模拟检测完成后，记录会出现在这里。'),
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
      title: '异常待办',
      children: [
        PageHeading(
          eyebrow: 'QUALITY / INBOX',
          title: '${s.pending.length} 条待复核',
          subtitle: '按检测时间排列，打开记录查看缺陷和判定依据。',
        ),
        if (s.pending.isEmpty)
          const EmptyState(
            title: '所有异常已处理',
            subtitle: '新的检测异常会自动出现在这里。',
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

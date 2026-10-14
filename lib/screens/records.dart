import 'audit.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../ui.dart';
import 'csv_export.dart';

class RecordsScreen extends StatelessWidget {
  final String? stationId, defect;
  final DateTimeRange? range;
  const RecordsScreen({super.key, this.stationId, this.defect, this.range});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('检测记录')),
    body: Backdrop(
      child: RecordsPage(stationId: stationId, defect: defect, range: range),
    ),
  );
}

class RecordsPage extends StatefulWidget {
  final String? stationId, defect;
  final DateTimeRange? range;
  const RecordsPage({super.key, this.stationId, this.defect, this.range});
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String query = '', status = 'all';
  String? stationId;
  bool archived = false, selecting = false, newest = true;
  DateTimeRange? range;
  final selected = <String>{};
  final search = TextEditingController();
  int limit = 30;
  @override
  void initState() {
    super.initState();
    stationId = widget.stationId;
    range = widget.range;
    query = widget.defect ?? '';
    search.text = query;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (stationId != null && !s.data.stations.any((x) => x.id == stationId)) {
      stationId = null;
    }
    final records =
        s.data.inspections.where((r) {
          final text =
              '${r.serial} ${r.id} ${r.defect} ${r.recipeName} ${r.note} ${r.operatorName}'
                  .toLowerCase();
          return r.archived == archived &&
              (stationId == null || r.stationId == stationId) &&
              text.contains(query.toLowerCase()) &&
              (range == null ||
                  inLocalDateRange(r.at, range!.start, range!.end)) &&
              switch (status) {
                'pass' => r.finalPassed,
                'fail' => !r.finalPassed,
                'pending' => r.pending,
                _ => true,
              };
        }).toList()..sort(
          (a, b) => newest ? b.at.compareTo(a.at) : a.at.compareTo(b.at),
        );
    final visibleIds = records.map((r) => r.id).toSet();
    selected.removeWhere((id) => !visibleIds.contains(id));
    return PageBody(
      children: [
        PageHeading(
          eyebrow: 'TRACEABILITY / RECORDS',
          title: '检测记录',
          subtitle: '搜索、筛选和复核，让质量可追溯。',
          trailing: IconButton(
            tooltip: '切换时间排序',
            onPressed: () => setState(() => newest = !newest),
            icon: Icon(newest ? Icons.south_rounded : Icons.north_rounded),
          ),
        ),
        TextField(
          controller: search,
          onChanged: (v) => setState(() {
            query = v;
            limit = 30;
          }),
          decoration: InputDecoration(
            hintText: '搜索序列号、缺陷、配方或备注',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    onPressed: () {
                      search.clear();
                      setState(() => query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in {
              'all': '全部',
              'pending': '待复核',
              'pass': '合格',
              'fail': '不合格',
            }.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: status == e.key,
                onSelected: (_) => setState(() {
                  status = e.key;
                  limit = 30;
                }),
              ),
            FilterChip(
              label: const Text('已归档'),
              selected: archived,
              onSelected: (v) => setState(() {
                archived = v;
                selected.clear();
              }),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: stationId ?? 'all',
                key: ValueKey(stationId),
                isExpanded: true,
                decoration: const InputDecoration(labelText: '工位'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全部工位')),
                  ...s.data.stations.map(
                    (x) => DropdownMenuItem(value: x.id, child: Text(x.name)),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => stationId = v == 'all' ? null : v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final value = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: localDay(DateTime.now(), 1),
                    initialDateRange: range,
                  );
                  if (value != null && mounted) setState(() => range = value);
                },
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(
                  range == null
                      ? '选择日期'
                      : '${range!.start.month}/${range!.start.day} – ${range!.end.month}/${range!.end.day}',
                ),
              ),
            ),
          ],
        ),
        if (range != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => range = null),
              child: const Text('清除日期筛选'),
            ),
          ),
        SectionHeading(
          '${records.length} 条${archived ? '归档' : '检测'}记录',
          action: Wrap(
            children: [
              if (s.engineer)
                IconButton(
                  tooltip: '导出筛选结果 CSV',
                  onPressed: records.isEmpty
                      ? null
                      : () => perform(context, () async {
                          openPage(
                            context,
                            CsvExportPage(
                              snapshot: s.captureCsv(records),
                              session: s.session,
                              scope: '筛选结果',
                              filterSummary: [
                                archived ? '归档记录' : '未归档记录',
                                {
                                  'all': '全部判定',
                                  'pending': '待复核',
                                  'pass': '合格',
                                  'fail': '不合格',
                                }[status]!,
                                stationId == null
                                    ? '全部工位'
                                    : s.station(stationId!).name,
                                if (query.isNotEmpty) '关键词：$query',
                                if (range != null)
                                  '${stamp(range!.start).split(' ').first} 至 ${stamp(range!.end).split(' ').first}',
                                newest ? '时间从新到旧' : '时间从旧到新',
                              ].join(' · '),
                            ),
                          );
                        }),
                  icon: const Icon(Icons.file_download_outlined),
                ),
              if (s.engineer)
                TextButton(
                  onPressed: () => setState(() {
                    selecting = !selecting;
                    selected.clear();
                  }),
                  child: Text(selecting ? '完成' : '选择'),
                ),
            ],
          ),
        ),
        if (selecting)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: GlassPanel(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('已选 ${selected.length} 条'),
                  TextButton(
                    onPressed: () =>
                        setState(() => selected.addAll(visibleIds)),
                    child: const Text('全选筛选结果'),
                  ),
                  BusyButton(
                    label: archived ? '恢复所选' : '归档所选',
                    icon: archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    onPressed: selected.isEmpty
                        ? null
                        : () async {
                            if (await confirm(
                              context,
                              archived ? '恢复记录？' : '归档记录？',
                              '将处理 ${selected.length} 条记录。归档记录仍可在「已归档」中查看和恢复。',
                            )) {
                              await s.archive(Set.of(selected), !archived);
                              if (mounted) {
                                setState(() => selected.clear());
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        if (records.isEmpty)
          const EmptyState(
            title: '没有匹配的记录',
            subtitle: '试试清除筛选条件，或到工位生成模拟检测。',
            icon: Icons.manage_search_rounded,
          ),
        ...records
            .take(limit)
            .map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RecordTile(
                  record: r,
                  selected: selecting ? selected.contains(r.id) : null,
                  onSelect: () => setState(() {
                    if (!selected.add(r.id)) selected.remove(r.id);
                  }),
                ),
              ),
            ),
        if (records.length > limit)
          OutlinedButton(
            onPressed: () => setState(() => limit += 30),
            child: Text('加载更多（剩余 ${records.length - limit} 条）'),
          ),
      ],
    );
  }
}

class RecordTile extends StatelessWidget {
  final Inspection record;
  final bool? selected;
  final VoidCallback? onSelect;
  const RecordTile({
    super.key,
    required this.record,
    this.selected,
    this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), r = record;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: selected != null
            ? Checkbox(value: selected, onChanged: (_) => onSelect?.call())
            : Container(
                width: 42,
                height: 48,
                decoration: BoxDecoration(
                  color: (r.finalPassed ? green : red).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  r.finalPassed
                      ? Icons.check_rounded
                      : Icons.priority_high_rounded,
                  color: r.finalPassed ? green : red,
                ),
              ),
        title: Text(
          r.serial,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${s.station(r.stationId).name} · ${stamp(r.at)}',
                style: const TextStyle(fontSize: 11),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Tag(
                    r.pending
                        ? '待复核'
                        : r.review != null
                        ? r.finalPassed
                              ? '复核放行'
                              : '复核判退'
                        : r.passed
                        ? '合格'
                        : '不合格',
                    color: r.pending
                        ? amber
                        : r.finalPassed
                        ? green
                        : red,
                  ),
                  if (r.defect.isNotEmpty) Tag(r.defect, color: red),
                  if (r.sample) const Tag('示例', color: Colors.blueGrey),
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: selected != null
            ? onSelect
            : () => openPage(context, RecordDetailPage(id: r.id)),
      ),
    );
  }
}

class RecordDetailPage extends StatefulWidget {
  final String id;
  const RecordDetailPage({super.key, required this.id});
  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  final note = TextEditingController();
  String verdict = 'reject';
  bool initialized = false;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final found = s.data.inspections.where((r) => r.id == widget.id);
    if (found.isEmpty) {
      return const DetailScaffold(
        title: '检测详情',
        children: [
          EmptyState(title: '记录已移除', subtitle: '示例清理或备份恢复后，这条记录已不在当前工作区。'),
        ],
      );
    }
    final r = found.first;
    if (!initialized) {
      initialized = true;
      note.text = r.note;
      verdict = r.review ?? 'reject';
    }
    return DetailScaffold(
      title: '检测详情',
      actions: [
        if (s.engineer)
          IconButton(
            tooltip: '导出此记录',
            onPressed: () => perform(context, () async {
              openPage(
                context,
                CsvExportPage(
                  snapshot: s.captureCsv([r]),
                  session: s.session,
                  scope: '单条检测记录',
                  filterSummary: r.serial,
                ),
              );
            }),
            icon: const Icon(Icons.file_download_outlined),
          ),
      ],
      children: [
        PageHeading(
          eyebrow: 'INSPECTION / EVIDENCE',
          title: r.serial,
          subtitle: '${s.station(r.stationId).name} · ${stamp(r.at)}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tag(
              r.passed ? '原始判定 PASS' : '原始判定 FAIL',
              color: r.passed ? green : red,
            ),
            if (r.pending) const Tag('等待复核', color: amber),
            if (r.sample) const Tag('示例记录'),
            if (r.archived) const Tag('已归档', color: Colors.blueGrey),
          ],
        ),
        const SizedBox(height: 20),
        PartPreview(defect: !r.passed, height: 260),
        const SizedBox(height: 12),
        const Text(
          '画面为程序绘制的合成工件示意，不代表真实相机采集。',
          style: TextStyle(fontSize: 11, color: Colors.blueGrey),
        ),
        const SectionHeading('检测证据'),
        GlassPanel(
          child: Column(
            children: [
              InfoRow('记录 ID', r.id),
              InfoRow('缺陷类型', r.defect.isEmpty ? '未检出' : r.defect),
              InfoRow('置信度', '${(r.confidence * 100).toStringAsFixed(2)}%'),
              InfoRow('配方快照', r.recipeName),
              if (r.recipeSnapshot.isNotEmpty) ...[
                InfoRow('检测时灵敏度', '${r.recipeSnapshot['sensitivity']}%'),
                InfoRow(
                  '检测时阈值',
                  '${((r.recipeSnapshot['confidence'] as num) * 100).round()}%',
                ),
                InfoRow(
                  '启用缺陷',
                  (r.recipeSnapshot['defects'] as List).join('、'),
                ),
              ],
              InfoRow('操作人员', r.operatorName),
              InfoRow('检测时间', zonedStamp(r.at, precise: true)),
            ],
          ),
        ),
        if (r.review != null) ...[
          const SectionHeading('最近一次复核'),
          GlassPanel(
            child: Column(
              children: [
                InfoRow('复核结果', r.review == 'pass' ? '放行' : '判退'),
                InfoRow('复核人员', r.reviewer!),
                InfoRow('复核时间', zonedStamp(r.reviewedAt!, precise: true)),
                InfoRow('复核依据', r.note),
              ],
            ),
          ),
        ],
        if (s.engineer && !r.archived) ...[
          SectionHeading(r.review == null ? '质量复核' : '更新复核结论'),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '原始检测结果将保留，复核结论和每次变更均写入操作日志。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'reject',
                      label: Text('判退'),
                      icon: Icon(Icons.close),
                    ),
                    ButtonSegment(
                      value: 'pass',
                      label: Text('放行'),
                      icon: Icon(Icons.check),
                    ),
                  ],
                  selected: {verdict},
                  onSelectionChanged: (v) => setState(() => verdict = v.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: note,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: '复核依据',
                    hintText: '描述核查发现与处理原因，至少 3 个字',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: BusyButton(
                    label: '提交复核',
                    icon: Icons.fact_check_outlined,
                    onPressed: () async {
                      await s.review(r.id, verdict, note.text);
                      if (context.mounted) toast(context, '复核已保存');
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!s.engineer) ...[
          const SizedBox(height: 18),
          const GlassPanel(child: Text('当前为操作员账户。请由质量工程师或管理员完成复核。')),
        ],
        AuditTrail(target: s.recordTarget(r), legacySerial: r.serial),
        if (s.engineer) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: r.pending
                ? null
                : () => perform(context, () async {
                    if (await confirm(
                      context,
                      r.archived ? '恢复记录？' : '归档记录？',
                      r.archived ? '记录会重新出现在检测列表和统计中。' : '记录将移入归档区，可随时恢复。',
                    )) {
                      await s.archive({r.id}, !r.archived);
                    }
                  }),
            icon: Icon(
              r.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            label: Text(r.archived ? '恢复此记录' : '归档此记录'),
          ),
        ],
      ],
    );
  }
}

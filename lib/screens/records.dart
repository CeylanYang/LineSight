import '../l10n.dart';
import 'audit.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../record_query.dart';
import '../record_review.dart';
import '../store.dart';
import '../ui.dart';
import 'csv_export.dart';

class RecordsScreen extends StatelessWidget {
  final String? stationId, defect;
  final DateTimeRange? range;
  const RecordsScreen({super.key, this.stationId, this.defect, this.range});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, "检测记录"))),
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
  final recordQuery = RecordQueryCache();
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
    final result = recordQuery.resolve(
      workspace: s.data,
      revision: s.revision,
      session: s.session,
      query: query,
      status: status,
      stationId: stationId,
      archived: archived,
      newest: newest,
      firstDate: range?.start,
      lastDate: range?.end,
    );
    final records = result.records;
    final visibleIds = result.ids;
    selected.removeWhere((id) => !visibleIds.contains(id));
    return PageBody(
      children: [
        PageHeading(
          eyebrow: 'TRACEABILITY / RECORDS',
          title: tr(context, "检测记录"),
          subtitle: tr(context, "搜索、筛选和复核，让质量可追溯。"),
          trailing: IconButton(
            tooltip: tr(context, "切换时间排序"),
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
            hintText: tr(context, "搜索序列号、缺陷、配方或备注"),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: tr(context, "清空搜索"),
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
              'all': tr(context, "全部"),
              'pending': tr(context, "待复核"),
              'pass': tr(context, "合格"),
              'fail': tr(context, "不合格"),
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
              label: Text(tr(context, "已归档")),
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
                decoration: InputDecoration(labelText: tr(context, "工位")),
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text(tr(context, "全部工位")),
                  ),
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
                      ? tr(context, "选择日期")
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
              child: Text(tr(context, "清除日期筛选")),
            ),
          ),
        SectionHeading(
          tr(context, "{0} 条{1}记录", [
            records.length,
            archived ? tr(context, "归档") : tr(context, "检测"),
          ]),
          action: Wrap(
            children: [
              if (s.engineer)
                IconButton(
                  tooltip: tr(context, "导出筛选结果 CSV"),
                  onPressed: records.isEmpty
                      ? null
                      : () => perform(context, () async {
                          openPage(
                            context,
                            CsvExportPage(
                              snapshot: s.captureCsv(records),
                              session: s.session,
                              scope: tr(context, "筛选结果"),
                              filterSummary: [
                                archived
                                    ? tr(context, "归档记录")
                                    : tr(context, "未归档记录"),
                                {
                                  'all': tr(context, "全部判定"),
                                  'pending': tr(context, "待复核"),
                                  'pass': tr(context, "合格"),
                                  'fail': tr(context, "不合格"),
                                }[status]!,
                                stationId == null
                                    ? tr(context, "全部工位")
                                    : s.station(stationId!).name,
                                if (query.isNotEmpty)
                                  tr(context, "关键词：{0}", [query]),
                                if (range != null)
                                  tr(context, "{0} 至 {1}", [
                                    stamp(range!.start).split(' ').first,
                                    stamp(range!.end).split(' ').first,
                                  ]),
                                newest
                                    ? tr(context, "时间从新到旧")
                                    : tr(context, "时间从旧到新"),
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
                  child: Text(
                    selecting ? tr(context, "完成") : tr(context, "选择"),
                  ),
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
                  Text(tr(context, "已选 {0} 条", [selected.length])),
                  TextButton(
                    onPressed: () =>
                        setState(() => selected.addAll(visibleIds)),
                    child: Text(tr(context, "全选筛选结果")),
                  ),
                  BusyButton(
                    label: archived ? tr(context, "恢复所选") : tr(context, "归档所选"),
                    icon: archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    onPressed: selected.isEmpty
                        ? null
                        : () async {
                            if (await confirm(
                              context,
                              archived
                                  ? tr(context, "恢复记录？")
                                  : tr(context, "归档记录？"),
                              tr(context, "将处理 {0} 条记录。归档记录仍可在「已归档」中查看和恢复。", [
                                selected.length,
                              ]),
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
          EmptyState(
            title: tr(context, "没有匹配的记录"),
            subtitle: tr(context, "试试清除筛选条件，或到工位生成模拟检测。"),
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
            child: Text(
              tr(context, "加载更多（剩余 {0} 条）", [records.length - limit]),
            ),
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
                        ? tr(context, "待复核")
                        : r.review != null
                        ? r.finalPassed
                              ? tr(context, "复核放行")
                              : tr(context, "复核判退")
                        : r.passed
                        ? tr(context, "合格")
                        : tr(context, "不合格"),
                    color: r.pending
                        ? amber
                        : r.finalPassed
                        ? green
                        : red,
                  ),
                  if (r.defect.isNotEmpty)
                    Tag(tr(context, r.defect), color: red),
                  if (r.sample) Tag(tr(context, "示例"), color: Colors.blueGrey),
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
  final form = GlobalKey<FormState>();
  String verdict = 'reject';
  String _baseNote = '', _baseVerdict = 'reject';
  ReviewRecordVersion? _version;
  int? _draftSession;
  bool _conflicted = false, _saving = false, _allowPop = false;
  bool _exitDialogOpen = false;
  bool get _dirty =>
      _version != null && (note.text != _baseNote || verdict != _baseVerdict);

  void _adopt(Inspection record, int session) {
    _version = ReviewRecordVersion.capture(record);
    _draftSession = session;
    _baseNote = record.note;
    _baseVerdict = record.review ?? 'reject';
    if (note.text != _baseNote) note.text = _baseNote;
    verdict = _baseVerdict;
    _conflicted = false;
    _allowPop = false;
  }

  Widget _guard(Widget child) => PopScope<void>(
    canPop: !_saving && (!_dirty || _allowPop),
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _exitDialogOpen) return;
      if (_saving) {
        toast(context, tr(context, "正在保存复核，请稍候"));
        return;
      }
      _exitDialogOpen = true;
      final discard = await confirm(
        context,
        tr(context, "放弃未提交的复核？"),
        tr(context, "复核草稿尚未保存，返回后将丢弃本次修改。"),
        confirmLabel: tr(context, "放弃并返回"),
      );
      _exitDialogOpen = false;
      if (!mounted || !discard) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context);
        }
      });
    },
    child: child,
  );

  Future<void> _reload(
    AppStore store,
    Inspection shown, {
    bool keepDraft = false,
  }) async {
    final shownVersion = ReviewRecordVersion.capture(shown);
    final startedSession = store.session;
    final accepted = await confirm(
      context,
      keepDraft ? tr(context, "已核对最新记录？") : tr(context, "放弃草稿并重新载入？"),
      keepDraft
          ? tr(context, "请确认已查看上方最新检测证据和复核记录。将保留你的草稿，之后的提交会作为新的复核写入日志。")
          : tr(context, "当前未提交的内容将被丢弃，表单会显示最新保存的复核结论与依据。"),
      confirmLabel: keepDraft ? tr(context, "保留草稿继续复核") : tr(context, "重新载入"),
    );
    if (!mounted || !accepted) return;
    store.requireSession(startedSession, elevated: true);
    final latest = store.data.inspections
        .where((r) => r.id == widget.id)
        .firstOrNull;
    if (latest == null || !shownVersion.matches(latest)) {
      throw StateError('记录再次发生变化，请重新核对');
    }
    final draftNote = note.text, draftVerdict = verdict;
    setState(() {
      _adopt(latest, store.session);
      if (keepDraft) {
        note.text = draftNote;
        verdict = draftVerdict;
      }
    });
  }

  Widget _unavailableDraft(String reason) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, "未提交的复核草稿"),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(reason),
          const SizedBox(height: 12),
          Text(
            tr(context, "复核结论：{0}", [
              verdict == 'pass' ? tr(context, "放行") : tr(context, "判退"),
            ]),
          ),
          const SizedBox(height: 8),
          SelectableText(
            note.text.isEmpty ? tr(context, "（未填写依据）") : note.text,
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (_draftSession != null && _draftSession != s.session) {
      _version = null;
      note.clear();
      _draftSession = null;
      _conflicted = false;
    }
    final found = s.data.inspections.where((r) => r.id == widget.id);
    if (found.isEmpty) {
      return _guard(
        DetailScaffold(
          title: tr(context, "检测详情"),
          children: [
            EmptyState(
              title: tr(context, "记录已移除"),
              subtitle: tr(context, "示例清理或备份恢复后，这条记录已不在当前工作区。"),
            ),
            if (_dirty)
              _unavailableDraft(tr(context, "记录已移除，无法提交。可以复制草稿中的文字后返回。")),
          ],
        ),
      );
    }
    final r = found.first;
    if (_version == null || (!_dirty && !_saving && !_version!.matches(r))) {
      _adopt(r, s.session);
    } else {
      _conflicted = !_version!.matches(r);
    }
    return _guard(
      DetailScaffold(
        title: tr(context, "检测详情"),
        actions: [
          if (s.engineer)
            IconButton(
              tooltip: tr(context, "导出此记录"),
              onPressed: () => perform(context, () async {
                openPage(
                  context,
                  CsvExportPage(
                    snapshot: s.captureCsv([r]),
                    session: s.session,
                    scope: tr(context, "单条检测记录"),
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
                r.passed ? tr(context, "原始判定 PASS") : tr(context, "原始判定 FAIL"),
                color: r.passed ? green : red,
              ),
              if (r.pending) Tag(tr(context, "等待复核"), color: amber),
              if (r.sample) Tag(tr(context, "示例记录")),
              if (r.archived) Tag(tr(context, "已归档"), color: Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 20),
          PartPreview(defect: !r.passed, height: 260),
          const SizedBox(height: 12),
          Text(
            tr(context, "画面为程序绘制的合成工件示意，不代表真实相机采集。"),
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
          SectionHeading(tr(context, "检测证据")),
          GlassPanel(
            child: Column(
              children: [
                InfoRow(tr(context, "记录 ID"), r.id),
                InfoRow(
                  tr(context, "缺陷类型"),
                  r.defect.isEmpty ? tr(context, "未检出") : tr(context, r.defect),
                ),
                InfoRow(
                  tr(context, "置信度"),
                  '${(r.confidence * 100).toStringAsFixed(2)}%',
                ),
                InfoRow(tr(context, "配方快照"), r.recipeName),
                if (r.recipeSnapshot.isNotEmpty) ...[
                  InfoRow(
                    tr(context, "检测时灵敏度"),
                    '${r.recipeSnapshot['sensitivity']}%',
                  ),
                  InfoRow(
                    tr(context, "检测时阈值"),
                    '${((r.recipeSnapshot['confidence'] as num) * 100).round()}%',
                  ),
                  InfoRow(
                    tr(context, "启用缺陷"),
                    (r.recipeSnapshot['defects'] as List).join('、'),
                  ),
                ],
                InfoRow(tr(context, "操作人员"), r.operatorName),
                InfoRow(tr(context, "检测时间"), zonedStamp(r.at, precise: true)),
              ],
            ),
          ),
          if (r.review != null) ...[
            SectionHeading(tr(context, "最近一次复核")),
            GlassPanel(
              child: Column(
                children: [
                  InfoRow(
                    tr(context, "复核结果"),
                    r.review == 'pass' ? tr(context, "放行") : tr(context, "判退"),
                  ),
                  InfoRow(tr(context, "复核人员"), r.reviewer!),
                  InfoRow(
                    tr(context, "复核时间"),
                    zonedStamp(r.reviewedAt!, precise: true),
                  ),
                  InfoRow(tr(context, "复核依据"), r.note),
                ],
              ),
            ),
          ],
          if (s.engineer && !r.archived) ...[
            SectionHeading(
              r.review == null ? tr(context, "质量复核") : tr(context, "更新复核结论"),
            ),
            if (_conflicted && !_saving) ...[
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tag(tr(context, "记录已更新"), color: amber),
                    const SizedBox(height: 10),
                    Text(tr(context, "草稿已保留。请核对上方最新记录，再选择重新载入，或保留草稿继续复核。")),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () =>
                              perform(context, () => _reload(s, r)),
                          child: Text(tr(context, "载入最新复核")),
                        ),
                        TextButton(
                          onPressed: () => perform(
                            context,
                            () => _reload(s, r, keepDraft: true),
                          ),
                          child: Text(tr(context, "核对后保留草稿")),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Form(
              key: form,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, "原始检测结果将保留，复核结论和每次变更均写入操作日志。"),
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'reject',
                          label: Text(tr(context, "判退")),
                          icon: const Icon(Icons.close),
                        ),
                        ButtonSegment(
                          value: 'pass',
                          label: Text(tr(context, "放行")),
                          icon: const Icon(Icons.check),
                        ),
                      ],
                      selected: {verdict},
                      onSelectionChanged: _saving
                          ? null
                          : (v) => setState(() => verdict = v.first),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: note,
                      enabled: !_saving,
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final error = reviewNoteError(value ?? '');
                        return error == null ? null : trMessage(context, error);
                      },
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        labelText: tr(context, "复核依据"),
                        hintText: tr(context, "描述核查发现与处理原因，至少 3 个字"),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_dirty || r.review != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              liveRegion: _conflicted,
                              child: Text(
                                _conflicted
                                    ? tr(context, "记录已更新，请先核对上方提示")
                                    : _dirty
                                    ? tr(context, "有未提交的修改")
                                    : tr(context, "与已保存的复核一致"),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                          if (_dirty && !_conflicted)
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => perform(context, () => _reload(s, r)),
                              child: Text(tr(context, "撤销修改")),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: BusyButton(
                        label: tr(context, "提交复核"),
                        icon: Icons.fact_check_outlined,
                        onPressed:
                            _conflicted ||
                                _saving ||
                                (r.review != null && !_dirty)
                            ? null
                            : () async {
                                if (!form.currentState!.validate()) return;
                                final startedSession = s.session;
                                final version = _version!;
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(() => _saving = true);
                                try {
                                  await s.review(
                                    r.id,
                                    verdict,
                                    note.text,
                                    expectedVersion: version,
                                  );
                                  if (!mounted || s.session != startedSession) {
                                    return;
                                  }
                                  final current = s.data.inspections
                                      .where((x) => x.id == r.id)
                                      .firstOrNull;
                                  if (current != null) {
                                    setState(() => _adopt(current, s.session));
                                  }
                                  if (context.mounted) {
                                    toast(context, tr(context, "复核已保存"));
                                  }
                                } finally {
                                  if (mounted) setState(() => _saving = false);
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_dirty && (r.archived || !s.engineer))
            _unavailableDraft(
              r.archived
                  ? tr(context, "记录已归档，无法提交。可以复制草稿，或恢复记录后重新核对。")
                  : tr(context, "当前账户无法提交复核。可以复制草稿中的文字后返回。"),
            ),
          if (!s.engineer) ...[
            const SizedBox(height: 18),
            GlassPanel(child: Text(tr(context, "当前为操作员账户。请由质量工程师或管理员完成复核。"))),
          ],
          AuditTrail(target: s.recordTarget(r), legacySerial: r.serial),
          if (s.engineer) ...[
            const SizedBox(height: 20),
            if (_dirty && !r.archived) ...[
              Text(
                tr(context, "先提交或撤销复核草稿，再归档记录。"),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: r.pending || _saving || (_dirty && !r.archived)
                  ? null
                  : () => perform(context, () async {
                      if (await confirm(
                        context,
                        r.archived
                            ? tr(context, "恢复记录？")
                            : tr(context, "归档记录？"),
                        r.archived
                            ? tr(context, "记录会重新出现在检测列表和统计中。")
                            : tr(context, "记录将移入归档区，可随时恢复。"),
                      )) {
                        await s.archive({r.id}, !r.archived);
                      }
                    }),
              icon: Icon(
                r.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              label: Text(
                r.archived ? tr(context, "恢复此记录") : tr(context, "归档此记录"),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

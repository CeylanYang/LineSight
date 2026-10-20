import '../l10n.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../backup.dart';
import '../models.dart';
import 'backup_transfer.dart';
import '../ui.dart';

RestoreComparison _compare(List<Workspace> pair) =>
    RestoreComparison(pair[0], pair[1]);

BackupDocument _resolveTime((BackupDocument, LegacyTimeChoice) input) =>
    input.$1.resolveLegacyTimes(input.$2);

class RestorePreviewPage extends StatefulWidget {
  final Workspace incoming;
  final String fileName;
  final BackupDocument? document;
  final String? pointId;
  const RestorePreviewPage({
    super.key,
    required this.incoming,
    required this.fileName,
    this.document,
    this.pointId,
  });
  @override
  State<RestorePreviewPage> createState() => _RestorePreviewPageState();
}

class _RestorePreviewPageState extends State<RestorePreviewPage> {
  BackupDocument? document;
  Workspace get incoming => document?.workspace ?? widget.incoming;
  bool resolvingTime = false, acknowledged = false;
  String? timeError, selectedTime;
  int choiceGeneration = 0;
  int comparedRevision = -1;
  @override
  void initState() {
    super.initState();
    document = widget.document;
    if (document?.legacyChoice != null) {
      selectedTime =
          document!.legacyChoice!.offsetMinutes?.toString() ?? 'local';
    }
  }

  Future<void> chooseTime(String value) async {
    final generation = ++choiceGeneration;
    final source = document!;
    setState(() {
      selectedTime = value;
      resolvingTime = true;
      acknowledged = false;
      timeError = null;
    });
    try {
      final resolved = await compute(_resolveTime, (
        source,
        value == 'local'
            ? const LegacyTimeChoice.local()
            : LegacyTimeChoice.fixed(int.parse(value)),
      ));
      if (!mounted || generation != choiceGeneration) return;
      final s = AppScope.of(context);
      setState(() {
        document = resolved;
        comparedRevision = s.revision;
        comparison = compute(_compare, [s.data, incoming]);
        resolvingTime = false;
      });
    } catch (error) {
      if (!mounted || generation != choiceGeneration) return;
      setState(() {
        resolvingTime = false;
        timeError = error is FormatException
            ? error.message
            : tr(context, "无法解释旧时间，请重新选择");
      });
    }
  }

  Future<RestoreComparison>? comparison;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (comparedRevision != s.revision) {
      comparedRevision = s.revision;
      comparison = compute(_compare, [s.data, incoming]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), undo = widget.pointId != null;
    final timeReady =
        !resolvingTime &&
        timeError == null &&
        (document?.readyToRestore ?? true);
    final needsTimeChoice = (document?.legacyTimeCount ?? 0) > 0;
    final pointValid = !undo || s.restorePoint?.id == widget.pointId;
    return DetailScaffold(
      title: undo ? tr(context, "还原点预览") : tr(context, "备份恢复预览"),
      children: [
        PageHeading(
          eyebrow: undo ? 'RESTORE / UNDO' : 'BACKUP / PREVIEW',
          title: undo ? tr(context, "撤回前，看清影响。") : tr(context, "恢复前，先确认。"),
          subtitle: tr(context, "逐项比较当前数据与{0}，包含归档记录。", [
            undo ? tr(context, "还原点") : tr(context, "备份"),
          ]),
        ),
        GlassPanel(
          child: Column(
            children: [
              InfoRow(
                undo ? tr(context, "还原来源") : tr(context, "备份文件"),
                widget.fileName,
              ),
              if (document != null) ...[
                InfoRow(tr(context, "文件大小"), fileSize(document!.bytes)),
                InfoRow(
                  tr(context, "导出时间"),
                  !timeReady
                      ? tr(context, "等待时间解释")
                      : document!.exportedAt == null
                      ? tr(context, "旧备份未记录")
                      : zonedStamp(document!.exportedAt!),
                ),
                InfoRow(
                  tr(context, "格式检查"),
                  tr(context, "通过 · LineSight {0}", [document!.format]),
                ),
                if (document!.checksum != null)
                  InfoRow(tr(context, "完整性校验"), tr(context, "SHA-256 通过")),
              ],
              InfoRow(
                tr(context, "检测记录"),
                '${s.data.inspections.length} → ${incoming.inspections.length}',
              ),
              InfoRow(
                tr(context, "配方"),
                '${s.data.recipes.length} → ${incoming.recipes.length}',
              ),
              InfoRow(
                tr(context, "工位"),
                '${s.data.stations.length} → ${incoming.stations.length}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (needsTimeChoice) ...[
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(tr(context, "旧备份时间")),
                Text(
                  tr(
                    context,
                    "{0} 个时间没有时区信息。请选择原设备记录这些时间时使用的规则；已经带时区的时间会保持原时刻。",
                    [document!.legacyTimeCount],
                  ),
                  style: const TextStyle(height: 1.7),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedTime,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(context, "来源时间解释"),
                    hintText: tr(context, "请选择"),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'local',
                      child: Text(tr(context, "本机时区历史规则")),
                    ),
                    for (final offset in [
                      480,
                      0,
                      for (var m = -720; m <= 840; m += 15)
                        if (m != 480 && m != 0) m,
                    ])
                      DropdownMenuItem(
                        value: '$offset',
                        child: Text(
                          tr(context, "固定 {0}", [utcOffsetLabel(offset)]),
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) chooseTime(v);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    context,
                    "固定偏移适用于所有旧时间，不会切换夏令时。来源使用夏令时且跨季节时，应在对应时区设备上选历史规则；重复出现的钟表时间仍需人工核对。中国标准时间可选 UTC+08:00。",
                  ),
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
                if (resolvingTime)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (timeError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      trMessage(context, timeError!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (timeReady) ...[
                  const SizedBox(height: 12),
                  if (document!.legacyExample != null) ...[
                    InfoRow(
                      tr(context, "原始时间"),
                      document!.legacyExample!.replaceFirst('T', ' '),
                    ),
                    InfoRow(
                      tr(context, "本地时间"),
                      zonedStamp(document!.interpretedExample!, precise: true),
                    ),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(context, "已确认时间解释及下方恢复影响")),
                    value: acknowledged,
                    onChanged: (v) => setState(() => acknowledged = v ?? false),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (!pointValid)
          EmptyState(
            title: tr(context, "还原点已更新"),
            subtitle: tr(context, "请返回数据管理，重新打开当前还原点。"),
          ),
        if (pointValid && timeReady)
          FutureBuilder<RestoreComparison>(
            future: comparison,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return GlassPanel(
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Text(tr(context, "正在逐项比较数据…"))),
                    ],
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return EmptyState(
                  title: tr(context, "无法完成数据比较"),
                  subtitle: tr(context, "请返回并重新选择备份。当前数据尚未修改。"),
                );
              }
              final diff = snapshot.data!, expectedRevision = comparedRevision;
              final comparedDocument = document, comparedIncoming = incoming;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeading(tr(context, "恢复影响")),
                  AdaptiveGrid(
                    minWidth: 130,
                    children: [
                      Metric(
                        label: tr(context, "新增对象"),
                        value: '${diff.count(RestoreChangeKind.added)}',
                        icon: Icons.add_circle_outline,
                        color: green,
                      ),
                      Metric(
                        label: tr(context, "内容替换"),
                        value: '${diff.count(RestoreChangeKind.changed)}',
                        icon: Icons.swap_horiz_rounded,
                        color: blue,
                      ),
                      Metric(
                        label: tr(context, "当前移除"),
                        value: '${diff.count(RestoreChangeKind.removed)}',
                        icon: Icons.remove_circle_outline,
                        color: amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(context, "{0} 个对象内容相同。以下数量按记录、配方和工位的 ID 逐项比较。", [
                      diff.unchanged,
                    ]),
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  for (final type in ['检测记录', '配方', '工位'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassPanel(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(tr(context, type)),
                          subtitle: Text(
                            tr(context, "新增 {0} · 替换 {1} · 移除 {2}", [
                              diff.count(RestoreChangeKind.added, type: type),
                              diff.count(RestoreChangeKind.changed, type: type),
                              diff.count(RestoreChangeKind.removed, type: type),
                            ]),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => openPage(
                            context,
                            RestoreChangesPage(
                              changes: diff.changes
                                  .where((c) => c.type == type)
                                  .toList(),
                              type: type,
                            ),
                          ),
                        ),
                      ),
                    ),
                  SectionHeading(tr(context, "日志与还原保障")),
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (undo)
                          Text(
                            tr(context, "当前操作日志全部保留，并追加撤回记录。"),
                            style: const TextStyle(height: 1.7),
                          )
                        else ...[
                          InfoRow(
                            tr(context, "追加日志"),
                            tr(context, "{0} 条", [diff.newAudits]),
                          ),
                          InfoRow(
                            tr(context, "相同日志"),
                            tr(context, "{0} 条，去重保留", [diff.duplicateAudits]),
                          ),
                          if (diff.conflictingAudits > 0)
                            InfoRow(
                              tr(context, "同 ID 内容不同"),
                              tr(context, "{0} 条，以本机原日志为准", [
                                diff.conflictingAudits,
                              ]),
                            ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          undo
                              ? tr(
                                  context,
                                  "此操作会替换恢复之后产生或修改的业务数据，并用完当前还原点。请先备份需要保留的内容。",
                                )
                              : tr(
                                  context,
                                  "恢复前将保存当前业务数据为本机还原点{0}。本机账户、密码和外观设置保持不变。",
                                  [
                                    s.restorePoint == null
                                        ? ''
                                        : tr(context, "，覆盖上一个还原点"),
                                  ],
                                ),
                          style: const TextStyle(height: 1.7),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  BusyButton(
                    label: tr(context, "先备份当前数据"),
                    icon: Icons.save_alt_rounded,
                    onPressed: s.engineer
                        ? () async =>
                              openPage(context, const BackupExportPage())
                        : null,
                  ),
                  const SizedBox(height: 12),
                  BusyButton(
                    label: undo
                        ? tr(context, "确认撤回恢复")
                        : tr(context, "确认恢复此备份"),
                    icon: Icons.restore_rounded,
                    onPressed: !s.admin || (needsTimeChoice && !acknowledged)
                        ? null
                        : () async {
                            final session = s.session;
                            if (!await confirm(
                              context,
                              undo
                                  ? tr(context, "恢复到此还原点？")
                                  : tr(context, "用此备份替换业务数据？"),
                              tr(context, '新增 {0} · 替换 {1} · 移除 {2}', [
                                    diff.count(RestoreChangeKind.added),
                                    diff.count(RestoreChangeKind.changed),
                                    diff.count(RestoreChangeKind.removed),
                                  ]) +
                                  (undo
                                      ? tr(context, "还原点将在成功后移除。")
                                      : tr(context, "当前数据会自动保留为还原点。")) +
                                  (comparedDocument?.timeInterpretation == null
                                      ? ''
                                      : tr(context, "\n时间解释：{0}", [
                                          trMessage(
                                            context,
                                            comparedDocument!
                                                .timeInterpretation!,
                                          ),
                                        ])),
                              confirmLabel: undo
                                  ? tr(context, "撤回恢复")
                                  : tr(context, "恢复"),
                            )) {
                              return;
                            }
                            s.requireSession(session, owner: true);
                            if (undo) {
                              await s.undoRestore(
                                expectedRevision: expectedRevision,
                                expectedPointId: widget.pointId,
                              );
                            } else if (comparedDocument != null) {
                              await s.restoreDocument(
                                comparedDocument,
                                expectedRevision: expectedRevision,
                              );
                            } else {
                              await s.restore(
                                comparedIncoming,
                                expectedRevision: expectedRevision,
                              );
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                              toast(
                                context,
                                undo
                                    ? tr(context, "已还原恢复前的数据")
                                    : tr(context, "备份已恢复"),
                              );
                            }
                          },
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class RestoreChangesPage extends StatefulWidget {
  final List<RestoreChange> changes;
  final String type;
  const RestoreChangesPage({
    super.key,
    required this.changes,
    required this.type,
  });
  @override
  State<RestoreChangesPage> createState() => _RestoreChangesPageState();
}

class _RestoreChangesPageState extends State<RestoreChangesPage> {
  String query = '';
  RestoreChangeKind? kind;
  int limit = 30;
  @override
  Widget build(BuildContext context) {
    final rows = widget.changes
        .where(
          (c) =>
              (kind == null || c.kind == kind) &&
              '${c.label} ${c.id}'.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return DetailScaffold(
      title: tr(context, "{0}变更", [tr(context, widget.type)]),
      children: [
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: tr(context, "搜索名称或 ID"),
          ),
          onChanged: (v) => setState(() {
            query = v;
            limit = 30;
          }),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(tr(context, "全部")),
              selected: kind == null,
              onSelected: (_) => setState(() {
                kind = null;
                limit = 30;
              }),
            ),
            for (final k in RestoreChangeKind.values)
              ChoiceChip(
                label: Text(switch (k) {
                  RestoreChangeKind.added => tr(context, "新增"),
                  RestoreChangeKind.changed => tr(context, "替换"),
                  RestoreChangeKind.removed => tr(context, "移除"),
                }),
                selected: kind == k,
                onSelected: (_) => setState(() {
                  kind = k;
                  limit = 30;
                }),
              ),
          ],
        ),
        SectionHeading(tr(context, "{0} 个变更", [rows.length])),
        if (rows.isEmpty)
          EmptyState(
            title: tr(context, "暂无变更"),
            subtitle: tr(context, "没有符合当前筛选条件的变更。"),
          ),
        ...rows
            .take(limit)
            .map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(c.label),
                    subtitle: Text('${tr(context, c.actionLabel)} · ${c.id}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        openPage(context, RestoreChangeDetailPage(change: c)),
                  ),
                ),
              ),
            ),
        if (rows.length > limit)
          OutlinedButton(
            onPressed: () => setState(() => limit += 30),
            child: Text(tr(context, "加载更多（剩余 {0} 个）", [rows.length - limit])),
          ),
        const SizedBox(height: 16),
        Text(
          tr(context, "这里显示打开预览时的比较结果。返回恢复预览后会按当前工作区重新比较。"),
          style: const TextStyle(fontSize: 12, height: 1.6),
        ),
      ],
    );
  }
}

class RestoreChangeDetailPage extends StatelessWidget {
  final RestoreChange change;
  const RestoreChangeDetailPage({super.key, required this.change});
  static const labels = {
    'name': '名称',
    'version': '版本',
    'material': '材料',
    'sensitivity': '灵敏度（%）',
    'confidence': '置信度',
    'defects': '启用缺陷',
    'line': '产线',
    'running': '运行状态',
    'recipeId': '配方 ID',
    'stationId': '工位 ID',
    'recipeName': '配方名称',
    'recipeSnapshot': '检测时配方快照',
    'serial': '序列号',
    'at': '检测时间',
    'passed': '原始结果',
    'defect': '缺陷',
    'operatorName': '操作人',
    'note': '复核依据',
    'review': '复核结果',
    'reviewer': '复核人',
    'reviewedAt': '复核时间',
    'archived': '归档状态',
    'sample': '示例标记',
  };
  String display(BuildContext context, Object? value) {
    if (value == null) return tr(context, "未设置");
    if (value is bool) return value ? tr(context, "是") : tr(context, "否");
    if (value is List) return value.join('、');
    if (value is Map) {
      return value.entries
          .map(
            (e) =>
                '${tr(context, labels[e.key] ?? e.key)}：${display(context, e.value)}',
          )
          .join('\n');
    }
    if (value == 'pass') return tr(context, "放行");
    if (value == 'reject') return tr(context, "判退");
    return '$value'.isEmpty ? tr(context, "（空）") : '$value';
  }

  String fieldValue(BuildContext context, String key, Object? value) {
    if ((key == 'at' || key == 'reviewedAt') && value is String) {
      return zonedStamp(parseInstant(value), precise: true);
    }
    if (value is bool) {
      return switch (key) {
        'passed' => value ? tr(context, "合格 PASS") : tr(context, "不合格 FAIL"),
        'running' => value ? tr(context, "运行中") : tr(context, "已暂停"),
        'archived' => value ? tr(context, "已归档") : tr(context, "未归档"),
        'sample' => value ? tr(context, "示例 / 模拟") : tr(context, "非示例"),
        _ => display(context, value),
      };
    }
    if (key == 'confidence' && value is num) {
      return '${(value * 100).toStringAsFixed(2)}%';
    }
    return display(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final c = change;
    final keys = {...?c.before?.keys, ...?c.after?.keys}.where(
      (key) =>
          key != 'id' &&
          jsonEncode(c.before?[key]) != jsonEncode(c.after?[key]),
    );
    return DetailScaffold(
      title: '${tr(context, c.type)} · ${tr(context, c.actionLabel)}',
      children: [
        PageHeading(
          eyebrow: 'RESTORE / CHANGE',
          title: c.label,
          subtitle: c.id,
        ),
        ...keys.map(
          (key) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, labels[key] ?? key),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    tr(context, "当前"),
                    c.before == null
                        ? tr(context, "不存在")
                        : fieldValue(context, key, c.before?[key]),
                  ),
                  const Divider(height: 24),
                  InfoRow(
                    tr(context, "恢复后"),
                    c.after == null
                        ? tr(context, "不存在")
                        : fieldValue(context, key, c.after?[key]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

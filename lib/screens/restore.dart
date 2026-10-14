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
        timeError = error is FormatException ? error.message : '无法解释旧时间，请重新选择';
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
      title: undo ? '还原点预览' : '备份恢复预览',
      children: [
        PageHeading(
          eyebrow: undo ? 'RESTORE / UNDO' : 'BACKUP / PREVIEW',
          title: undo ? '撤回前，看清影响。' : '恢复前，先确认。',
          subtitle: '逐项比较当前数据与${undo ? '还原点' : '备份'}，包含归档记录。',
        ),
        GlassPanel(
          child: Column(
            children: [
              InfoRow(undo ? '还原来源' : '备份文件', widget.fileName),
              if (document != null) ...[
                InfoRow('文件大小', fileSize(document!.bytes)),
                InfoRow(
                  '导出时间',
                  !timeReady
                      ? '等待时间解释'
                      : document!.exportedAt == null
                      ? '旧备份未记录'
                      : zonedStamp(document!.exportedAt!),
                ),
                InfoRow('格式检查', '通过 · LineSight ${document!.format}'),
                if (document!.checksum != null)
                  const InfoRow('完整性校验', 'SHA-256 通过'),
              ],
              InfoRow(
                '检测记录',
                '${s.data.inspections.length} → ${incoming.inspections.length}',
              ),
              InfoRow(
                '配方',
                '${s.data.recipes.length} → ${incoming.recipes.length}',
              ),
              InfoRow(
                '工位',
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
                const SectionHeading('旧备份时间'),
                Text(
                  '${document!.legacyTimeCount} 个时间没有时区信息。请选择原设备记录这些时间时使用的规则；已经带时区的时间会保持原时刻。',
                  style: const TextStyle(height: 1.7),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedTime,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '来源时间解释',
                    hintText: '请选择',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'local',
                      child: Text('本机时区历史规则'),
                    ),
                    for (final offset in [
                      480,
                      0,
                      for (var m = -720; m <= 840; m += 15)
                        if (m != 480 && m != 0) m,
                    ])
                      DropdownMenuItem(
                        value: '$offset',
                        child: Text('固定 ${utcOffsetLabel(offset)}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) chooseTime(v);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  '固定偏移适用于所有旧时间，不会切换夏令时。来源使用夏令时且跨季节时，应在对应时区设备上选历史规则；重复出现的钟表时间仍需人工核对。中国标准时间可选 UTC+08:00。',
                  style: TextStyle(fontSize: 12, height: 1.6),
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
                      timeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (timeReady) ...[
                  const SizedBox(height: 12),
                  if (document!.legacyExample != null) ...[
                    InfoRow(
                      '原始时间',
                      document!.legacyExample!.replaceFirst('T', ' '),
                    ),
                    InfoRow(
                      '本地时间',
                      zonedStamp(document!.interpretedExample!, precise: true),
                    ),
                  ],
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('已确认时间解释及下方恢复影响'),
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
          const EmptyState(title: '还原点已更新', subtitle: '请返回数据管理，重新打开当前还原点。'),
        if (pointValid && timeReady)
          FutureBuilder<RestoreComparison>(
            future: comparison,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const GlassPanel(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 16),
                      Expanded(child: Text('正在逐项比较数据…')),
                    ],
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const EmptyState(
                  title: '无法完成数据比较',
                  subtitle: '请返回并重新选择备份。当前数据尚未修改。',
                );
              }
              final diff = snapshot.data!, expectedRevision = comparedRevision;
              final comparedDocument = document, comparedIncoming = incoming;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeading('恢复影响'),
                  AdaptiveGrid(
                    minWidth: 130,
                    children: [
                      Metric(
                        label: '新增对象',
                        value: '${diff.count(RestoreChangeKind.added)}',
                        icon: Icons.add_circle_outline,
                        color: green,
                      ),
                      Metric(
                        label: '内容替换',
                        value: '${diff.count(RestoreChangeKind.changed)}',
                        icon: Icons.swap_horiz_rounded,
                        color: blue,
                      ),
                      Metric(
                        label: '当前移除',
                        value: '${diff.count(RestoreChangeKind.removed)}',
                        icon: Icons.remove_circle_outline,
                        color: amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${diff.unchanged} 个对象内容相同。以下数量按记录、配方和工位的 ID 逐项比较。',
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  for (final type in ['检测记录', '配方', '工位'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassPanel(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(type),
                          subtitle: Text(
                            '新增 ${diff.count(RestoreChangeKind.added, type: type)} · 替换 ${diff.count(RestoreChangeKind.changed, type: type)} · 移除 ${diff.count(RestoreChangeKind.removed, type: type)}',
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
                  const SectionHeading('日志与还原保障'),
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (undo)
                          const Text(
                            '当前操作日志全部保留，并追加撤回记录。',
                            style: TextStyle(height: 1.7),
                          )
                        else ...[
                          InfoRow('追加日志', '${diff.newAudits} 条'),
                          InfoRow('相同日志', '${diff.duplicateAudits} 条，去重保留'),
                          if (diff.conflictingAudits > 0)
                            InfoRow(
                              '同 ID 内容不同',
                              '${diff.conflictingAudits} 条，以本机原日志为准',
                            ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          undo
                              ? '此操作会替换恢复之后产生或修改的业务数据，并用完当前还原点。请先备份需要保留的内容。'
                              : '恢复前将保存当前业务数据为本机还原点${s.restorePoint == null ? '' : '，覆盖上一个还原点'}。本机账户、密码和外观设置保持不变。',
                          style: const TextStyle(height: 1.7),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  BusyButton(
                    label: '先备份当前数据',
                    icon: Icons.save_alt_rounded,
                    onPressed: s.engineer
                        ? () async =>
                              openPage(context, const BackupExportPage())
                        : null,
                  ),
                  const SizedBox(height: 12),
                  BusyButton(
                    label: undo ? '确认撤回恢复' : '确认恢复此备份',
                    icon: Icons.restore_rounded,
                    onPressed: !s.admin || (needsTimeChoice && !acknowledged)
                        ? null
                        : () async {
                            final session = s.session;
                            if (!await confirm(
                              context,
                              undo ? '恢复到此还原点？' : '用此备份替换业务数据？',
                              '新增 ${diff.count(RestoreChangeKind.added)} 个、替换 ${diff.count(RestoreChangeKind.changed)} 个、移除 ${diff.count(RestoreChangeKind.removed)} 个对象。'
                              '${undo ? '还原点将在成功后移除。' : '当前数据会自动保留为还原点。'}'
                              '${comparedDocument?.timeInterpretation == null ? '' : '\n时间解释：${comparedDocument!.timeInterpretation}'}',
                              confirmLabel: undo ? '撤回恢复' : '恢复',
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
                              toast(context, undo ? '已还原恢复前的数据' : '备份已恢复');
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
      title: '${widget.type}变更',
      children: [
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索名称或 ID',
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
              label: const Text('全部'),
              selected: kind == null,
              onSelected: (_) => setState(() {
                kind = null;
                limit = 30;
              }),
            ),
            for (final k in RestoreChangeKind.values)
              ChoiceChip(
                label: Text(switch (k) {
                  RestoreChangeKind.added => '新增',
                  RestoreChangeKind.changed => '替换',
                  RestoreChangeKind.removed => '移除',
                }),
                selected: kind == k,
                onSelected: (_) => setState(() {
                  kind = k;
                  limit = 30;
                }),
              ),
          ],
        ),
        SectionHeading('${rows.length} 个变更'),
        if (rows.isEmpty)
          const EmptyState(title: '暂无变更', subtitle: '没有符合当前筛选条件的变更。'),
        ...rows
            .take(limit)
            .map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(c.label),
                    subtitle: Text('${c.actionLabel} · ${c.id}'),
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
            child: Text('加载更多（剩余 ${rows.length - limit} 个）'),
          ),
        const SizedBox(height: 16),
        const Text(
          '这里显示打开预览时的比较结果。返回恢复预览后会按当前工作区重新比较。',
          style: TextStyle(fontSize: 12, height: 1.6),
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
  String display(Object? value) {
    if (value == null) return '未设置';
    if (value is bool) return value ? '是' : '否';
    if (value is List) return value.join('、');
    if (value is Map) {
      return value.entries
          .map((e) => '${labels[e.key] ?? e.key}：${display(e.value)}')
          .join('\n');
    }
    if (value == 'pass') return '放行';
    if (value == 'reject') return '判退';
    return '$value'.isEmpty ? '（空）' : '$value';
  }

  String fieldValue(String key, Object? value) {
    if ((key == 'at' || key == 'reviewedAt') && value is String) {
      return zonedStamp(parseInstant(value), precise: true);
    }
    if (value is bool) {
      return switch (key) {
        'passed' => value ? '合格 PASS' : '不合格 FAIL',
        'running' => value ? '运行中' : '已暂停',
        'archived' => value ? '已归档' : '未归档',
        'sample' => value ? '示例 / 模拟' : '非示例',
        _ => display(value),
      };
    }
    if (key == 'confidence' && value is num) {
      return '${(value * 100).toStringAsFixed(2)}%';
    }
    return display(value);
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
      title: '${c.type} · ${c.actionLabel}',
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
                    labels[key] ?? key,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    '当前',
                    c.before == null ? '不存在' : fieldValue(key, c.before?[key]),
                  ),
                  const Divider(height: 24),
                  InfoRow(
                    '恢复后',
                    c.after == null ? '不存在' : fieldValue(key, c.after?[key]),
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

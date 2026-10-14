import 'package:flutter/material.dart';
import '../models.dart';
import '../backup.dart';
import '../ui.dart';
import 'dashboard.dart';
import 'modules.dart';
import 'records.dart';

class AuditPage extends StatefulWidget {
  final AuditTarget? target;
  final String? legacySerial;
  const AuditPage({super.key, this.target, this.legacySerial});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final search = TextEditingController();
  String kind = '全部';
  int limit = 40, days = 0;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), target = widget.target;
    final source = target == null
        ? s.data.audits.reversed.toList()
        : s.history(target.type, target.id, legacySerial: widget.legacySerial);
    final kinds = {'全部', ...source.map((a) => a.action)};
    final selectedKind = kinds.contains(kind) ? kind : '全部';
    final query = search.text.trim().toLowerCase();
    final since = localDay(DateTime.now(), 1 - days);
    final rows = source
        .where(
          (a) =>
              (selectedKind == '全部' || a.action == selectedKind) &&
              (days == 0 ||
                  (!a.at.isBefore(since) &&
                      a.at.isBefore(localDay(DateTime.now(), 1)))) &&
              (query.isEmpty ||
                  '${a.id} ${a.actorId ?? ''} ${a.actor} ${a.action} ${a.detail} ${a.operationId ?? ''}'
                      .toLowerCase()
                      .contains(query) ||
                  a.targets.any(
                    (t) => '${t.id} ${t.label}'.toLowerCase().contains(query),
                  )),
        )
        .toList();
    return DetailScaffold(
      title: target == null ? '操作日志' : '${target.typeLabel}轨迹',
      children: [
        PageHeading(
          eyebrow: 'TRACEABILITY / AUDIT',
          title: target?.label ?? '每一步，都留有依据。',
          subtitle: target == null
              ? '查看操作详情、关联对象和文件导出结果。'
              : '按对象 ID 关联，名称修改后仍可追溯。',
        ),
        TextField(
          controller: search,
          onChanged: (_) => setState(() => limit = 40),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: '搜索人员、动作、名称或 ID',
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    onPressed: () => setState(() {
                      search.clear();
                      limit = 40;
                    }),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey(selectedKind),
          initialValue: selectedKind,
          decoration: const InputDecoration(labelText: '操作类型'),
          items: kinds
              .map((k) => DropdownMenuItem(value: k, child: Text(k)))
              .toList(),
          onChanged: (v) => setState(() {
            kind = v!;
            limit = 40;
          }),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final d in [0, 7, 30])
              ChoiceChip(
                label: Text(d == 0 ? '全部时间' : '近 $d 天'),
                selected: days == d,
                onSelected: (_) => setState(() {
                  days = d;
                  limit = 40;
                }),
              ),
          ],
        ),
        SectionHeading('${rows.length} 条操作'),
        if (rows.isEmpty)
          const EmptyState(title: '暂无匹配的操作', subtitle: '调整搜索词、时间或操作类型。'),
        ...rows
            .take(limit)
            .map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AuditCard(entry: a),
              ),
            ),
        if (rows.length > limit)
          OutlinedButton(
            onPressed: () => setState(() => limit += 40),
            child: Text('加载更多（剩余 ${rows.length - limit} 条）'),
          ),
        const SizedBox(height: 16),
        const Text(
          '旧版日志保留原文；未记录关联 ID 的批量操作无法分配到某一条记录。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.6),
        ),
      ],
    );
  }
}

IconData _auditIcon(String action) => switch (action) {
  '质量复核' => Icons.fact_check_outlined,
  '归档记录' => Icons.archive_outlined,
  '恢复记录' => Icons.unarchive_outlined,
  '导出数据' => Icons.download_done_rounded,
  '开始导出' => Icons.file_download_outlined,
  '取消导出' || '导出未完成' => Icons.do_not_disturb_alt_outlined,
  '配方换型' => Icons.swap_horiz_rounded,
  _ => Icons.history_rounded,
};

class AuditCard extends StatelessWidget {
  final AuditEntry entry;
  const AuditCard({super.key, required this.entry});
  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => openPage(context, AuditDetailPage(id: entry.id)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_auditIcon(entry.action), color: blue, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.action,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              entry.detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  entry.actor,
                  style: const TextStyle(fontSize: 12, color: blue),
                ),
                Text(
                  stamp(entry.at),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.targets.isNotEmpty)
                  Text(
                    '${entry.targets.length} 个关联对象',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class AuditDetailPage extends StatefulWidget {
  final String id;
  const AuditDetailPage({super.key, required this.id});
  @override
  State<AuditDetailPage> createState() => _AuditDetailPageState();
}

class _AuditDetailPageState extends State<AuditDetailPage> {
  int limit = 30;
  String query = '';
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final found = s.data.audits.where((a) => a.id == widget.id);
    if (found.isEmpty) {
      return const DetailScaffold(
        title: '操作详情',
        children: [EmptyState(title: '日志不在当前工作区', subtitle: '返回操作日志查看现有记录。')],
      );
    }
    final a = found.first;
    final byteChange = a.changes.where((c) => c.field == '文件字节数').firstOrNull;
    final hashChange = a.changes.where((c) => c.field == 'SHA-256').firstOrNull;
    final fileBytes = int.tryParse(byteChange?.after ?? '') ?? 0;
    final verifiedFile =
        a.action == '导出数据' &&
        a.detail.startsWith('CSV ·') &&
        fileBytes > 0 &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(hashChange?.after ?? '');
    final changes = verifiedFile
        ? a.changes.where((c) => c != byteChange && c != hashChange).toList()
        : a.changes;
    final targets = a.targets
        .where(
          (t) =>
              '${t.label} ${t.id}'.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final related = a.operationId == null
        ? <AuditEntry>[]
        : s.data.audits
              .where(
                (other) =>
                    other.operationId == a.operationId && other.id != a.id,
              )
              .toList();
    return DetailScaffold(
      title: '操作详情',
      children: [
        PageHeading(
          eyebrow: 'AUDIT / EVENT',
          title: a.action,
          subtitle: '${a.actor} · ${stamp(a.at)}',
        ),
        GlassPanel(
          child: SelectableText(a.detail, style: const TextStyle(height: 1.8)),
        ),
        if (verifiedFile) ...[
          const SectionHeading('文件校验'),
          GlassPanel(
            child: Column(
              children: [
                InfoRow('文件大小', '${fileSize(fileBytes)} · $fileBytes B'),
                InfoRow('SHA-256', hashChange!.after),
              ],
            ),
          ),
        ],
        if (changes.isNotEmpty) ...[
          const SectionHeading('变更前后'),
          ...changes.map(
            (change) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      change.field,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    InfoRow(
                      '之前',
                      change.before.isEmpty ? '（空）' : change.before,
                    ),
                    const Divider(height: 24),
                    InfoRow('之后', change.after.isEmpty ? '（空）' : change.after),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SectionHeading('事件信息'),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow('操作人（当时名称）', a.actor),
              InfoRow('操作时间', zonedStamp(a.at, precise: true)),
              const SizedBox(height: 10),
              const Text(
                '日志 ID',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              SelectableText(a.id),
              if (a.actorId != null) ...[
                const SizedBox(height: 12),
                const Text(
                  '操作人 ID',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                SelectableText(a.actorId!),
              ],
              if (a.operationId != null) ...[
                const SizedBox(height: 12),
                const Text(
                  '导出操作 ID',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                SelectableText(a.operationId!),
              ],
            ],
          ),
        ),
        if (a.operationId != null) ...[
          const SectionHeading('同一次导出'),
          if (related.isEmpty)
            GlassPanel(
              child: Text(
                a.action == '开始导出'
                    ? '尚无完成结果。文件选择器可能仍在等待；若应用中途退出，无法确认文件是否已保存。'
                    : '此工作区未包含该次导出的其他日志。',
                style: const TextStyle(height: 1.6),
              ),
            ),
          ...related.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AuditCard(entry: event),
            ),
          ),
        ],
        SectionHeading('关联对象 · ${a.targets.length}'),
        if (a.targets.isEmpty) const Text('此操作没有单独关联对象，详情以日志原文为准。'),
        if (a.targets.isNotEmpty) ...[
          const Text(
            '显示操作发生时的名称；点击对象查看当前数据。已移除的对象仍保留历史 ID。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 16),
          if (a.targets.length > 10) ...[
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '在关联对象中搜索名称或 ID',
              ),
              onChanged: (v) => setState(() {
                query = v;
                limit = 30;
              }),
            ),
            const SizedBox(height: 12),
          ],
          ...targets.take(limit).map((t) => _targetTile(context, t)),
          if (targets.isEmpty)
            const EmptyState(title: '暂无匹配对象', subtitle: '尝试其他名称或 ID。'),
          if (targets.length > limit)
            OutlinedButton(
              onPressed: () => setState(() => limit += 30),
              child: Text('加载更多（剩余 ${targets.length - limit} 个）'),
            ),
        ],
      ],
    );
  }

  Widget _targetTile(BuildContext context, AuditTarget t) {
    final s = AppScope.of(context);
    final Widget? page = switch (t.type) {
      'record' when s.data.inspections.any((r) => r.id == t.id) =>
        RecordDetailPage(id: t.id),
      'station' when s.data.stations.any((r) => r.id == t.id) => StationPage(
        id: t.id,
      ),
      'recipe' when s.data.recipes.any((r) => r.id == t.id) => RecipeDetailPage(
        id: t.id,
      ),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: ListTile(
          isThreeLine: true,
          title: Text(t.label),
          subtitle: Text(
            '${t.typeLabel}${page == null && t.type != 'account' ? ' · 当前已移除' : ''}\n${t.id}',
          ),
          trailing: page == null ? null : const Icon(Icons.chevron_right),
          onTap: page == null ? null : () => openPage(context, page),
        ),
      ),
    );
  }
}

class AuditTrail extends StatelessWidget {
  final AuditTarget target;
  final String? legacySerial;
  const AuditTrail({super.key, required this.target, this.legacySerial});
  @override
  Widget build(BuildContext context) {
    final rows = AppScope.of(
      context,
    ).history(target.type, target.id, legacySerial: legacySerial);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('处理轨迹 · ${rows.length}'),
        if (rows.isEmpty) const GlassPanel(child: Text('暂无关联操作。历史示例可能没有生成日志。')),
        ...rows
            .take(5)
            .map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AuditCard(entry: a),
              ),
            ),
        if (rows.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => openPage(
              context,
              AuditPage(target: target, legacySerial: legacySerial),
            ),
            icon: const Icon(Icons.manage_search_rounded),
            label: const Text('查看完整轨迹'),
          ),
      ],
    );
  }
}

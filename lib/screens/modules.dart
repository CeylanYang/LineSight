import '../l10n.dart';
import 'audit.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models.dart';
import '../ui.dart';
import 'dashboard.dart';

class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key});
  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  int section = 0;
  String query = '';
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final recipes = s.data.recipes.where(
      (r) => '${r.name} ${r.material} ${r.version}'.toLowerCase().contains(
        query.toLowerCase(),
      ),
    );
    return PageBody(
      children: [
        PageHeading(
          eyebrow: 'CONFIGURATION / MODULES',
          title: tr(context, "配方中心"),
          subtitle: tr(context, "配方参数、工位换型和本机运行状态。"),
          trailing: s.engineer
              ? IconButton.filledTonal(
                  tooltip: tr(context, "创建配方"),
                  onPressed: () => openPage(context, const RecipeEditorPage()),
                  icon: const Icon(Icons.add),
                )
              : null,
        ),
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 0, label: Text(tr(context, "配方"))),
            ButtonSegment(value: 1, label: Text(tr(context, "换型"))),
            ButtonSegment(value: 2, label: Text(tr(context, "系统"))),
          ],
          selected: {section},
          onSelectionChanged: (v) => setState(() => section = v.first),
        ),
        const SizedBox(height: 24),
        if (section == 0) ...[
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr(context, "搜索配方名称、材料或版本"),
            ),
          ),
          const SizedBox(height: 20),
          if (recipes.isEmpty)
            EmptyState(
              title: tr(context, "未找到配方"),
              subtitle: tr(context, "调整关键词，或创建新的检测配方。"),
            ),
          AdaptiveGrid(
            children: recipes.map((r) {
              final used = s.data.stations
                  .where((x) => x.recipeId == r.id)
                  .length;
              return GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.view_in_ar_rounded,
                          size: 32,
                          color: blue,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Tag(
                              used > 0
                                  ? tr(context, "{0} 个工位使用", [used])
                                  : tr(context, "可用"),
                              color: used > 0 ? green : blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(r.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 5),
                    Text(
                      '${r.version} / ${r.material}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    InfoRow(tr(context, "灵敏度"), '${r.sensitivity.round()}%'),
                    InfoRow(
                      tr(context, "最小置信度"),
                      '${(r.confidence * 100).round()}%',
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: r.defects
                          .map((d) => Tag(tr(context, d)))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                openPage(context, RecipeDetailPage(id: r.id)),
                            child: Text(tr(context, "查看详情")),
                          ),
                        ),
                        if (s.engineer) ...[
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: tr(context, "应用到工位"),
                            onPressed: () => openPage(
                              context,
                              ChangeoverPage(recipeId: r.id),
                            ),
                            icon: const Icon(Icons.swap_horiz_rounded),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
        if (section == 1) ...[
          GlassPanel(
            child: Text(
              tr(context, "换型会更新工位的当前配方。历史记录保留检测时的配方名称与版本，每次换型需要填写原因。"),
              style: const TextStyle(height: 1.7),
            ),
          ),
          SectionHeading(tr(context, "工位当前配置")),
          ...s.data.stations.map(
            (station) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassPanel(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(
                    Icons.precision_manufacturing_outlined,
                    color: blue,
                  ),
                  title: Text(trWorkspaceLabel(context, station.name)),
                  subtitle: Text(s.recipe(station.recipeId).label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openPage(
                    context,
                    s.engineer
                        ? ChangeoverPage(stationId: station.id)
                        : StationPage(id: station.id),
                  ),
                ),
              ),
            ),
          ),
          SectionHeading(tr(context, "最近换型")),
          if (!s.data.audits.any((a) => a.action == '配方换型'))
            EmptyState(
              title: tr(context, "暂无换型记录"),
              subtitle: tr(context, "选择一个工位，开始配置它的检测配方。"),
            ),
          ...s.data.audits
              .where((a) => a.action == '配方换型')
              .toList()
              .reversed
              .take(20)
              .map(
                (a) => ListTile(
                  leading: const Icon(Icons.swap_horiz, color: green),
                  title: Text(a.detail),
                  subtitle: Text('${a.actor} · ${stamp(a.at)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openPage(context, AuditDetailPage(id: a.id)),
                ),
              ),
        ],
        if (section == 2) const SystemPanel(),
      ],
    );
  }
}

class RecipeDetailPage extends StatelessWidget {
  final String id;
  const RecipeDetailPage({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.data.recipes.any((r) => r.id == id)) {
      return DetailScaffold(
        title: tr(context, "配方详情"),
        children: [
          EmptyState(
            title: tr(context, "配方已删除"),
            subtitle: tr(context, "返回配方中心查看当前配置。"),
          ),
        ],
      );
    }
    final r = s.recipe(id);
    final stations = s.data.stations.where((x) => x.recipeId == id).toList();
    return DetailScaffold(
      title: tr(context, "配方详情"),
      children: [
        PageHeading(
          eyebrow: 'RECIPE / ${r.version.toUpperCase()}',
          title: r.name,
          subtitle: r.material,
        ),
        PartPreview(height: 230, part: partArtKey(r.name)),
        SectionHeading(tr(context, "检测参数")),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(tr(context, "版本"), r.version),
              InfoRow(tr(context, "灵敏度"), '${r.sensitivity.round()}%'),
              InfoRow(tr(context, "置信度阈值"), '${(r.confidence * 100).round()}%'),
              InfoRow(
                tr(context, "缺陷类别"),
                tr(context, "{0} 项启用", [r.defects.length]),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: r.defects.map((d) => Tag(tr(context, d))).toList(),
              ),
            ],
          ),
        ),
        AuditTrail(target: s.recipeTarget(id)),
        SectionHeading(tr(context, "使用此配方的工位")),
        if (stations.isEmpty) Text(tr(context, "当前没有工位使用此配方。")),
        ...stations.map(
          (x) => ListTile(
            leading: const Icon(
              Icons.precision_manufacturing_outlined,
              color: green,
            ),
            title: Text(x.name),
            subtitle: Text(x.line),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPage(context, StationPage(id: x.id)),
          ),
        ),
        if (s.engineer) ...[
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    openPage(context, ChangeoverPage(recipeId: id)),
                icon: const Icon(Icons.swap_horiz),
                label: Text(tr(context, "应用配方")),
              ),
              OutlinedButton.icon(
                onPressed: () => openPage(context, RecipeEditorPage(recipe: r)),
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr(context, "编辑")),
              ),
              OutlinedButton.icon(
                onPressed: () => openPage(
                  context,
                  RecipeEditorPage(recipe: r, duplicate: true),
                ),
                icon: const Icon(Icons.copy_rounded),
                label: Text(tr(context, "复制为新配方")),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: stations.isNotEmpty
                ? null
                : () => perform(context, () async {
                    if (await confirm(
                      context,
                      tr(context, "删除此配方？"),
                      tr(context, "历史记录中的配方快照会保留。此操作不能撤销。"),
                      confirmLabel: tr(context, "删除"),
                    )) {
                      await s.deleteRecipe(id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  }),
            icon: const Icon(Icons.delete_outline),
            label: Text(
              stations.isNotEmpty
                  ? tr(context, "使用中的配方不能删除")
                  : tr(context, "删除配方"),
            ),
          ),
        ],
      ],
    );
  }
}

class RecipeEditorPage extends StatefulWidget {
  final Recipe? recipe;
  final bool duplicate;
  const RecipeEditorPage({super.key, this.recipe, this.duplicate = false});
  @override
  State<RecipeEditorPage> createState() => _RecipeEditorPageState();
}

class _RecipeEditorPageState extends State<RecipeEditorPage> {
  late final TextEditingController name, version, material;
  late double sensitivity, confidence;
  late Set<String> defects;
  bool dirty = false, saved = false;
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    name = TextEditingController(
      text: r == null
          ? ''
          : widget.duplicate
          ? '${r.name}-COPY'
          : r.name,
    );
    version = TextEditingController(text: r?.version ?? 'v1.0');
    material = TextEditingController(text: r?.material ?? '');
    sensitivity = r?.sensitivity ?? 80;
    confidence = r?.confidence ?? .75;
    defects = (r?.defects ?? ['表面划痕', '边缘缺口']).toSet();
  }

  @override
  void dispose() {
    name.dispose();
    version.dispose();
    material.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return PopScope(
      canPop: !dirty || saved,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop &&
            await confirm(
              context,
              tr(context, "放弃未保存的修改？"),
              tr(context, "配方尚未保存。"),
              confirmLabel: tr(context, "放弃"),
            )) {
          if (context.mounted) {
            setState(() => saved = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.pop(context);
            });
          }
        }
      },
      child: DetailScaffold(
        title: widget.recipe == null || widget.duplicate
            ? tr(context, "创建配方")
            : tr(context, "编辑配方"),
        children: [
          Form(
            key: form,
            onChanged: () {
              if (!dirty) setState(() => dirty = true);
            },
            child: GlassPanel(
              child: Column(
                children: [
                  TextFormField(
                    controller: name,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: tr(context, "配方名称")),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? tr(context, "请填写名称")
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: version,
                    maxLength: 30,
                    decoration: InputDecoration(labelText: tr(context, "配方版本")),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? tr(context, "请填写版本")
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: material,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: tr(context, "工件材料与描述"),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? tr(context, "请填写材料")
                        : null,
                  ),
                ],
              ),
            ),
          ),
          SectionHeading(tr(context, "检测参数")),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, "灵敏度  {0}%", [sensitivity.round()]),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: sensitivity,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${sensitivity.round()}%',
                  onChanged: (v) => setState(() {
                    sensitivity = v;
                    dirty = true;
                  }),
                ),
                Text(
                  tr(context, "调整灵敏度与置信度阈值，设置缺陷识别范围。"),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 20),
                Text(
                  tr(context, "最小置信度  {0}%", [(confidence * 100).round()]),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Slider(
                  value: confidence,
                  min: .5,
                  max: 1,
                  divisions: 50,
                  label: '${(confidence * 100).round()}%',
                  onChanged: (v) => setState(() {
                    confidence = v;
                    dirty = true;
                  }),
                ),
              ],
            ),
          ),
          SectionHeading(tr(context, "启用的缺陷类别")),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                {'表面划痕', '边缘缺口', '孔位偏移', '层间裂纹', '尺寸偏差', '表面气孔', ...defects}
                    .map(
                      (d) => FilterChip(
                        label: Text(tr(context, d)),
                        selected: defects.contains(d),
                        onSelected: (v) => setState(() {
                          dirty = true;
                          v ? defects.add(d) : defects.remove(d);
                        }),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 24),
          BusyButton(
            label: tr(context, "保存配方"),
            icon: Icons.save_outlined,
            onPressed: !s.engineer
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    if (defects.isEmpty) throw StateError('至少启用一个缺陷类别');
                    if (widget.recipe != null &&
                        !widget.duplicate &&
                        s.data.stations.any(
                          (x) => x.recipeId == widget.recipe!.id,
                        )) {
                      if (!await confirm(
                        context,
                        tr(context, "更新正在使用的配方？"),
                        tr(context, "使用此配方的工位将从下一次检测起采用新参数。历史检测记录保持原始快照。"),
                      )) {
                        return;
                      }
                    }
                    await s.saveRecipe(
                      Recipe(
                        id: widget.duplicate
                            ? uid()
                            : widget.recipe?.id ?? uid(),
                        name: name.text.trim(),
                        version: version.text.trim(),
                        material: material.text.trim(),
                        sensitivity: sensitivity,
                        confidence: confidence,
                        defects: defects.toList(),
                      ),
                    );
                    if (context.mounted) {
                      setState(() => saved = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) Navigator.pop(context);
                      });
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class ChangeoverPage extends StatefulWidget {
  final String? stationId, recipeId;
  const ChangeoverPage({super.key, this.stationId, this.recipeId});
  @override
  State<ChangeoverPage> createState() => _ChangeoverPageState();
}

class _ChangeoverPageState extends State<ChangeoverPage> {
  String? stationId, recipeId;
  final reason = TextEditingController();
  @override
  void initState() {
    super.initState();
    stationId = widget.stationId;
    recipeId = widget.recipeId;
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    stationId ??= s.data.stations.first.id;
    recipeId ??= s.data.recipes.first.id;
    final station = s.station(stationId!);
    final next = s.recipe(recipeId!);
    return DetailScaffold(
      title: tr(context, "工位换型"),
      children: [
        PageHeading(
          eyebrow: 'CHANGEOVER / SETUP',
          title: tr(context, "确认下一次检测的标准。"),
          subtitle: tr(context, "选择工位与目标配方，并记录换型原因。"),
        ),
        GlassPanel(
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: stationId,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr(context, "目标工位")),
                items: s.data.stations
                    .map(
                      (x) => DropdownMenuItem(value: x.id, child: Text(x.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => stationId = v),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: recipeId,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr(context, "目标配方")),
                items: s.data.recipes
                    .map(
                      (r) =>
                          DropdownMenuItem(value: r.id, child: Text(r.label)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => recipeId = v),
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "变更预览")),
        GlassPanel(
          child: Column(
            children: [
              InfoRow(tr(context, "当前配方"), s.recipe(station.recipeId).label),
              const Icon(Icons.south_rounded, color: blue),
              InfoRow(tr(context, "目标配方"), next.label),
              InfoRow(tr(context, "工件材料"), next.material),
              InfoRow(tr(context, "灵敏度"), '${next.sensitivity.round()}%'),
              InfoRow(
                tr(context, "最小置信度"),
                '${(next.confidence * 100).round()}%',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: reason,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: tr(context, "换型原因"),
            hintText: tr(context, "例如：切换至下一批铝合金支架"),
          ),
        ),
        const SizedBox(height: 20),
        BusyButton(
          label: station.recipeId == recipeId
              ? tr(context, "此配方已在使用")
              : tr(context, "确认并应用"),
          icon: Icons.check_circle_outline,
          onPressed: !s.engineer || station.recipeId == recipeId
              ? null
              : () async {
                  if (await confirm(
                    context,
                    tr(context, "确认换型？"),
                    tr(context, "{0} 将使用 {1} 进行后续检测。", [
                      trWorkspaceLabel(context, station.name),
                      next.label,
                    ]),
                  )) {
                    await s.changeover(stationId!, recipeId!, reason.text);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
        ),
      ],
    );
  }
}

class SystemPanel extends StatefulWidget {
  const SystemPanel({super.key});
  @override
  State<SystemPanel> createState() => _SystemPanelState();
}

class _SystemPanelState extends State<SystemPanel> {
  String? result;
  int? bytes;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassPanel(
          child: Column(
            children: [
              InfoRow(tr(context, "工作区"), tr(context, "本机工作区")),
              InfoRow(
                tr(context, "本地数据库"),
                s.db.isOpen ? tr(context, "已连接") : tr(context, "未连接"),
              ),
              InfoRow(
                tr(context, "工作区记录"),
                tr(context, "{0} 条", [s.data.inspections.length]),
              ),
              InfoRow(
                tr(context, "配方 / 工位"),
                '${s.data.recipes.length} / ${s.data.stations.length}',
              ),
              InfoRow(
                tr(context, "操作日志"),
                tr(context, "{0} 条", [s.data.audits.length]),
              ),
              if (bytes != null)
                InfoRow(
                  tr(context, "数据库大小"),
                  '${(bytes! / 1024).toStringAsFixed(1)} KB',
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        BusyButton(
          label: tr(context, "运行存储诊断"),
          icon: Icons.health_and_safety_outlined,
          onPressed: () async {
            final rows = await s.db.rawQuery('PRAGMA integrity_check');
            final size = await File(s.db.path).length();
            s.data.validate();
            if (mounted) {
              setState(() {
                result = rows.first.values.first == 'ok'
                    ? tr(context, "检查通过：数据库完整，记录关联有效。")
                    : tr(context, "数据库报告：{0}", [rows.first.values.first]);
                bytes = size;
              });
            }
          },
        ),
        if (result != null) ...[
          const SizedBox(height: 16),
          GlassPanel(child: Text(result!)),
        ],
        SectionHeading(
          tr(context, "工位配置"),
          action: s.engineer
              ? TextButton.icon(
                  onPressed: () => openPage(context, const StationEditorPage()),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr(context, "添加工位")),
                )
              : null,
        ),
        ...s.data.stations.map(
          (station) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.precision_manufacturing_outlined,
              color: blue,
            ),
            title: Text(trWorkspaceLabel(context, station.name)),
            subtitle: Text(
              '${trWorkspaceLabel(context, station.line)} · ${s.recipe(station.recipeId).label}',
            ),
            trailing: Icon(
              s.engineer ? Icons.tune_rounded : Icons.chevron_right,
            ),
            onTap: () => openPage(
              context,
              s.engineer
                  ? StationEditorPage(station: station)
                  : StationPage(id: station.id),
            ),
          ),
        ),
        SectionHeading(tr(context, "运行说明")),
        Text(
          tr(context, "启动工位后可开始检测并生成记录；暂停工位后将停止生成新记录。"),
          style: const TextStyle(height: 1.8),
        ),
      ],
    );
  }
}

class StationEditorPage extends StatefulWidget {
  final Station? station;
  const StationEditorPage({super.key, this.station});
  @override
  State<StationEditorPage> createState() => _StationEditorPageState();
}

class _StationEditorPageState extends State<StationEditorPage> {
  late final TextEditingController name, line;
  String? recipeId;
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.station?.name ?? '');
    line = TextEditingController(text: widget.station?.line ?? 'LINE 03');
    recipeId = widget.station?.recipeId;
  }

  @override
  void dispose() {
    name.dispose();
    line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    recipeId ??= s.data.recipes.first.id;
    return DetailScaffold(
      title: widget.station == null ? tr(context, "添加工位") : tr(context, "编辑工位"),
      children: [
        PageHeading(
          eyebrow: 'STATION / CONFIGURATION',
          title: tr(context, "组织你的产线。"),
          subtitle: tr(context, "新工位初始为暂停状态，准备好后可进入检测台启动。"),
        ),
        Form(
          key: form,
          child: GlassPanel(
            child: Column(
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 80,
                  decoration: InputDecoration(labelText: tr(context, "工位名称")),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? tr(context, "请填写工位名称")
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: line,
                  maxLength: 80,
                  decoration: InputDecoration(labelText: tr(context, "产线名称")),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? tr(context, "请填写产线名称")
                      : null,
                ),
                if (widget.station == null) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: recipeId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr(context, "初始配方")),
                    items: s.data.recipes
                        .map(
                          (r) => DropdownMenuItem(
                            value: r.id,
                            child: Text(r.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => recipeId = v),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        BusyButton(
          label: tr(context, "保存工位"),
          icon: Icons.save_outlined,
          onPressed: () async {
            if (!form.currentState!.validate()) return;
            await s.saveStation(
              Station(
                id: widget.station?.id ?? uid(),
                name: name.text.trim(),
                line: line.text.trim(),
                recipeId: recipeId!,
                running: false,
              ),
            );
            if (context.mounted) Navigator.pop(context);
          },
        ),
        if (widget.station != null) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => openPage(
              context,
              ChangeoverPage(stationId: widget.station!.id),
            ),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: Text(tr(context, "更换检测配方")),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => perform(context, () async {
              if (await confirm(
                context,
                tr(context, "删除工位？"),
                tr(context, "只允许删除已暂停且没有关联检测记录的工位。"),
                confirmLabel: tr(context, "删除"),
              )) {
                await s.deleteStation(widget.station!.id);
                if (context.mounted) Navigator.pop(context);
              }
            }),
            icon: const Icon(Icons.delete_outline),
            label: Text(tr(context, "删除此工位")),
          ),
        ],
      ],
    );
  }
}

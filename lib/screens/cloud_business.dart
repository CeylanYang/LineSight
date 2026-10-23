import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../cloud_account.dart';
import '../cloud_outbox.dart';
import '../cloud_filters.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../ui.dart';
import 'cloud_shell.dart';
import 'cloud_tasks.dart';

Future<Map<int, Uint8List>> cloudReportImages(
  CloudAccount account,
  Map snapshot,
) async {
  final captured = account.draftKey('report-images');
  final workspace = snapshot['workspace_id'];
  final images = <int, Uint8List>{};
  for (final task in snapshot['jobs'] as List? ?? []) {
    for (final photo in task['evidence'] as List? ?? []) {
      if (captured != account.draftKey('report-images') ||
          account.activeWorkspace?['id'] != workspace) {
        throw const CollaborationApiException(403, '请切回原工作区后重试');
      }
      final raw = await account.download(
        'workspaces/$workspace/jobs/${task['id']}/evidence/${photo['id']}/original/',
      );
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(raw),
        targetWidth: 360,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      try {
        final bytes = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (bytes != null) {
          images[photo['id'] as int] = bytes.buffer.asUint8List();
        }
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    }
  }
  if (captured != account.draftKey('report-images') ||
      account.activeWorkspace?['id'] != workspace) {
    throw const CollaborationApiException(403, '请切回原工作区后重试');
  }
  return images;
}

class CloudReportSnapshotPage extends StatelessWidget {
  final Map snapshot;
  final Map<int, Uint8List> images;
  const CloudReportSnapshotPage({
    super.key,
    required this.snapshot,
    required this.images,
  });
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn ||
        account.activeWorkspace?['id'] != snapshot['workspace_id']) {
      return cloudAccessRequired(context);
    }
    const hint = TextStyle(fontSize: 11.5, height: 1.5, color: muted);
    final jobs = (snapshot['jobs'] as List?) ?? const [];
    final metrics = snapshot['metrics'] as Map? ?? const {};
    final filters = Map<String, String>.from(snapshot['filters'] as Map? ?? {});
    String rate(Object? value) =>
        value is num ? '${(value * 100).toStringAsFixed(1)}%' : '—';
    return DetailScaffold(
      title: tr(context, '报告预览'),
      actions: [
        IconButton(
          icon: const Icon(Icons.copy, size: 20),
          tooltip: tr(context, '复制追溯码'),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: '${snapshot['report_id']}'),
            );
            if (context.mounted) toast(context, '已复制');
          },
        ),
      ],
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF15233A), Color(0xFF213B63)],
            ),
            boxShadow: [
              BoxShadow(
                color: ink.withValues(alpha: .22),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.assessment_outlined,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LINESIGHT · QUALITY REPORT',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Color(0xFF9DC0F5),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${snapshot['workspace']}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tag(tr(context, '云端快照'), color: blue),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                '${snapshot['report_id']}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                  letterSpacing: .3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${tr(context, '生成时间')} ${snapshot['generated_at']}',
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.filter_alt_outlined,
                      size: 16,
                      color: Colors.white60,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cloudScopeLabel(context, filters),
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (metrics.isNotEmpty) ...[
          SectionHeader(tr(context, '核心指标'), icon: Icons.insights_outlined),
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth >= 720 ? 3 : 2;
              final width = (c.maxWidth - (columns - 1) * 10) / columns;
              Widget cell(Widget child) => SizedBox(width: width, child: child);
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  cell(
                    StatCard(
                      label: tr(context, '首次通过率'),
                      value: rate(metrics['first_pass_rate']),
                      icon: Icons.verified_outlined,
                      color: green,
                    ),
                  ),
                  cell(
                    StatCard(
                      label: tr(context, '最终放行率'),
                      value: rate(metrics['final_release_rate']),
                      icon: Icons.task_alt,
                      color: blue,
                    ),
                  ),
                  cell(
                    StatCard(
                      label: tr(context, '异常工件'),
                      value: '${metrics['latest_fail_pieces'] ?? 0}',
                      icon: Icons.report_gmailerrorred_outlined,
                      color: red,
                    ),
                  ),
                  cell(
                    StatCard(
                      label: tr(context, '报废工件'),
                      value: '${metrics['latest_scrap_pieces'] ?? 0}',
                      icon: Icons.delete_outline,
                      color: amber,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
        SectionHeader(
          tr(context, '任务清单'),
          icon: Icons.inventory_2_outlined,
          caption: '${jobs.length} ${tr(context, '个任务')}',
        ),
        if (jobs.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(18),
            child: Text(
              tr(context, '当前筛选范围内没有任务。'),
              style: hint,
            ),
          )
        else
          for (final task in jobs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () => openPage(
                        context,
                        CloudTaskPage(
                          job: Map<String, dynamic>.from(task as Map),
                          workspaceId: snapshot['workspace_id'] as int,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Row(
                        children: [
                          PartThumb(
                            partName: '${task['part_name']}',
                            size: 52,
                            defect:
                                (task['exceptions'] as List? ?? []).any(
                                  (e) => e['status'] == 'open',
                                ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${task['part_name']}',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${task['batch_code'] ?? ''} · ${tr(context, '负责人')} ${task['assignee'] ?? '—'}',
                                  style: hint,
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: muted,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${task['id']} · v${task['version']}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: muted,
                            letterSpacing: .2,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${tr(context, '工件数量')} ${task['quantity'] ?? 0}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                    for (final check in task['inspections'] as List? ?? []) ...[
                      const Divider(height: 22),
                      Row(
                        children: [
                          Tag(
                            tr(
                              context,
                              check['verdict'] == 'pass' ? '合格' : '异常',
                            ),
                            color: check['verdict'] == 'pass' ? green : red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${tr(context, '检验轮次')} ${check['round_no']} · ${check['inspector']}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: ink,
                              ),
                            ),
                          ),
                          Text(
                            cloudTimestamp(check['created_at']),
                            style: hint,
                          ),
                        ],
                      ),
                      if ('${check['note'] ?? ''}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text('${check['note']}', style: hint),
                        ),
                      if (check['template_snapshot'] is Map)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            '${check['template_snapshot']['name'] ?? ''} · v${check['template_snapshot']['version'] ?? ''}',
                            style: hint,
                          ),
                        ),
                    ],
                    for (final issue in task['exceptions'] as List? ?? []) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7F4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFE0D6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${tr(context, cloudCategories[issue['category']] ?? '${issue['category']}')} · ${issue['assignee'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: red,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${issue['note'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.5,
                                color: ink,
                              ),
                            ),
                            if ('${issue['resolution'] ?? ''}'
                                .isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                '${tr(context, '处理结果')}：${issue['resolution']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.5,
                                  color: muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if ((task['evidence'] as List? ?? []).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final photo in task['evidence'] as List? ?? [])
                            InkWell(
                              onTap: () => openPage(
                                context,
                                CloudEvidencePage(
                                  jobId: '${task['id']}',
                                  photo: Map<String, dynamic>.from(
                                    photo as Map,
                                  ),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 104,
                                  height: 78,
                                  child: images[photo['id']] != null
                                      ? Image.memory(
                                          images[photo['id']]!,
                                          fit: BoxFit.cover,
                                        )
                                      : const ColoredBox(
                                          color: Color(0xFF101B2B),
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: Colors.white54,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }
}


Future<String?> cloudTextPrompt(BuildContext context, String title) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, title)),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(context, '取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(tr(context, '确认')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class CloudTemplatesPage extends StatelessWidget {
  const CloudTemplatesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    final owner = account.activeWorkspace?['role'] == 'owner';
    return PageBody(
      children: [
        PageHeading(
          eyebrow: 'CONFIGURATION / TEMPLATES',
          title: tr(context, '检查模板'),
          subtitle: tr(context, '统一检查口径，模板版本随检验记录一起归档。'),
          trailing: owner
              ? IconButton.filled(
                  tooltip: tr(context, '发布检查模板'),
                  onPressed: () =>
                      openPage(context, const CloudTemplateEditor()),
                  icon: const Icon(Icons.add, size: 22),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                )
              : null,
        ),
        if (!account.signedIn)
          EmptyState(
            icon: Icons.lock_outline,
            title: tr(context, '需要登录'),
            subtitle: tr(context, '登录后查看任务与检验记录。'),
            action: FilledButton(
              onPressed: () => openPage(context, const CloudLoginPage()),
              child: Text(tr(context, '登录')),
            ),
          )
        else if (account.templates.isEmpty)
          EmptyState(
            icon: Icons.fact_check_outlined,
            title: tr(context, '暂无检查模板'),
            subtitle: tr(context, '发布模板后可快速创建标准化质检任务。'),
            action: owner
                ? FilledButton.icon(
                    onPressed: () =>
                        openPage(context, const CloudTemplateEditor()),
                    icon: const Icon(Icons.add),
                    label: Text(tr(context, '发布检查模板')),
                  )
                : null,
          )
        else ...[
          Row(
            children: [
              _CountPill(
                label: tr(context, '个模板'),
                value: account.templates.length,
                color: blue,
              ),
              const Spacer(),
              Text(
                tr(context, '按工作区版本管理'),
                style: const TextStyle(fontSize: 10.5, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...account.templates.map(
            (template) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassPanel(
                padding: const EdgeInsets.fromLTRB(13, 13, 8, 13),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => openPage(
                      context,
                      _TemplateDetailPage(template: template),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF5699FF), Color(0xFF2A63E8)],
                            ),
                            borderRadius: BorderRadius.all(Radius.circular(15)),
                          ),
                          child: const Icon(
                            Icons.fact_check_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${template['name']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                        color: ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Tag('v${template['version']}', color: blue),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${(template['items'] as List).length} ${tr(context, '检查项')} · ${tr(context, '随检验记录归档')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Color(0xFFA9B8CC),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (owner)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: () =>
                    openPage(context, const CloudTemplateEditor()),
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr(context, '发布检查模板')),
              ),
            ),
        ],
      ],
    );
  }
}

class _TemplateDetailPage extends StatelessWidget {
  final Map<String, dynamic> template;
  const _TemplateDetailPage({required this.template});
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    final items = template['items'] as List;
    return DetailScaffold(
      title: '${template['name']}',
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5699FF), Color(0xFF2A63E8)],
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${template['name']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      children: [
                        Tag('v${template['version']}', color: blue),
                        Tag(
                          '${items.length} ${tr(context, '检查项')}',
                          color: green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionHeader(tr(context, '检查项目'), icon: Icons.checklist_rounded),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: GlassPanel(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: blue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      '${items[i]['label']}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                  ),
                  Tag(
                    tr(
                      context,
                      items[i]['required'] == true ? '必填' : '选填',
                    ),
                    color: items[i]['required'] == true ? amber : muted,
                  ),
                ],
              ),
            ),
          ),
        if (account.activeWorkspace?['role'] == 'owner')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.icon(
              onPressed: () =>
                  openPage(context, CloudTemplateEditor(template: template)),
              icon: const Icon(Icons.publish_outlined, size: 18),
              label: Text(tr(context, '发布新版本')),
            ),
          ),
      ],
    );
  }
}

class CloudTemplateEditor extends StatefulWidget {
  final Map<String, dynamic>? template;
  const CloudTemplateEditor({super.key, this.template});
  @override
  State<CloudTemplateEditor> createState() => _CloudTemplateEditorState();
}

class _CloudTemplateEditorState extends State<CloudTemplateEditor> {
  final name = TextEditingController(), items = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name.text = '${widget.template?['name'] ?? ''}';
    items.text = (widget.template?['items'] as List? ?? [])
        .map((i) => i['label'])
        .join('\n');
    items.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  int get count => items.text
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .length;

  @override
  void dispose() {
    items.removeListener(_refresh);
    name.dispose();
    items.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: tr(context, '发布检查模板'),
    children: [
      GlassPanel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: blue.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.rule_folder_outlined,
                color: blue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, '新版本将覆盖当前默认检查项'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr(context, '历史检验记录保留原模板快照'),
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      SectionHeader(tr(context, '模板信息'), icon: Icons.badge_outlined),
      GlassPanel(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: name,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: tr(context, '模板名称'),
            hintText: tr(context, '例如：外观与尺寸终检'),
          ),
        ),
      ),
      SectionHeader(
        tr(context, '检查项'),
        icon: Icons.checklist_rtl,
        caption: '$count ${tr(context, '项')}',
      ),
      GlassPanel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: items,
              minLines: 5,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: tr(context, '每行一项（3 至 6 项）'),
                hintText: tr(
                  context,
                  '表面划痕\n装配间隙\n关键尺寸\n标识与批次',
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  count >= 3 && count <= 6
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 16,
                  color: count >= 3 && count <= 6 ? green : amber,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    count >= 3 && count <= 6
                        ? tr(context, '检查项数量符合发布要求')
                        : tr(context, '请填写 3 至 6 个检查项'),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: count >= 3 && count <= 6 ? muted : amber,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F1),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: const Color(0xFFFFDCD2)),
            ),
            child: Text(
              trMessage(context, error!),
              style: const TextStyle(fontSize: 12, color: red),
            ),
          ),
        ),
      const SizedBox(height: 18),
      if (busy)
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: LinearProgressIndicator(),
        ),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          onPressed: busy
              ? null
              : () async {
                  final account = CloudScope.of(context),
                      rows = items.text
                          .split('\n')
                          .where((s) => s.trim().isNotEmpty)
                          .toList();
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await account.request(
                      'POST',
                      'workspaces/${account.activeWorkspace!['id']}/templates/',
                      body: {
                        'name': name.text.trim(),
                        'items': [
                          for (var i = 0; i < rows.length; i++)
                            {
                              'id': 'item-${i + 1}',
                              'label': rows[i].trim(),
                              'required': true,
                              'allow_na': true,
                            },
                        ],
                      },
                    );
                    await account.reload();
                    if (context.mounted) Navigator.pop(context);
                  } catch (failure) {
                    if (mounted) setState(() => error = '$failure');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          icon: const Icon(Icons.publish_outlined, size: 19),
          label: Text(tr(context, '发布')),
        ),
      ),
    ],
  );
}

class CloudTeamPage extends StatefulWidget {
  const CloudTeamPage({super.key});
  @override
  State<CloudTeamPage> createState() => _CloudTeamPageState();
}

class _CloudTeamPageState extends State<CloudTeamPage> {
  List<Map<String, dynamic>> members = [];
  bool busy = false, loaded = false;
  String? error, invitation;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      load();
    }
  }

  Future<void> action(Future<void> Function(CloudAccount account) work) async {
    final account = CloudScope.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work(account);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => action((account) async {
    if (account.activeWorkspace == null) return;
    final rows =
        (await account.request(
                  'GET',
                  'workspaces/${account.activeWorkspace!['id']}/members/',
                )
                as List)
            .cast<Map<String, dynamic>>();
    if (mounted) setState(() => members = rows);
  });

  String roleLabel(BuildContext context, Object? role) => tr(
    context,
    switch (role) {
      'owner' => '团队管理员',
      'operator' => '操作成员',
      _ => '只读成员',
    },
  );

  Color roleColor(Object? role) => switch (role) {
    'owner' => amber,
    'operator' => blue,
    _ => muted,
  };

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context),
        workspace = CloudScope.of(context).activeWorkspace;
    if (!account.signedIn) return cloudAccessRequired(context);
    final owner = workspace?['role'] == 'owner' && !account.demoAccount;
    const hint = TextStyle(fontSize: 11.5, height: 1.5, color: muted);
    Future<void> createTeam() async {
      final name = await cloudTextPrompt(context, '创建团队');
      if (name == null || name.isEmpty) return;
      await action((account) async {
        final result = await account.request(
          'POST',
          'workspaces/create/',
          body: {'name': name},
        );
        await account.reload();
        await account.selectWorkspace(
          account.workspaces.firstWhere((w) => w['id'] == result['id']),
        );
      });
      if (mounted) await load();
    }

    Future<void> joinTeam() async {
      final code = await cloudTextPrompt(context, '输入邀请码');
      if (code == null || code.isEmpty) return;
      await action((account) async {
        final result = await account.request(
          'POST',
          'workspaces/redeem/',
          body: {'code': code},
        );
        await account.reload();
        await account.selectWorkspace(
          account.workspaces.firstWhere((w) => w['id'] == result['id']),
        );
      });
      if (mounted) await load();
    }

    Future<void> invite(String role) => action((account) async {
      final result = await account.request(
        'POST',
        'workspaces/${workspace!['id']}/invite/',
        body: {'role': role},
      );
      if (mounted) setState(() => invitation = '${result['code']}');
    });

    return DetailScaffold(
      title: tr(context, '团队与权限'),
      children: [
        HeroBanner(
          eyebrow: 'ACCESS / TEAM',
          title: '${workspace?['name'] ?? ''}',
          subtitle:
              '${workspace?['kind'] == 'team' ? tr(context, '协作团队') : tr(context, '个人工作区')} · ${members.length} ${tr(context, '名成员')}',
          actions: [
            if (!account.demoAccount) ...[
              HeroAction(
                label: tr(context, '创建团队'),
                icon: Icons.group_add_outlined,
                ghost: true,
                onPressed: busy ? null : createTeam,
              ),
              HeroAction(
                label: tr(context, '加入团队'),
                icon: Icons.login,
                ghost: true,
                onPressed: busy ? null : joinTeam,
              ),
            ],
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trMessage(context, error!),
                      style: const TextStyle(fontSize: 12, color: red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (owner) ...[
          SectionHeader(
            tr(context, '邀请成员'),
            icon: Icons.person_add_alt_1_outlined,
            caption: tr(context, '仅团队管理员'),
          ),
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: 'operator',
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: tr(context, '邀请成员权限'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'operator',
                            child: Text(tr(context, '操作成员')),
                          ),
                          DropdownMenuItem(
                            value: 'viewer',
                            child: Text(tr(context, '只读成员')),
                          ),
                        ],
                        onChanged: busy
                            ? null
                            : (role) => invite(role ?? 'operator'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () => invite('operator'),
                      icon: const Icon(Icons.vpn_key_outlined, size: 17),
                      label: Text(tr(context, '生成邀请码')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tr(context, '切换权限会立即生成新的邀请码'),
                  style: hint,
                ),
                if (invitation != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F8FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: hairline),
                    ),
                    child: Column(
                      children: [
                        SelectableText(
                          invitation!,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.4,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: invitation!),
                            );
                            if (context.mounted) toast(context, '已复制');
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(tr(context, '复制邀请码')),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        SectionHeader(
          tr(context, '团队成员'),
          icon: Icons.groups_2_outlined,
          caption: '${members.length} ${tr(context, '人')}',
        ),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < members.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 66),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 2,
                  ),
                  leading: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          roleColor(members[i]['role']).withValues(alpha: .75),
                          roleColor(members[i]['role']),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${members[i]['display_name'] ?? members[i]['username'] ?? '?'}'
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  title: Text(
                    '${members[i]['display_name'] ?? members[i]['username']}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        Tag(
                          roleLabel(context, members[i]['role']),
                          color: roleColor(members[i]['role']),
                        ),
                        if ('${members[i]['username']}' !=
                            '${members[i]['display_name']}') ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${members[i]['username']}',
                              overflow: TextOverflow.ellipsis,
                              style: hint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing: owner && members[i]['role'] != 'owner'
                      ? PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_horiz,
                            size: 20,
                            color: muted,
                          ),
                          onSelected: (value) async {
                            if (!await confirm(
                              context,
                              tr(context, '更新成员权限'),
                              '${members[i]['display_name'] ?? members[i]['username']}',
                            )) {
                              return;
                            }
                            await action((account) async {
                              final path =
                                  'workspaces/${workspace!['id']}/members/${Uri.encodeComponent('${members[i]['username']}')}/';
                              await account.request(
                                value == 'remove' ? 'DELETE' : 'PATCH',
                                path,
                                body: value == 'remove'
                                    ? null
                                    : {'role': value},
                              );
                            });
                            if (mounted) await load();
                          },
                          itemBuilder: (_) => [
                            for (final e in {
                              'owner': '团队管理员',
                              'operator': '操作成员',
                              'viewer': '只读成员',
                              'remove': '移除成员',
                            }.entries)
                              PopupMenuItem(
                                value: e.key,
                                child: Text(tr(context, e.value)),
                              ),
                          ],
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
        if (!account.demoAccount && workspace?['kind'] == 'team') ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: red,
              side: BorderSide(color: red.withValues(alpha: .35)),
              minimumSize: const Size(0, 46),
            ),
            icon: const Icon(Icons.logout, size: 18),
            label: Text(tr(context, '离开团队')),
            onPressed: busy
                ? null
                : () async {
                    if (!await confirm(
                      context,
                      tr(context, '离开团队'),
                      '${workspace!['name']}',
                    )) {
                      return;
                    }
                    await action((account) async {
                      await account.request(
                        'POST',
                        'workspaces/${workspace['id']}/leave/',
                      );
                      await account.reload();
                    });
                    if (context.mounted && error == null) {
                      Navigator.pop(context);
                    }
                  },
          ),
        ],
      ],
    );
  }
}

class CloudInspectionDetailPage extends StatelessWidget {
  final Map<String, dynamic> record;
  const CloudInspectionDetailPage({super.key, required this.record});
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    final template = record['template_snapshot'] as Map? ?? {};
    final answers = (record['answers'] as List?) ?? const [];
    final evidence = (record['evidence'] as List?) ?? const [];
    final passed = '${record['verdict']}' == 'pass';
    final partName = '${record['part_name']}';
    final items = (template['items'] as List?) ?? const [];
    return DetailScaffold(
      title: partName,
      children: [
        PartArt(
          partName: partName,
          defect: !passed,
          height: 196,
          caption: 'ROUND ${record['round_no']}',
        ),
        const SizedBox(height: 14),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          partName,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: ink,
                            letterSpacing: -.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${record['inspector']} · ${cloudTimestamp(record['created_at'])}',
                          style: const TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tag(
                    tr(context, passed ? '合格' : '异常'),
                    color: passed ? green : red,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InfoGrid(
                items: {
                  tr(context, '批次号'): '${record['batch_code'] ?? ''}',
                  tr(context, '检验轮次'): '${record['round_no'] ?? ''}',
                  tr(context, '检验模板'):
                      '${template['name'] ?? ''}${template['version'] == null ? '' : ' · v${template['version']}'}',
                  if (record['inspected_qty'] != null)
                    tr(context, '工件数量'): '${record['inspected_qty']}',
                  if (record['inspected_qty'] != null)
                    tr(context, '合格'): '${record['pass_qty'] ?? 0}',
                  if (record['inspected_qty'] != null)
                    tr(context, '异常'): '${record['fail_qty'] ?? 0}',
                  if (record['inspected_qty'] != null)
                    tr(context, '报废'): '${record['scrap_qty'] ?? 0}',
                },
              ),
            ],
          ),
        ),
        SectionHeader(
          tr(context, '检验结果'),
          icon: Icons.checklist_rtl,
          caption: '${answers.length} ${tr(context, '项')}',
        ),
        GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: answers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    tr(context, '本次检验未记录检查项。'),
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < answers.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: blue.withValues(alpha: .09),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: blue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    () {
                                      final match = items.where(
                                        (item) =>
                                            item['id'] == answers[i]['id'],
                                      );
                                      return match.isEmpty
                                          ? '${answers[i]['id']}'
                                          : '${match.first['label']}';
                                    }(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: ink,
                                      height: 1.4,
                                    ),
                                  ),
                                  if ('${answers[i]['note'] ?? ''}'
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${answers[i]['note']}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        height: 1.5,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tag(
                              tr(
                                context,
                                switch (answers[i]['result']) {
                                  'pass' => '合格',
                                  'fail' => '异常',
                                  _ => '不适用',
                                },
                              ),
                              color: switch (answers[i]['result']) {
                                'pass' => green,
                                'fail' => red,
                                _ => muted,
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        if ('${record['note'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.edit_note_outlined, size: 18, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${record['note']}',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SectionHeader(
          tr(context, '照片证据'),
          icon: Icons.photo_library_outlined,
          caption: '${evidence.length} ${tr(context, '张')}',
        ),
        if (evidence.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.no_photography_outlined, color: muted),
                const SizedBox(width: 10),
                Text(
                  tr(context, '本次检验未上传照片'),
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < evidence.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => openPage(
                    context,
                    CloudEvidencePage(
                      jobId: '${record['task_id']}',
                      photo: Map<String, dynamic>.from(evidence[i] as Map),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: hairline),
                      boxShadow: const [
                        BoxShadow(
                          color: panelShadow,
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFF101B2B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.image_outlined,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${tr(context, '证据照片')} ${i + 1}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${widgetStage(context, evidence[i]['stage'])} · ${cloudTimestamp(evidence[i]['created_at'])}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  String widgetStage(BuildContext context, Object? stage) => switch (stage) {
    'printing' => tr(context, '打印阶段'),
    'inspection' => tr(context, '检验阶段'),
    'resolution' => tr(context, '处理阶段'),
    _ => tr(context, '现场'),
  };
}

class CloudEvidencePage extends StatefulWidget {
  final String jobId;
  final Map<String, dynamic> photo;
  const CloudEvidencePage({
    super.key,
    required this.jobId,
    required this.photo,
  });
  @override
  State<CloudEvidencePage> createState() => _CloudEvidencePageState();
}

class _CloudEvidencePageState extends State<CloudEvidencePage> {
  Uint8List? bytes;
  bool edge = false, loading = false;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (bytes == null && !loading && error == null) load();
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
    loading = true;
    try {
      final result = await account.download(
        'workspaces/${account.activeWorkspace!['id']}/jobs/${widget.jobId}/evidence/${widget.photo['id']}/${edge ? 'preview' : 'original'}/',
      );
      if (mounted) {
        setState(() {
          bytes = Uint8List.fromList(result);
          error = null;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!CloudScope.of(context).signedIn) {
      return cloudAccessRequired(context);
    }
    const hint = TextStyle(fontSize: 11.5, height: 1.5, color: muted);
    return DetailScaffold(
      title: tr(context, '图片证据'),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.photo_outlined, size: 17),
                      label: Text(tr(context, '原图')),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.gradient_outlined, size: 17),
                      label: Text(tr(context, '边缘参考')),
                    ),
                  ],
                  selected: {edge},
                  onSelectionChanged: loading
                      ? null
                      : (value) {
                          setState(() {
                            edge = value.first;
                            bytes = null;
                          });
                          load();
                        },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.pinch_outlined,
                    size: 15,
                    color: muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr(context, '支持双指缩放与拖动查看细节'),
                      style: hint,
                    ),
                  ),
                  Text(
                    '${tr(context, '证据')} #${widget.photo['id']}',
                    style: hint,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          GlassPanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_off_outlined, color: red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trMessage(context, error!),
                        style: const TextStyle(fontSize: 12, color: red),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(() => error = null);
                    load();
                  },
                  child: Text(tr(context, '重新加载')),
                ),
              ],
            ),
          ),
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Container(
              height: MediaQuery.sizeOf(context).height * .62,
              color: const Color(0xFF0B1422),
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 8,
                child: Center(
                  child: Image.memory(bytes!, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        if (bytes != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${widget.photo['stage'] ?? ''} · ${cloudTimestamp(widget.photo['created_at'])}',
              textAlign: TextAlign.center,
              style: hint,
            ),
          ),
      ],
    );
  }
}

Future<int?> cloudPickPhoto(
  BuildContext context,
  Map<String, dynamic> job, {
  Map<String, dynamic>? issue,
  String stage = 'inspection',
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: Text(tr(context, '拍照')),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(tr(context, '从相册选择')),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  final account = CloudScope.of(context),
      profileId = CloudScope.of(context).profile?['id'],
      workspace = CloudScope.of(context).activeWorkspace!['id'];
  final photo = await ImagePicker().pickImage(
    source: source,
    maxWidth: 3000,
    maxHeight: 3000,
    imageQuality: 88,
  );
  if (photo == null) return null;
  final bytes = await photo.readAsBytes();
  if (bytes.length > 10 * 1024 * 1024) {
    throw const CollaborationApiException(400, '请选择不超过 10 MB 的图片');
  }
  if (profileId != account.profile?['id'] ||
      workspace != account.activeWorkspace?['id']) {
    throw const CollaborationApiException(401, '请先登录');
  }
  final outbox = CloudOutbox(account);
  final item = await outbox.enqueue(
    '${job['id']}',
    bytes,
    stage: stage,
    issueId: issue?['id'] as int?,
  );
  try {
    return await outbox.retry(item['key'] as String);
  } catch (_) {
    throw const CollaborationApiException(503, '图片已保存，请在同步页面重试上传');
  }
}

class CloudReportPage extends StatefulWidget {
  final String? jobId;
  final Map<String, String> filters;
  const CloudReportPage({super.key, this.jobId, this.filters = const {}});
  @override
  State<CloudReportPage> createState() => _CloudReportPageState();
}

class _CloudReportPageState extends State<CloudReportPage> {
  bool busy = false;
  String? error;
  Map<String, dynamic>? scopedMetrics;
  bool loaded = false;
  Map<String, String> filters = {};
  String? scope;
  int generation = 0;
  String get query => cloudQuery(filters);
  @override
  void initState() {
    super.initState();
    filters = {...widget.filters, if (widget.jobId != null) 'q': widget.jobId!};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CloudScope.of(context).draftKey('report-query');
    if (next != scope) {
      if (scope != null) filters.clear();
      scope = next;
      scopedMetrics = null;
      if (next != null) load();
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context),
        captured = scope,
        ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
      scopedMetrics = null;
    });
    try {
      final data =
          await account.request(
                'GET',
                'workspaces/${account.activeWorkspace!['id']}/metrics/$query',
              )
              as Map;
      if (mounted &&
          ticket == generation &&
          captured == account.draftKey('report-query')) {
        setState(() => scopedMetrics = Map<String, dynamic>.from(data));
      }
    } catch (failure) {
      if (mounted && ticket == generation) setState(() => error = '$failure');
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  String rate(Object? value) =>
      value is num ? '${(value * 100).toStringAsFixed(1)}%' : '—';

  Future<Map<String, dynamic>?> reportSnapshot() async {
    final account = CloudScope.of(context);
    return await account.request(
          'GET',
          'workspaces/${account.activeWorkspace!['id']}/report/$query',
        )
        as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context),
        metrics = scopedMetrics ?? <String, dynamic>{};
    if (!account.signedIn) return cloudAccessRequired(context);
    const hint = TextStyle(fontSize: 11.5, height: 1.5, color: muted);
    final trend = (metrics['trend'] as List?) ?? const [];
    final categories = (metrics['issue_categories'] as Map?) ?? const {};
    final categoryMax = categories.values.fold<num>(
      0,
      (max, value) => value is num && value > max ? value : max,
    );

    Future<void> exportCsv() async {
      setState(() {
        busy = true;
        error = null;
      });
      try {
        final bytes = await account.download(
          'workspaces/${account.activeWorkspace!['id']}/report/${query.isEmpty ? '?' : '$query&'}download=csv',
        );
        await FilePicker.platform.saveFile(
          fileName: 'LineSight-quality.csv',
          type: FileType.custom,
          allowedExtensions: ['csv'],
          bytes: Uint8List.fromList(bytes),
        );
      } catch (failure) {
        if (mounted) setState(() => error = '$failure');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    Future<void> preview() async {
      setState(() {
        busy = true;
        error = null;
      });
      try {
        final snapshot = await reportSnapshot();
        if (snapshot == null) return;
        final images = await cloudReportImages(account, snapshot);
        if (context.mounted) {
          openPage(
            context,
            CloudReportSnapshotPage(snapshot: snapshot, images: images),
          );
        }
      } catch (failure) {
        if (mounted) setState(() => error = '$failure');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    Future<void> printReport() async {
      setState(() {
        busy = true;
        error = null;
      });
      try {
        final snapshot = await reportSnapshot();
        if (snapshot == null || !context.mounted) return;
        final images = await cloudReportImages(account, snapshot);
        final font = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSansSC.ttf'),
        );
        if (!context.mounted) return;
        final document = pw.Document(
          theme: pw.ThemeData.withFont(base: font, bold: font),
        );
        final data = snapshot['metrics'] as Map;
        document.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            maxPages: 200,
            build: (_) => [
              pw.Text(
                'LineSight · ${tr(context, '质量报告')}',
                style: const pw.TextStyle(fontSize: 24),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                '${snapshot['workspace']} · ${tr(context, '云端数据')}\n${snapshot['report_id']}\n${snapshot['generated_at']}\n${cloudScopeLabel(context, filters)}',
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                data: [
                  [tr(context, '首次通过率'), rate(data['first_pass_rate'])],
                  [tr(context, '最终放行率'), rate(data['final_release_rate'])],
                  [
                    tr(context, '首次送检工件'),
                    '${data['first_inspected_pieces']}',
                  ],
                  [
                    tr(context, '最终放行工件'),
                    '${data['final_released_pieces']}',
                  ],
                  [tr(context, '异常工件'), '${data['latest_fail_pieces']}'],
                  [tr(context, '报废工件'), '${data['latest_scrap_pieces']}'],
                ],
              ),
              for (final task in snapshot['jobs'] as List? ?? []) ...[
                pw.SizedBox(height: 16),
                pw.Text(
                  '${task['part_name']} · ${task['batch_code'] ?? ''}',
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.Text('${task['id']} · v${task['version']}'),
                pw.Text(
                  '${tr(context, '打印设备')}: ${task['printer']} · ${tr(context, '工件数量')}: ${task['quantity']}',
                ),
                for (final check in task['inspections'] as List? ?? []) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    '${tr(context, '检验轮次')} ${check['round_no']} · ${check['inspector']} · ${cloudTimestamp(check['created_at'])}',
                  ),
                  pw.Text(
                    '${tr(context, check['verdict'] == 'pass' ? '合格' : '异常')} · ${check['note']}',
                  ),
                  pw.Text(
                    '${check['template_snapshot']?['name'] ?? ''} · v${check['template_snapshot']?['version'] ?? ''}',
                  ),
                ],
                for (final issue in task['exceptions'] as List? ?? [])
                  pw.Text(
                    '${issue['assignee']} · ${issue['note']} · ${issue['resolution']}',
                  ),
                for (final photo in task['evidence'] as List? ?? []) ...[
                  pw.Text(
                    '${tr(context, '图片证据')} #${photo['id']} · ${tr(context, {'inspection': '检验照片', 'before': '整改前', 'after': '整改后'}[photo['stage']] ?? '${photo['stage']}')}',
                  ),
                  if (images[photo['id']] != null)
                    pw.Image(
                      pw.MemoryImage(images[photo['id']]!),
                      width: 180,
                      height: 120,
                      fit: pw.BoxFit.contain,
                    ),
                ],
              ],
            ],
          ),
        );
        await Printing.layoutPdf(onLayout: (_) => document.save());
      } catch (failure) {
        if (mounted) setState(() => error = '$failure');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    return DetailScaffold(
      title: tr(context, '质量洞察与报告'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh, size: 21),
          tooltip: tr(context, '刷新'),
        ),
      ],
      children: [
        HeroBanner(
          eyebrow: 'QUALITY / ANALYTICS',
          title: tr(context, '质量洞察'),
          subtitle:
              '${account.activeWorkspace?['name'] ?? ''} · ${cloudScopeLabel(context, filters)}',
          actions: [
            HeroAction(
              label: tr(context, '筛选范围'),
              icon: Icons.filter_alt_outlined,
              ghost: true,
              onPressed: busy
                  ? null
                  : () async {
                      final selected = await cloudFilterDialog(
                        context,
                        filters,
                        records: true,
                      );
                      if (selected != null && mounted) {
                        setState(() => filters = selected);
                        load();
                      }
                    },
            ),
            HeroAction(
              label: tr(context, '刷新数据'),
              icon: Icons.refresh,
              ghost: true,
              onPressed: busy ? null : load,
            ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, color: red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trMessage(context, error!),
                      style: const TextStyle(fontSize: 12, color: red),
                    ),
                  ),
                  TextButton(
                    onPressed: load,
                    child: Text(tr(context, '重试')),
                  ),
                ],
              ),
            ),
          ),
        SectionHeader(
          tr(context, '核心指标'),
          icon: Icons.insights_outlined,
          caption: tr(context, '按当前筛选范围统计'),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 720 ? 3 : 2;
            final width = (c.maxWidth - (columns - 1) * 10) / columns;
            Widget cell(Widget child) =>
                SizedBox(width: width, child: child);
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                cell(
                  StatCard(
                    label: tr(context, '首次通过率'),
                    value: rate(metrics['first_pass_rate']),
                    icon: Icons.verified_outlined,
                    color: green,
                  ),
                ),
                cell(
                  StatCard(
                    label: tr(context, '最终放行率'),
                    value: rate(metrics['final_release_rate']),
                    icon: Icons.task_alt,
                    color: blue,
                  ),
                ),
                cell(
                  StatCard(
                    label: tr(context, '首次送检工件'),
                    value: '${metrics['first_inspected_pieces'] ?? 0}',
                    icon: Icons.inventory_2_outlined,
                    color: blue,
                  ),
                ),
                cell(
                  StatCard(
                    label: tr(context, '最终放行工件'),
                    value: '${metrics['final_released_pieces'] ?? 0}',
                    icon: Icons.outbox_outlined,
                    color: green,
                  ),
                ),
                cell(
                  StatCard(
                    label: tr(context, '异常工件'),
                    value: '${metrics['latest_fail_pieces'] ?? 0}',
                    icon: Icons.report_gmailerrorred_outlined,
                    color: red,
                  ),
                ),
                cell(
                  StatCard(
                    label: tr(context, '报废工件'),
                    value: '${metrics['latest_scrap_pieces'] ?? 0}',
                    icon: Icons.delete_outline,
                    color: amber,
                  ),
                ),
              ],
            );
          },
        ),
        SectionHeader(
          tr(context, '最近 7 天'),
          icon: Icons.timeline,
          caption: tr(context, '点击日期查看当日任务'),
        ),
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: trend.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    tr(context, '当前范围内暂无检验数据'),
                    style: hint,
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < trend.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => openPage(
                            context,
                            CloudTaskListPage(
                              filters: {
                                ...filters,
                                'first_day': '${trend[i]['day']}',
                              },
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 78,
                                  child: Text(
                                    '${trend[i]['day']}'.substring(
                                      '${trend[i]['day']}'.length > 5
                                          ? 5
                                          : 0,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: ink,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(5),
                                        child: SizedBox(
                                          height: 8,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              const ColoredBox(
                                                color: Color(0xFFFFD9D2),
                                              ),
                                              FractionallySizedBox(
                                                alignment: Alignment.centerLeft,
                                                widthFactor:
                                                    (trend[i]['inspected']
                                                                as num? ??
                                                            0) ==
                                                        0
                                                    ? 0.0
                                                    : ((trend[i]['passed']
                                                                    as num? ??
                                                                0) /
                                                                (trend[i]['inspected']
                                                                    as num))
                                                            .clamp(0.0, 1.0)
                                                            .toDouble(),
                                                child: const ColoredBox(
                                                  color: green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '${tr(context, '合格')} ${trend[i]['passed'] ?? 0} · ${tr(context, '异常')} ${(trend[i]['inspected'] as num? ?? 0) - (trend[i]['passed'] as num? ?? 0)}',
                                        style: hint,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '${trend[i]['passed'] ?? 0}/${trend[i]['inspected'] ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        SectionHeader(
          tr(context, '异常类别'),
          icon: Icons.category_outlined,
          caption: categories.isEmpty ? null : tr(context, '按任务数量排序'),
        ),
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: categories.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: green),
                      const SizedBox(width: 10),
                      Text(
                        tr(context, '当前范围内没有登记异常'),
                        style: hint,
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < categories.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => openPage(
                            context,
                            CloudTaskListPage(
                              filters: {
                                ...filters,
                                'category': '${categories.keys.elementAt(i)}',
                              },
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        tr(
                                          context,
                                          cloudCategories[categories.keys
                                                  .elementAt(i)] ??
                                              '${categories.keys.elementAt(i)}',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: ink,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          minHeight: 6,
                                          value: categoryMax == 0
                                              ? 0
                                              : (categories.values
                                                            .elementAt(i)
                                                        as num) /
                                                    categoryMax,
                                          backgroundColor:
                                              const Color(0xFFEEF3FA),
                                          color: red.withValues(alpha: .75),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  '${categories.values.elementAt(i)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: red,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 19,
                                  color: muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.timer_outlined, color: blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, '平均异常处理时长'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(tr(context, '从登记到关闭的平均用时'), style: hint),
                  ],
                ),
              ),
              Text(
                metrics['average_issue_seconds'] == null
                    ? '—'
                    : '${((metrics['average_issue_seconds'] as num) / 3600).toStringAsFixed(1)} h',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
        SectionHeader(tr(context, '导出与报告'), icon: Icons.description_outlined),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              MenuTile(
                title: tr(context, '查看范围内任务'),
                subtitle: tr(context, '跳转到与当前筛选一致的任务列表'),
                icon: Icons.list_alt,
                onTap: () => openPage(
                  context,
                  CloudTaskListPage(filters: Map.of(filters)),
                ),
              ),
              const Divider(height: 1),
              MenuTile(
                title: tr(context, '导出 CSV'),
                subtitle: tr(context, '下载当前范围的明细数据'),
                icon: Icons.table_view_outlined,
                color: green,
                trailing: const Icon(
                  Icons.download_outlined,
                  size: 19,
                  color: muted,
                ),
                onTap: busy ? null : exportCsv,
              ),
              const Divider(height: 1),
              MenuTile(
                title: tr(context, '报告预览'),
                subtitle: tr(context, '在应用内查看带照片的报告快照'),
                icon: Icons.preview_outlined,
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 19,
                  color: muted,
                ),
                onTap: busy ? null : preview,
              ),
              const Divider(height: 1),
              MenuTile(
                title: tr(context, '打印质量报告'),
                subtitle: tr(context, '使用系统打印服务生成 PDF'),
                icon: Icons.print_outlined,
                color: amber,
                trailing: const Icon(
                  Icons.chevron_right,
                  size: 19,
                  color: muted,
                ),
                onTap: busy ? null : printReport,
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class _CountPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _CountPill({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(color: muted, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class CloudRecordsPage extends StatefulWidget {
  const CloudRecordsPage({super.key});
  @override
  State<CloudRecordsPage> createState() => _CloudRecordsPageState();
}

class _CloudRecordsPageState extends State<CloudRecordsPage> {
  final search = TextEditingController();
  Map<String, String> filters = {};
  List<Map<String, dynamic>> rows = [];
  String? scope, error;
  String sourceVersion = '';
  bool busy = false;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = CloudScope.of(context);
    final next = account.draftKey('record-query');
    final revision = account.records.map((row) => '${row['id']}').join(',');
    final changed = revision != sourceVersion;
    sourceVersion = revision;
    if (next != scope) {
      scope = next;
      filters.clear();
      search.clear();
      rows = [];
      if (next != null) load();
    } else if (changed && next != null) {
      load();
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final account = CloudScope.of(context),
        captured = scope,
        ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
      rows = [];
    });
    try {
      final data =
          await account.request(
                'GET',
                'workspaces/${account.activeWorkspace!['id']}/records/${cloudQuery(filters)}',
              )
              as List;
      if (mounted &&
          ticket == generation &&
          captured == account.draftKey('record-query')) {
        setState(() => rows = data.cast<Map<String, dynamic>>());
      }
    } catch (failure) {
      if (mounted && ticket == generation) setState(() => error = '$failure');
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    final passed = rows.where((r) => r['verdict'] == 'pass').length;
    final failed = rows.length - passed;
    return PageBody(
      children: [
        PageHeading(
          eyebrow: 'TRACEABILITY / RECORDS',
          title: tr(context, '检测记录'),
          subtitle: tr(context, '逐轮追溯检验结论、检验人与照片证据。'),
          trailing: account.signedIn
              ? IconButton.filledTonal(
                  tooltip: tr(context, '刷新'),
                  onPressed: busy ? null : load,
                  icon: const Icon(Icons.refresh, size: 19),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(42, 42),
                    backgroundColor: Colors.white,
                    foregroundColor: ink,
                    side: const BorderSide(color: hairline),
                  ),
                )
              : null,
        ),
        if (!account.signedIn)
          EmptyState(
            icon: Icons.lock_outline,
            title: tr(context, '需要登录'),
            subtitle: tr(context, '登录后查看任务与检验记录。'),
            action: FilledButton(
              onPressed: () => openPage(context, const CloudLoginPage()),
              child: Text(tr(context, '登录')),
            ),
          ),
        if (account.signedIn) ...[
          GlassPanel(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: search,
                  decoration: InputDecoration(
                    hintText: tr(context, '任务号、批次或名称'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                      onPressed: () {
                        if (search.text.trim().isEmpty) {
                          filters.remove('q');
                        } else {
                          filters['q'] = search.text.trim();
                        }
                        load();
                      },
                    ),
                  ),
                  onSubmitted: (_) {
                    if (search.text.trim().isEmpty) {
                      filters.remove('q');
                    } else {
                      filters['q'] = search.text.trim();
                    }
                    load();
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final e
                        in {'': '全部', 'pass': '合格', 'fail': '异常'}.entries)
                      ChoiceChip(
                        label: Text(tr(context, e.value)),
                        selected: (filters['verdict'] ?? '') == e.key,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          if (e.key.isEmpty) {
                            filters.remove('verdict');
                          } else {
                            filters['verdict'] = e.key;
                          }
                          load();
                        },
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.tune, size: 16),
                      label: Text(tr(context, '筛选范围')),
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        final selected = await cloudFilterDialog(
                          context,
                          filters,
                          records: true,
                        );
                        if (selected != null && mounted) {
                          setState(() {
                            filters = selected;
                            search.text = filters['q'] ?? '';
                          });
                          load();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CountPill(
                label: tr(context, '全部'),
                value: rows.length,
                color: blue,
              ),
              const SizedBox(width: 7),
              _CountPill(
                label: tr(context, '合格'),
                value: passed,
                color: green,
              ),
              const SizedBox(width: 7),
              _CountPill(
                label: tr(context, '异常'),
                value: failed,
                color: red,
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: tr(context, '范围报告'),
                onPressed: () => openPage(
                  context,
                  CloudReportPage(filters: Map.of(filters)),
                ),
                icon: const Icon(Icons.analytics_outlined, size: 19),
                style: IconButton.styleFrom(
                  minimumSize: const Size(38, 38),
                  backgroundColor: Colors.white,
                  foregroundColor: blue,
                  side: const BorderSide(color: hairline),
                ),
              ),
            ],
          ),
          if (filters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                cloudScopeLabel(context, filters),
                style: const TextStyle(fontSize: 10.5, color: muted),
              ),
            ),
          const SizedBox(height: 10),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                trMessage(context, error!),
                style: const TextStyle(color: red, fontSize: 12),
              ),
            ),
          if (!busy && rows.isEmpty)
            EmptyState(
              title: tr(context, '暂无检验记录'),
              subtitle: tr(context, '没有符合条件的记录。'),
            ),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassPanel(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => openPage(
                      context,
                      CloudInspectionDetailPage(record: r),
                    ),
                    child: Row(
                      children: [
                        PartThumb(
                          partName: '${r['part_name']}',
                          size: 58,
                          defect: r['verdict'] != 'pass',
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${r['part_name']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Tag(
                                    tr(
                                      context,
                                      r['verdict'] == 'pass' ? '合格' : '异常',
                                    ),
                                    color: r['verdict'] == 'pass'
                                        ? green
                                        : red,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${r['batch_code'] ?? ''} · ${tr(context, '检验轮次')} ${r['round_no']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.badge_outlined,
                                    size: 13,
                                    color: Color(0xFF8FA2BA),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${r['inspector']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    cloudTimestamp(r['created_at']),
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      color: Color(0xFF9AA9BD),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Color(0xFFA9B8CC),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class CloudSyncPage extends StatefulWidget {
  const CloudSyncPage({super.key});
  @override
  State<CloudSyncPage> createState() => _CloudSyncPageState();
}

class _CloudSyncPageState extends State<CloudSyncPage> {
  CloudOutbox? outbox;
  List<Map<String, dynamic>> photos = [], drafts = [];
  bool busy = false;
  String? error;
  String? scope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = CloudScope.of(context),
        next = CloudScope.of(context).draftKey('outbox');
    if (next != scope) {
      scope = next;
      photos = [];
      drafts = [];
      if (next != null) {
        outbox = CloudOutbox(account);
        load();
      }
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
    final captured = scope;
    try {
      final items = await outbox!.list(), forms = await account.listDrafts();
      if (mounted && captured == scope) {
        setState(() {
          photos = items;
          drafts = forms;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted && captured == scope) setState(() => error = '无法读取待同步内容，请重试');
    }
  }

  Future<void> retry(String key) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await outbox!.retry(key);
      await load();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is CollaborationApiException
              ? failure.message
              : '上传失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    const hint = TextStyle(fontSize: 11.5, height: 1.5, color: muted);
    final pending = photos.where((item) => item['state'] != 'uploaded').length;
    return DetailScaffold(
      title: tr(context, '同步与草稿'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: busy ? null : load,
        ),
      ],
      children: [
        HeroBanner(
          eyebrow: 'DATA / OFFLINE SYNC',
          title: tr(context, '同步与草稿'),
          subtitle:
              '${account.activeWorkspace?['name'] ?? ''} · $drafts.length ${tr(context, '份草稿')} · $pending ${tr(context, '张待上传')}',
          actions: [
            HeroAction(
              label: tr(context, '刷新云端数据'),
              icon: Icons.cloud_sync_outlined,
              ghost: true,
              onPressed: busy
                  ? null
                  : () async {
                      await account.reload();
                      if (mounted) await load();
                    },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: tr(context, '待上传图片'),
                value: '$pending',
                icon: Icons.cloud_upload_outlined,
                color: pending > 0 ? amber : green,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatCard(
                label: tr(context, '本机草稿'),
                value: '${drafts.length}',
                icon: Icons.edit_note_outlined,
                color: drafts.isEmpty ? green : blue,
              ),
            ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trMessage(context, error!),
                      style: const TextStyle(fontSize: 12, color: red),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SectionHeader(
          tr(context, '图片上传'),
          icon: Icons.cloud_upload_outlined,
          caption: '${photos.length} ${tr(context, '项')}',
        ),
        if (photos.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined, color: green, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, '所有照片均已同步至云端'),
                    style: hint,
                  ),
                ),
              ],
            ),
          )
        else
          for (final item in photos)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F8FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.photo_camera_back_outlined,
                            size: 19,
                            color: blue,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${tr(context, '任务')} ${item['job_id']}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${tr(context, item['stage'] == 'inspection' ? '检验照片' : '现场照片')} · ${((item['bytes'] as num) / 1024).round()} KB',
                                style: hint,
                              ),
                            ],
                          ),
                        ),
                        Tag(
                          tr(
                            context,
                            item['state'] == 'uploaded'
                                ? (item['stage'] == 'inspection'
                                      ? '已上传，待关联检验'
                                      : '已上传')
                                : '等待上传',
                          ),
                          color: item['state'] == 'uploaded' ? green : amber,
                        ),
                      ],
                    ),
                    if (item['error'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          trMessage(context, '${item['error']}'),
                          style: const TextStyle(fontSize: 11, color: red),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item['state'] != 'uploaded')
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              textStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onPressed: busy
                                ? null
                                : () => retry('${item['key']}'),
                            icon: const Icon(Icons.sync, size: 16),
                            label: Text(tr(context, '重试上传')),
                          ),
                        const Spacer(),
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: red),
                          onPressed: busy
                              ? null
                              : () async {
                                  if (!await confirm(
                                    context,
                                    tr(context, '移除图片'),
                                    tr(context, '确认从待同步列表中移除此图片？'),
                                  )) {
                                    return;
                                  }
                                  await outbox!.remove('${item['key']}');
                                  await load();
                                },
                          child: Text(tr(context, '移除')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        SectionHeader(
          tr(context, '本机草稿'),
          icon: Icons.edit_note_outlined,
          caption: '${drafts.length} ${tr(context, '份')}',
        ),
        if (drafts.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.task_alt, color: green, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, '没有未提交的草稿'),
                    style: hint,
                  ),
                ),
              ],
            ),
          )
        else
          GlassPanel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < drafts.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 68),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 2,
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: blue.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        switch (drafts[i]['action']) {
                          'inspect' => Icons.fact_check_outlined,
                          'resolve' => Icons.handyman_outlined,
                          _ => Icons.assignment_outlined,
                        },
                        size: 19,
                        color: blue,
                      ),
                    ),
                    title: Text(
                      '${drafts[i]['part_name'] ?? drafts[i]['name'] ?? tr(context, '新建任务')}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        tr(
                          context,
                          drafts[i]['action'] == 'inspect'
                              ? '检验草稿'
                              : drafts[i]['action'] == 'resolve'
                              ? '处置草稿'
                              : '任务草稿',
                        ),
                        style: hint,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: muted,
                    ),
                    onTap: () async {
                      if (drafts[i]['job_id'] == null) {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CloudCreateTaskPage(),
                          ),
                        );
                      } else {
                        try {
                          final job = Map<String, dynamic>.from(
                            await account.request(
                                  'GET',
                                  'workspaces/${account.activeWorkspace!['id']}/jobs/${drafts[i]['job_id']}/',
                                )
                                as Map,
                          );
                          if (!context.mounted) return;
                          final matches =
                              (job['exceptions'] as List? ?? []).where(
                                (e) => e['id'] == drafts[i]['issue_id'],
                              );
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CloudTaskCommandPage(
                                job: job,
                                workspaceId:
                                    account.activeWorkspace!['id'] as int,
                                action: '${drafts[i]['action']}',
                                issue: matches.isEmpty
                                    ? null
                                    : Map<String, dynamic>.from(
                                        matches.first as Map,
                                      ),
                              ),
                            ),
                          );
                        } catch (failure) {
                          if (mounted) {
                            setState(() => error = '无法打开草稿，请检查任务权限后重试');
                          }
                        }
                      }
                      if (mounted) await load();
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class CloudNotificationsPage extends StatelessWidget {
  const CloudNotificationsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    final notices = account.notifications;
    final unread = notices.where((notice) => notice['read'] != true).length;
    const hint = TextStyle(fontSize: 11.5, height: 1.5, color: muted);
    return DetailScaffold(
      title: tr(context, '待办与通知'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, size: 21),
          tooltip: tr(context, '刷新'),
          onPressed: () => account.reload(),
        ),
      ],
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (unread > 0 ? amber : green).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  unread > 0
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none_outlined,
                  color: unread > 0 ? amber : green,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unread > 0
                          ? '$unread ${tr(context, '条待处理通知')}'
                          : tr(context, '没有待处理通知'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ink,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${tr(context, '全部通知')} ${notices.length} ${tr(context, '条')}',
                      style: hint,
                    ),
                  ],
                ),
              ),
              if (unread > 0)
                Tag(
                  tr(context, '待处理'),
                  color: amber,
                )
              else
                Tag(tr(context, '已清空'), color: green),
            ],
          ),
        ),
        SectionHeader(
          tr(context, '通知列表'),
          icon: Icons.inbox_outlined,
          caption: '${notices.length} ${tr(context, '条')}',
        ),
        if (notices.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.inbox_outlined, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(context, '没有待办通知，新的异常与复检会显示在这里。'),
                    style: hint,
                  ),
                ),
              ],
            ),
          )
        else
          for (final notice in notices)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    final matches = account.jobs.where(
                      (j) => '${j['id']}' == '${notice['task_id']}',
                    );
                    if (matches.isNotEmpty) {
                      openPage(
                        context,
                        CloudTaskPage(
                          job: matches.first,
                          workspaceId: account.activeWorkspace!['id'] as int,
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: notice['read'] == true
                            ? hairline
                            : amber.withValues(alpha: .35),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: panelShadow,
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        PartThumb(
                          partName: '${notice['part_name']}',
                          size: 50,
                          defect: notice['reinspection'] == true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${notice['part_name']}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Tag(
                                    tr(
                                      context,
                                      notice['reinspection'] == true
                                          ? '待复检'
                                          : taskStatusLabels[notice['status']] ??
                                                '待处理',
                                    ),
                                    color: notice['reinspection'] == true
                                        ? red
                                        : taskColor('${notice['status']}'),
                                  ),
                                  if (notice['read'] != true)
                                    Text(
                                      tr(context, '未读'),
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: amber,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (notice['read'] == true)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.done_all,
                              size: 18,
                              color: muted,
                            ),
                          )
                        else
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: Text(tr(context, '标为已读')),
                            onPressed: () async {
                              try {
                                await account.request(
                                  'POST',
                                  'workspaces/${account.activeWorkspace!['id']}/notifications/${notice['task_id']}/read/',
                                  body: {'version': notice['version']},
                                );
                                await account.reload();
                              } catch (_) {
                                if (context.mounted) {
                                  toast(context, '更新通知失败，请重试');
                                }
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

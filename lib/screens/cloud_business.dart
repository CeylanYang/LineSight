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
    return DetailScaffold(
      title: tr(context, '报告预览'),
      children: [
        Text(
          '${snapshot['workspace']}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('${tr(context, '云端数据')} · ${snapshot['generated_at']}'),
        SelectableText('${snapshot['report_id']}'),
        Text(
          cloudScopeLabel(
            context,
            Map<String, String>.from(snapshot['filters'] as Map),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(tr(context, '复制追溯码')),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: '${snapshot['report_id']}'),
            );
            if (context.mounted) toast(context, '已复制');
          },
        ),
        for (final task in snapshot['jobs'] as List? ?? [])
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${task['part_name']} · ${task['batch_code']}'),
                  subtitle: Text(
                    '${task['id']} · v${task['version']}\n${tr(context, '负责人')}: ${task['assignee']}',
                  ),
                  onTap: () => openPage(
                    context,
                    CloudTaskPage(
                      job: Map<String, dynamic>.from(task as Map),
                      workspaceId: snapshot['workspace_id'] as int,
                    ),
                  ),
                ),
                for (final check in task['inspections'] as List? ?? [])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${tr(context, '检验轮次')} ${check['round_no']} · ${tr(context, check['verdict'] == 'pass' ? '合格' : '异常')}',
                    ),
                    subtitle: Text(
                      '${check['inspector']} · ${cloudTimestamp(check['created_at'])}\n${check['note']}\n${check['template_snapshot']?['name'] ?? ''} · v${check['template_snapshot']?['version'] ?? ''}',
                    ),
                  ),
                for (final issue in task['exceptions'] as List? ?? [])
                  Text(
                    '${tr(context, cloudCategories[issue['category']] ?? '${issue['category']}')} · ${issue['assignee']}\n${issue['note']}\n${issue['resolution']}',
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final photo in task['evidence'] as List? ?? [])
                      if (images[photo['id']] != null)
                        InkWell(
                          onTap: () => openPage(
                            context,
                            CloudEvidencePage(
                              jobId: '${task['id']}',
                              photo: Map<String, dynamic>.from(photo as Map),
                            ),
                          ),
                          child: Column(
                            children: [
                              Image.memory(
                                images[photo['id']]!,
                                width: 120,
                                height: 90,
                                fit: BoxFit.contain,
                              ),
                              Text('#${photo['id']} · ${photo['stage']}'),
                            ],
                          ),
                        ),
                  ],
                ),
              ],
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
    return PageBody(
      children: [
        Text(
          tr(context, '检查模板'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
        if (!account.signedIn) Text(tr(context, '登录后查看任务与检验记录')),
        if (account.activeWorkspace?['role'] == 'owner')
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr(context, '发布检查模板')),
            onPressed: () => openPage(context, const CloudTemplateEditor()),
          ),
        ...account.templates.map(
          (template) => GlassPanel(
            child: ListTile(
              title: Text('${template['name']} · v${template['version']}'),
              subtitle: Text(
                '${(template['items'] as List).length} ${tr(context, '检查项')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(
                context,
                DetailScaffold(
                  title: '${template['name']}',
                  children: [
                    for (final item in template['items'] as List)
                      GlassPanel(
                        child: ListTile(
                          title: Text('${item['label']}'),
                          subtitle: Text(
                            tr(context, item['required'] == true ? '必填' : '选填'),
                          ),
                        ),
                      ),
                    if (account.activeWorkspace?['role'] == 'owner')
                      OutlinedButton(
                        onPressed: () => openPage(
                          context,
                          CloudTemplateEditor(template: template),
                        ),
                        child: Text(tr(context, '发布新版本')),
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
  }

  @override
  void dispose() {
    name.dispose();
    items.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: tr(context, '发布检查模板'),
    children: [
      TextField(
        controller: name,
        maxLength: 100,
        decoration: InputDecoration(labelText: tr(context, '模板名称')),
      ),
      TextField(
        controller: items,
        minLines: 5,
        maxLines: 8,
        decoration: InputDecoration(labelText: tr(context, '检查项，每行一项（3至6项）')),
      ),
      if (error != null)
        Text(trMessage(context, error!), style: const TextStyle(color: red)),
      if (busy) const LinearProgressIndicator(),
      FilledButton(
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
        child: Text(tr(context, '发布')),
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
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context),
        workspace = CloudScope.of(context).activeWorkspace;
    if (!account.signedIn) return cloudAccessRequired(context);
    final owner = workspace?['role'] == 'owner' && !account.demoAccount;
    return DetailScaffold(
      title: tr(context, '团队与权限'),
      children: [
        Text(
          '${workspace?['name'] ?? ''}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(trMessage(context, error!), style: const TextStyle(color: red)),
        if (!account.demoAccount)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
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
                            account.workspaces.firstWhere(
                              (w) => w['id'] == result['id'],
                            ),
                          );
                        });
                        if (mounted) await load();
                      },
                child: Text(tr(context, '创建团队')),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
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
                            account.workspaces.firstWhere(
                              (w) => w['id'] == result['id'],
                            ),
                          );
                        });
                        if (mounted) await load();
                      },
                child: Text(tr(context, '加入团队')),
              ),
            ],
          ),
        if (owner)
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: tr(context, '邀请成员权限')),
            initialValue: 'operator',
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
                : (role) => action((account) async {
                    final result = await account.request(
                      'POST',
                      'workspaces/${workspace!['id']}/invite/',
                      body: {'role': role},
                    );
                    if (mounted) {
                      setState(() => invitation = '${result['code']}');
                    }
                  }),
          ),
        if (owner)
          TextButton(
            onPressed: busy
                ? null
                : () => action((account) async {
                    final result = await account.request(
                      'POST',
                      'workspaces/${workspace!['id']}/invite/',
                      body: {'role': 'operator'},
                    );
                    if (mounted) {
                      setState(() => invitation = '${result['code']}');
                    }
                  }),
            child: Text(tr(context, '生成邀请码')),
          ),
        if (invitation != null)
          GlassPanel(
            child: Column(
              children: [
                SelectableText(invitation!),
                TextButton.icon(
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: invitation!));
                    if (context.mounted) toast(context, '已复制');
                  },
                  label: Text(tr(context, '复制邀请码')),
                ),
              ],
            ),
          ),
        ...members.map(
          (member) => GlassPanel(
            child: ListTile(
              title: Text('${member['display_name'] ?? member['username']}'),
              subtitle: Text(
                tr(context, switch (member['role']) {
                  'owner' => '团队管理员',
                  'operator' => '操作成员',
                  _ => '只读成员',
                }),
              ),
              trailing: owner
                  ? PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (!await confirm(
                          context,
                          tr(context, '更新成员权限'),
                          '${member['display_name'] ?? member['username']}',
                        )) {
                          return;
                        }
                        await action((account) async {
                          final path =
                              'workspaces/${workspace!['id']}/members/${Uri.encodeComponent('${member['username']}')}/';
                          await account.request(
                            value == 'remove' ? 'DELETE' : 'PATCH',
                            path,
                            body: value == 'remove' ? null : {'role': value},
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
          ),
        ),
        if (!account.demoAccount && workspace?['kind'] == 'team')
          TextButton(
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
            child: Text(tr(context, '离开团队')),
          ),
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
    return DetailScaffold(
      title: '${record['part_name']}',
      children: [
        Text(
          '${tr(context, '检验轮次')} ${record['round_no']} · ${tr(context, record['verdict'] == 'pass' ? '合格' : '异常')}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          '${record['inspector']} · ${cloudTimestamp(record['created_at'])}',
        ),
        Text('${tr(context, '批次号')}：${record['batch_code'] ?? ''}'),
        if (record['inspected_qty'] != null)
          Text(
            '${tr(context, '工件数量')}：${record['inspected_qty']} · ${tr(context, '合格')} ${record['pass_qty']} · ${tr(context, '异常')} ${record['fail_qty']} · ${tr(context, '报废')} ${record['scrap_qty']}',
          ),
        Text(
          '${template['name'] ?? ''} ${template['version'] == null ? '' : 'v${template['version']}'}',
        ),
        ...((record['answers'] as List?) ?? []).map((answer) {
          final item = (template['items'] as List? ?? []).where(
            (i) => i['id'] == answer['id'],
          );
          return GlassPanel(
            child: ListTile(
              title: Text(
                item.isEmpty ? '${answer['id']}' : '${item.first['label']}',
              ),
              subtitle: Text(
                '${tr(context, switch (answer['result']) {
                  'pass' => '合格',
                  'fail' => '异常',
                  _ => '不适用',
                })}\n${answer['note'] ?? ''}',
              ),
            ),
          );
        }),
        Text('${record['note']}'),
        ...((record['evidence'] as List?) ?? []).map(
          (photo) => OutlinedButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: Text(tr(context, '查看证据')),
            onPressed: () => openPage(
              context,
              CloudEvidencePage(
                jobId: '${record['task_id']}',
                photo: Map<String, dynamic>.from(photo as Map),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
  Widget build(BuildContext context) => !CloudScope.of(context).signedIn
      ? cloudAccessRequired(context)
      : DetailScaffold(
          title: tr(context, '图片证据'),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr(context, '原图'))),
                ButtonSegment(value: true, label: Text(tr(context, '边缘参考'))),
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
            if (loading) const LinearProgressIndicator(),
            if (error != null) Text(trMessage(context, error!)),
            if (bytes != null)
              SizedBox(
                height: MediaQuery.sizeOf(context).height * .65,
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 8,
                  child: Image.memory(bytes!),
                ),
              ),
          ],
        );
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

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context),
        metrics = scopedMetrics ?? <String, dynamic>{};
    if (!account.signedIn) return cloudAccessRequired(context);
    String rate(Object? value) =>
        value is num ? '${(value * 100).toStringAsFixed(1)}%' : '—';
    return DetailScaffold(
      title: tr(context, '质量洞察与报告'),
      children: [
        Text(
          '${account.activeWorkspace?['name']}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('${tr(context, '云端数据')} · ${cloudScopeLabel(context, filters)}'),
        OutlinedButton.icon(
          icon: const Icon(Icons.filter_list),
          label: Text(tr(context, '筛选范围')),
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
        for (final entry in {
          'first_pass_rate': '首次通过率',
          'final_release_rate': '最终放行率',
        }.entries)
          GlassPanel(
            child: ListTile(
              title: Text(tr(context, entry.value)),
              trailing: Text(rate(metrics[entry.key])),
            ),
          ),
        for (final entry in {
          'first_inspected_pieces': '首次送检工件',
          'final_released_pieces': '最终放行工件',
          'latest_fail_pieces': '异常工件',
          'latest_scrap_pieces': '报废工件',
        }.entries)
          ListTile(
            title: Text(tr(context, entry.value)),
            trailing: Text('${metrics[entry.key] ?? 0}'),
          ),
        SectionHeading(tr(context, '最近7天')),
        ...((metrics['trend'] as List?) ?? []).map(
          (day) => ListTile(
            title: Text('${day['day']}'),
            subtitle: LinearProgressIndicator(
              value: (day['inspected'] as num) == 0
                  ? 0
                  : (day['passed'] as num) / (day['inspected'] as num),
            ),
            trailing: Text('${day['passed']}/${day['inspected']}'),
          ),
        ),
        SectionHeading(tr(context, '异常类别')),
        ...((metrics['issue_categories'] as Map?) ?? {}).entries.map(
          (entry) => GlassPanel(
            child: ListTile(
              title: Text(
                tr(context, cloudCategories[entry.key] ?? '${entry.key}'),
              ),
              trailing: Text('${entry.value}'),
              onTap: () => openPage(
                context,
                CloudTaskListPage(
                  filters: {...filters, 'category': '${entry.key}'},
                ),
              ),
            ),
          ),
        ),
        ListTile(
          title: Text(tr(context, '平均异常处理时长')),
          trailing: Text(
            metrics['average_issue_seconds'] == null
                ? '—'
                : '${((metrics['average_issue_seconds'] as num) / 3600).toStringAsFixed(1)} h',
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.list_alt),
          label: Text(tr(context, '查看范围内任务')),
          onPressed: () =>
              openPage(context, CloudTaskListPage(filters: Map.of(filters))),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(trMessage(context, error!), style: const TextStyle(color: red)),
        OutlinedButton.icon(
          icon: const Icon(Icons.table_view),
          label: Text(tr(context, '导出CSV')),
          onPressed: busy
              ? null
              : () async {
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
                },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.preview_outlined),
          label: Text(tr(context, '报告预览')),
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    final snapshot =
                        await account.request(
                              'GET',
                              'workspaces/${account.activeWorkspace!['id']}/report/$query',
                            )
                            as Map;
                    final images = await cloudReportImages(account, snapshot);
                    if (context.mounted) {
                      openPage(
                        context,
                        CloudReportSnapshotPage(
                          snapshot: snapshot,
                          images: images,
                        ),
                      );
                    }
                  } catch (failure) {
                    if (mounted) setState(() => error = '$failure');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.print),
          label: Text(tr(context, '打印质量报告')),
          onPressed: busy
              ? null
              : () async {
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    final snapshot =
                        await account.request(
                              'GET',
                              'workspaces/${account.activeWorkspace!['id']}/report/$query',
                            )
                            as Map;
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
                              [
                                tr(context, '首次通过率'),
                                rate(data['first_pass_rate']),
                              ],
                              [
                                tr(context, '最终放行率'),
                                rate(data['final_release_rate']),
                              ],
                              [
                                tr(context, '首次送检工件'),
                                '${data['first_inspected_pieces']}',
                              ],
                              [
                                tr(context, '最终放行工件'),
                                '${data['final_released_pieces']}',
                              ],
                              [
                                tr(context, '异常工件'),
                                '${data['latest_fail_pieces']}',
                              ],
                              [
                                tr(context, '报废工件'),
                                '${data['latest_scrap_pieces']}',
                              ],
                            ],
                          ),
                          for (final task
                              in snapshot['jobs'] as List? ?? []) ...[
                            pw.SizedBox(height: 16),
                            pw.Text(
                              '${task['part_name']} · ${task['batch_code'] ?? ''}',
                              style: const pw.TextStyle(fontSize: 16),
                            ),
                            pw.Text('${task['id']} · v${task['version']}'),
                            pw.Text(
                              '${tr(context, '打印设备')}: ${task['printer']} · ${tr(context, '工件数量')}: ${task['quantity']}',
                            ),
                            for (final check
                                in task['inspections'] as List? ?? []) ...[
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
                            for (final issue
                                in task['exceptions'] as List? ?? [])
                              pw.Text(
                                '${issue['assignee']} · ${issue['note']} · ${issue['resolution']}',
                              ),
                            for (final photo
                                in task['evidence'] as List? ?? []) ...[
                              pw.Text(
                                '${tr(context, '图片证据')} #${photo['id']} · ${photo['stage']}',
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
                },
        ),
      ],
    );
  }
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
    return PageBody(
      children: [
        Text(
          tr(context, '检测记录'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
        if (!account.signedIn) Text(tr(context, '登录后查看任务与检验记录')),
        if (account.signedIn) ...[
          TextField(
            controller: search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: tr(context, '任务号、批次或名称'),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
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
          Wrap(
            spacing: 8,
            children: [
              for (final e in {'': '全部', 'pass': '合格', 'fail': '异常'}.entries)
                ChoiceChip(
                  label: Text(tr(context, e.value)),
                  selected: (filters['verdict'] ?? '') == e.key,
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
                avatar: const Icon(Icons.filter_list),
                label: Text(tr(context, '筛选范围')),
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
              ActionChip(
                avatar: const Icon(Icons.refresh),
                label: Text(tr(context, '刷新')),
                onPressed: busy ? null : load,
              ),
              ActionChip(
                avatar: const Icon(Icons.analytics_outlined),
                label: Text(tr(context, '范围报告')),
                onPressed: () => openPage(
                  context,
                  CloudReportPage(filters: Map.of(filters)),
                ),
              ),
            ],
          ),
          Text(cloudScopeLabel(context, filters)),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              trMessage(context, error!),
              style: const TextStyle(color: red),
            ),
          if (!busy && rows.isEmpty)
            EmptyState(
              title: tr(context, '暂无检验记录'),
              subtitle: tr(context, '没有符合条件的记录。'),
            ),
          ...rows.map(
            (r) => GlassPanel(
              child: ListTile(
                title: Text('${r['part_name']}'),
                subtitle: Text(
                  '${r['batch_code']} · ${r['inspector']}\n${cloudTimestamp(r['created_at'])} · ${tr(context, '检验轮次')} ${r['round_no']}',
                ),
                leading: Icon(
                  r['verdict'] == 'pass'
                      ? Icons.check_circle_outline
                      : Icons.warning_amber,
                  color: r['verdict'] == 'pass' ? green : red,
                ),
                onTap: () =>
                    openPage(context, CloudInspectionDetailPage(record: r)),
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
    return DetailScaffold(
      title: tr(context, '同步与草稿'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: busy ? null : load,
        ),
      ],
      children: [
        Text(
          '${account.activeWorkspace?['name']}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(trMessage(context, error!), style: const TextStyle(color: red)),
        SectionHeading(tr(context, '图片上传')),
        if (photos.isEmpty) Text(tr(context, '没有待上传图片')),
        ...photos.map(
          (item) => GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['job_id']}'),
                Text(
                  '${tr(context, item['state'] == 'uploaded' ? (item['stage'] == 'inspection' ? '已上传，待关联检验' : '已上传') : '等待上传')} · ${((item['bytes'] as num) / 1024).round()} KB',
                ),
                if (item['error'] != null)
                  Text(trMessage(context, '${item['error']}')),
                Wrap(
                  spacing: 8,
                  children: [
                    if (item['state'] != 'uploaded')
                      TextButton(
                        onPressed: busy ? null : () => retry('${item['key']}'),
                        child: Text(tr(context, '重试上传')),
                      ),
                    TextButton(
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
        SectionHeading(tr(context, '本机草稿')),
        if (drafts.isEmpty) Text(tr(context, '没有未提交草稿')),
        ...drafts.map(
          (draft) => GlassPanel(
            child: ListTile(
              title: Text(
                '${draft['part_name'] ?? draft['name'] ?? tr(context, '新建任务')}',
              ),
              subtitle: Text(
                tr(
                  context,
                  draft['action'] == 'inspect'
                      ? '检验草稿'
                      : draft['action'] == 'resolve'
                      ? '处置草稿'
                      : '任务草稿',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (draft['job_id'] == null) {
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
                            'workspaces/${account.activeWorkspace!['id']}/jobs/${draft['job_id']}/',
                          )
                          as Map,
                    );
                    if (!context.mounted) return;
                    final matches = (job['exceptions'] as List? ?? []).where(
                      (e) => e['id'] == draft['issue_id'],
                    );
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CloudTaskCommandPage(
                          job: job,
                          workspaceId: account.activeWorkspace!['id'] as int,
                          action: '${draft['action']}',
                          issue: matches.isEmpty
                              ? null
                              : Map<String, dynamic>.from(matches.first as Map),
                        ),
                      ),
                    );
                  } catch (failure) {
                    if (mounted) setState(() => error = '无法打开草稿，请检查任务权限后重试');
                  }
                }
                if (mounted) await load();
              },
            ),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.sync),
          label: Text(tr(context, '刷新云端数据')),
          onPressed: busy
              ? null
              : () async {
                  await account.reload();
                  if (mounted) await load();
                },
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
    return DetailScaffold(
      title: tr(context, '待办与通知'),
      children: [
        if (account.notifications.isEmpty) Text(tr(context, '没有待办通知')),
        ...account.notifications.map(
          (notice) => GlassPanel(
            child: ListTile(
              leading: Icon(
                notice['read'] == true
                    ? Icons.mark_email_read_outlined
                    : Icons.mark_email_unread_outlined,
              ),
              title: Text('${notice['part_name']}'),
              subtitle: Text(
                tr(
                  context,
                  notice['reinspection'] == true
                      ? '待复检'
                      : taskStatusLabels[notice['status']] ?? '待处理',
                ),
              ),
              trailing: notice['read'] == true
                  ? Text(tr(context, '已读'))
                  : TextButton(
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
                          if (context.mounted) toast(context, '更新通知失败，请重试');
                        }
                      },
                    ),
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
            ),
          ),
        ),
      ],
    );
  }
}

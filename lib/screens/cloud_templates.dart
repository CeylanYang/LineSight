import 'dart:convert';
import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_feedback.dart';
import '../cloud_form.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../models.dart' show uid;
import '../ui.dart';
import 'cloud_tasks.dart'
    show cloudAccessRequired, cloudScopeChanged, CloudCreateTaskPage;

class CloudTemplateDetailPage extends StatefulWidget {
  final Map<String, dynamic> template;
  const CloudTemplateDetailPage({super.key, required this.template});
  @override
  State<CloudTemplateDetailPage> createState() => _TemplateDetailState();
}

class _TemplateDetailState extends State<CloudTemplateDetailPage> {
  String? binding;
  bool bound = false;
  late Map<String, dynamic> selected = widget.template;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      binding = CloudScope.of(context).accessScope;
      bound = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    final versions =
        account.templates
            .where(
              (t) =>
                  t['name'] == selected['name'] &&
                  (t['built_in'] == true) == (selected['built_in'] == true),
            )
            .toList()
          ..sort(
            (a, b) => (b['version'] as int).compareTo(a['version'] as int),
          );
    if (!versions.any((t) => t['id'] == selected['id'])) versions.add(selected);
    versions.sort(
      (a, b) => (b['version'] as int).compareTo(a['version'] as int),
    );
    final latest = versions.first;
    final owner = account.canManageProduction;
    final items = selected['items'] as List;
    void published(Map<String, dynamic> result) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() => selected = result);
      }
    }

    return DetailScaffold(
      title: '${selected['name']}',
      children: [
        HeroBanner(
          eyebrow: 'CONFIGURATION / TEMPLATES',
          title: '${selected['name']}',
          subtitle:
              '${tr(context, selected['built_in'] == true ? '内置模板' : '团队模板')} · v${selected['version']} · ${items.length} ${tr(context, '检查项')}',
        ),
        const SizedBox(height: 14),
        if (versions.length > 1)
          DropdownButtonFormField<int>(
            key: ValueKey(selected['id']),
            initialValue: selected['id'] as int,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr(context, '模板版本')),
            items: [
              for (final t in versions)
                DropdownMenuItem(
                  value: t['id'] as int,
                  child: Text(
                    'v${t['version']}${t['id'] == latest['id'] ? ' · ${tr(context, '最新版本')}' : ''}',
                  ),
                ),
            ],
            onChanged: (id) => setState(
              () => selected = versions.firstWhere((t) => t['id'] == id),
            ),
          ),
        SectionHeader(tr(context, '检查项目'), icon: Icons.checklist_rounded),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ${items[i]['label']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Tag(
                        tr(context, items[i]['required'] == true ? '必填' : '选填'),
                        color: items[i]['required'] == true ? amber : muted,
                      ),
                      Tag(
                        tr(
                          context,
                          items[i]['allow_na'] == true ? '允许不适用' : '需作出判定',
                        ),
                        color: blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (owner) ...[
          const SizedBox(height: 10),
          if (selected['built_in'] != true && selected['id'] == latest['id'])
            FilledButton.icon(
              onPressed: () {
                if (account.retainsAccess(binding)) {
                  openPage(
                    context,
                    CloudTemplateEditor(
                      template: selected,
                      onPublished: published,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.publish_outlined),
              label: Text(tr(context, '发布新版本')),
            ),
          OutlinedButton.icon(
            onPressed: () {
              if (account.retainsAccess(binding)) {
                openPage(
                  context,
                  CloudTemplateEditor(
                    template: selected,
                    copy: true,
                    onPublished: published,
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(tr(context, '复制模板')),
          ),
        ],
        if (account.canEdit)
          FilledButton.icon(
            onPressed: () {
              if (account.retainsAccess(binding)) {
                openPage(
                  context,
                  CloudCreateTaskPage(initialTemplateId: selected['id'] as int),
                );
              }
            },
            icon: const Icon(Icons.add_task),
            label: Text(tr(context, '使用此模板创建任务')),
          ),
      ],
    );
  }
}

class _DraftItem {
  final String id;
  final TextEditingController label;
  bool required, allowNa;
  _DraftItem({
    String? id,
    String text = '',
    this.required = true,
    this.allowNa = true,
  }) : id = id ?? 'item-${uid()}',
       label = TextEditingController(text: text);
  Map<String, dynamic> get json => {
    'id': id,
    'label': label.text.trim(),
    'required': required,
    'allow_na': allowNa,
  };
}

class CloudTemplateEditor extends StatefulWidget {
  final Map<String, dynamic>? template;
  final bool copy;
  final ValueChanged<Map<String, dynamic>>? onPublished;
  const CloudTemplateEditor({
    super.key,
    this.template,
    this.copy = false,
    this.onPublished,
  });
  @override
  State<CloudTemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<CloudTemplateEditor> {
  final form = GlobalKey<FormState>();
  final feedbackAnchor = GlobalKey();
  bool refreshing = false;
  final name = TextEditingController();
  final entries = <_DraftItem>[];
  final retired = <_DraftItem>[];
  String? binding, payloadFingerprint;
  String requestKey = 'template-${uid()}';
  bool bound = false,
      busy = false,
      dirty = false,
      mayLeave = false,
      asking = false;
  Object? failure;
  Map<String, dynamic>? receipt, newest;
  int? baseId;
  bool get updating =>
      widget.template != null &&
      !widget.copy &&
      widget.template!['built_in'] != true;
  @override
  void initState() {
    super.initState();
    name.text = '${widget.template?['name'] ?? ''}';
    if (updating) baseId = widget.template!['id'] as int;
    for (final row in widget.template?['items'] as List? ?? []) {
      entries.add(
        _DraftItem(
          id: '${row['id']}',
          text: '${row['label']}',
          required: row['required'] == true,
          allowNa: row['allow_na'] == true,
        ),
      );
    }
    while (entries.length < 3) {
      entries.add(_DraftItem());
    }
    name.addListener(markDirty);
    for (final entry in entries) {
      entry.label.addListener(markDirty);
    }
  }

  void markDirty() {
    if (mounted) setState(() => dirty = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      binding = CloudScope.of(context).accessScope;
      bound = true;
      if (widget.copy || widget.template?['built_in'] == true) {
        name.text = '${name.text} ${tr(context, '副本')}';
        dirty = false;
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    for (final entry in [...entries, ...retired]) {
      entry.label.dispose();
    }
    super.dispose();
  }

  Future<void> refreshCatalog() async {
    final account = CloudScope.of(context);
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      final rows = await account.reloadTemplates(binding);
      if (!mounted || !account.retainsAccess(binding)) return;
      if (receipt != null && !rows.any((row) => row['id'] == receipt!['id'])) {
        account.acceptTemplatePublication(binding, receipt!);
      }
      final family =
          rows
              .where(
                (t) => t['built_in'] != true && t['name'] == name.text.trim(),
              )
              .toList()
            ..sort(
              (a, b) => (b['version'] as int).compareTo(a['version'] as int),
            );
      setState(() {
        failure = null;
        newest = family.isEmpty ? null : family.first;
      });
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  void revealFeedback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = feedbackAnchor.currentContext;
      if (mounted &&
          target != null &&
          CloudScope.of(context).retainsAccess(binding)) {
        Scrollable.ensureVisible(target, alignment: .05);
      }
    });
  }

  Future<void> publish() async {
    final account = CloudScope.of(context);
    if (!account.retainsAccess(binding)) {
      setState(() {});
      return;
    }
    if (busy || refreshing || receipt != null) return;
    if (!validateCloudForm(form)) return;
    FocusScope.of(context).unfocus();
    final payload = <String, dynamic>{
      'name': name.text.trim(),
      'items': entries.map((e) => e.json).toList(),
      if (baseId != null) 'base_template_id': baseId,
    };
    final fingerprint = jsonEncode(payload);
    if (payloadFingerprint != fingerprint) {
      requestKey = 'template-${uid()}';
      payloadFingerprint = fingerprint;
    }
    setState(() {
      busy = true;
      failure = null;
      newest = null;
    });
    try {
      account.requireAccess(binding, write: true, manageProduction: true);
      final result = Map<String, dynamic>.from(
        await account.request(
              'POST',
              'workspaces/${account.activeWorkspace!['id']}/templates/',
              body: payload,
              idempotencyKey: requestKey,
            )
            as Map,
      );
      if (!mounted || !account.retainsAccess(binding)) return;
      setState(() => receipt = result);
      account.acceptTemplatePublication(binding, result);
      widget.onPublished?.call(result);
      cloudOutcome(context, '模板已发布');
      await refreshCatalog();
    } catch (error) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() => failure = error);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        revealFeedback();
      }
    }
  }

  Future<void> confirmLeave() async {
    if (asking || busy) return;
    asking = true;
    final leave = await confirm(
      context,
      tr(context, '放弃未保存的修改？'),
      tr(context, '未发布的模板修改将丢失。'),
      confirmLabel: '放弃并返回',
    );
    asking = false;
    if (mounted && leave) {
      setState(() => mayLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    final locked =
        busy || refreshing || receipt != null || !account.canManageProduction;
    final conflict =
        failure is CollaborationApiException &&
        (failure as CollaborationApiException).status == 409;
    return PopScope(
      canPop: mayLeave || (!busy && (!dirty || receipt != null)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) confirmLeave();
      },
      child: DetailScaffold(
        title: tr(
          context,
          updating
              ? '发布新版本'
              : widget.template != null
              ? '复制模板'
              : '发布检查模板',
        ),
        children: [
          CloudForm(
            formKey: form,
            children: [
              SizedBox(key: feedbackAnchor),
              if (receipt != null)
                GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: green,
                        size: 32,
                      ),
                      Text(
                        tr(context, '模板已发布'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('${receipt!['name']} · v${receipt!['version']}'),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: busy ? null : () => Navigator.pop(context),
                        child: Text(tr(context, '完成')),
                      ),
                    ],
                  ),
                ),
              if (failure != null) ...[
                if (conflict)
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(context, '模板版本已更新，请核对最新版本'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(tr(context, '编辑内容已保留。先查看最新检查项，再继续发布。')),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  try {
                                    await refreshCatalog();
                                  } catch (error) {
                                    if (mounted &&
                                        account.retainsAccess(binding)) {
                                      setState(() => failure = error);
                                    }
                                  }
                                },
                          child: Text(tr(context, '查看最新版本')),
                        ),
                      ],
                    ),
                  )
                else
                  CloudFailurePanel(failure: failure!, onRetry: refreshCatalog),
              ],
              if (newest != null && receipt == null && newest!['id'] != baseId)
                GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${tr(context, '最新版本')} · v${newest!['version']}'),
                      for (final row in newest!['items'] as List)
                        Text(
                          '• ${row['label']} · ${tr(context, row['required'] == true ? '必填' : '选填')} · ${tr(context, row['allow_na'] == true ? '允许不适用' : '需作出判定')}',
                        ),
                      if (baseId == null)
                        Text(tr(context, '同名模板已存在，请更改名称'))
                      else
                        OutlinedButton(
                          onPressed: locked
                              ? null
                              : () => setState(() {
                                  baseId = newest!['id'] as int;
                                  newest = null;
                                  payloadFingerprint = null;
                                }),
                          child: Text(tr(context, '基于最新版本继续，保留编辑内容')),
                        ),
                    ],
                  ),
                ),
              SectionHeader(tr(context, '模板信息'), icon: Icons.badge_outlined),
              GlassPanel(
                child: TextFormField(
                  controller: name,
                  readOnly: updating,
                  enabled: !locked,
                  maxLength: 100,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? tr(context, '请填写模板名称和3至6个检查项')
                      : null,
                  decoration: InputDecoration(labelText: tr(context, '模板名称')),
                ),
              ),
              Text(
                tr(context, '历史检验记录保留原模板快照'),
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              SectionHeader(
                tr(context, '检查项目'),
                icon: Icons.checklist_rounded,
                caption: '${entries.length} / 6',
              ),
              for (var i = 0; i < entries.length; i++)
                Padding(
                  key: ValueKey(entries[i].id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: ValueKey('label-${entries[i].id}'),
                          controller: entries[i].label,
                          enabled: !locked,
                          maxLength: 120,
                          maxLines: 3,
                          minLines: 1,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? tr(context, '请填写检查项名称')
                              : (value ?? '').trim().length > 120
                              ? tr(context, '每个检查项最多120个字符')
                              : null,
                          decoration: InputDecoration(
                            labelText: tr(context, '检查项 {0}', [i + 1]),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr(context, '必填')),
                          value: entries[i].required,
                          onChanged: locked
                              ? null
                              : (value) => setState(() {
                                  entries[i].required = value;
                                  dirty = true;
                                }),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr(context, '允许不适用')),
                          value: entries[i].allowNa,
                          onChanged: locked
                              ? null
                              : (value) => setState(() {
                                  entries[i].allowNa = value;
                                  dirty = true;
                                }),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: tr(context, '上移'),
                              onPressed: locked || i == 0
                                  ? null
                                  : () => setState(() {
                                      final item = entries.removeAt(i);
                                      entries.insert(i - 1, item);
                                      dirty = true;
                                    }),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: tr(context, '下移'),
                              onPressed: locked || i == entries.length - 1
                                  ? null
                                  : () => setState(() {
                                      final item = entries.removeAt(i);
                                      entries.insert(i + 1, item);
                                      dirty = true;
                                    }),
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              tooltip: tr(context, '删除检查项'),
                              onPressed: locked || entries.length <= 3
                                  ? null
                                  : () => setState(() {
                                      retired.add(entries.removeAt(i));
                                      dirty = true;
                                    }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (receipt == null) ...[
                OutlinedButton.icon(
                  onPressed: locked || entries.length >= 6
                      ? null
                      : () => setState(() {
                          final item = _DraftItem();
                          item.label.addListener(markDirty);
                          entries.add(item);
                          dirty = true;
                        }),
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, '添加检查项')),
                ),
                const SizedBox(height: 12),
                if (busy || refreshing) const LinearProgressIndicator(),
                FilledButton.icon(
                  onPressed: locked ? null : publish,
                  icon: const Icon(Icons.publish_outlined),
                  label: Text(tr(context, '发布')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

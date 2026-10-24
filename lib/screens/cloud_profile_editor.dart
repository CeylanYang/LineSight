import 'dart:convert';
import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_form.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../models.dart' show uid;
import '../ui.dart';
import 'cloud_tasks.dart' show cloudAccessRequired, cloudScopeChanged;

class CloudProfileEditor extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final bool copy;
  final ValueChanged<Map<String, dynamic>>? onSaved;
  const CloudProfileEditor({
    super.key,
    this.profile,
    this.copy = false,
    this.onSaved,
  });
  @override
  State<CloudProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<CloudProfileEditor> {
  final form = GlobalKey<FormState>();
  final feedback = GlobalKey();
  late final name = TextEditingController(
    text: '${widget.profile?['name'] ?? ''}',
  );
  late final version = TextEditingController(
    text: '${widget.profile?['version'] ?? 'v1.0'}',
  );
  late final source = TextEditingController(
    text: '${widget.profile?['source'] ?? ''}',
  );
  late final note = TextEditingController(
    text: '${widget.profile?['note'] ?? ''}',
  );
  int? templateId, revision;
  String? binding, fingerprint, requestKey;
  bool bound = false,
      busy = false,
      dirty = false,
      mayLeave = false,
      asking = false;
  Object? failure;
  Map<String, dynamic>? receipt, current;
  bool get updating => widget.profile?['override'] == true && !widget.copy;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      bound = true;
      binding = CloudScope.of(context).accessScope;
      templateId = widget.profile?['default_template_id'] as int?;
      revision = widget.profile?['revision'] as int?;
      if (widget.profile != null && !updating) {
        final original = name.text;
        name.text =
            '${original.length > 70 ? original.substring(0, 70) : original} ${tr(context, '副本')}';
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [name, version, source, note]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> leave() async {
    if (busy || asking) return;
    asking = true;
    final discard = await confirm(
      context,
      tr(context, '放弃未保存的修改？'),
      tr(context, '打印配置尚未保存。'),
      confirmLabel: '放弃并返回',
    );
    asking = false;
    if (mounted && discard) {
      setState(() => mayLeave = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> save() async {
    final account = CloudScope.of(context);
    if (busy ||
        receipt != null ||
        !account.retainsAccess(binding) ||
        !validateCloudForm(form)) {
      return;
    }
    FocusScope.of(context).unfocus();
    final payload = <String, dynamic>{
      'name': name.text.trim(),
      'version': version.text.trim(),
      'source': source.text.trim(),
      'note': note.text.trim(),
      'default_template_id': templateId,
      if (updating) 'id': widget.profile!['id'],
      if (updating) 'revision': revision,
    };
    final next = jsonEncode(payload);
    if (next != fingerprint) {
      fingerprint = next;
      requestKey = 'profile-${uid()}';
    }
    setState(() {
      busy = true;
      failure = null;
      current = null;
    });
    try {
      account.requireAccess(binding, write: true, manageProduction: true);
      final result = Map<String, dynamic>.from(
        await account.request(
              'POST',
              'workspaces/${account.activeWorkspace!['id']}/printer-profiles/',
              body: payload,
              idempotencyKey: requestKey,
            )
            as Map,
      );
      if (!mounted || !account.retainsAccess(binding)) return;
      setState(() {
        receipt = result;
        dirty = false;
      });
      widget.onSaved?.call(result);
    } catch (error) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() {
          failure = error;
          if (error is CollaborationApiException &&
              error.details?['code'] == 'profile_version_conflict' &&
              error.details?['current'] is Map) {
            current = Map<String, dynamic>.from(
              error.details!['current'] as Map,
            );
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = feedback.currentContext;
          if (mounted && target != null && account.retainsAccess(binding)) {
            Scrollable.ensureVisible(target, alignment: .05);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    final owner = account.canManageProduction;
    if (!owner) return cloudScopeChanged(context);
    final rows = <int, Map<String, dynamic>>{
      for (final t in account.templates) t['id'] as int: t,
    };
    final pinned = widget.profile?['default_template'];
    if (pinned is Map && !rows.containsKey(pinned['id'])) {
      rows[pinned['id'] as int] = Map<String, dynamic>.from(pinned);
    }
    String? requiredValue(String? value) =>
        value == null || value.trim().isEmpty ? tr(context, '请填写完整信息') : null;
    final locked = busy || receipt != null;
    return PopScope(
      canPop: mayLeave || (!busy && (!dirty || receipt != null)),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: DetailScaffold(
        title: tr(
          context,
          updating
              ? '编辑打印配置'
              : widget.profile == null
              ? '创建打印配置'
              : '复制打印配置',
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(key: feedback),
              if (receipt != null)
                GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: green,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(context, '打印配置已保存'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('${receipt!['name']} · ${receipt!['version']}'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, receipt),
                        child: Text(tr(context, '完成')),
                      ),
                    ],
                  ),
                )
              else ...[
                if (failure != null)
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          tr(
                            context,
                            current != null ? '配置已更新，请核对最新版本' : '未能保存打印配置',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: amber,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (current != null) ...[
                          Text('${current!['name']} · ${current!['version']}'),
                          Text('${current!['source']}'),
                          if (current!['default_template'] is Map)
                            Text(
                              '${current!['default_template']['name']} · v${current!['default_template']['version']}',
                            ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () {
                                    setState(() {
                                      revision = current!['revision'] as int;
                                      current = null;
                                      failure = null;
                                      dirty = true;
                                    });
                                  },
                            child: Text(tr(context, '基于最新配置继续，保留编辑内容')),
                          ),
                        ] else
                          Text(tr(context, '请核对名称、版本及 HTTPS 来源，检查网络后再次保存。')),
                      ],
                    ),
                  ),
                GlassPanel(
                  child: Form(
                    key: form,
                    onChanged: () {
                      if (!dirty) setState(() => dirty = true);
                    },
                    child: Column(
                      children: [
                        TextFormField(
                          controller: name,
                          enabled: !locked,
                          readOnly: updating,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: tr(context, '配置名称'),
                          ),
                          validator: requiredValue,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: version,
                          enabled: !locked,
                          maxLength: 40,
                          decoration: InputDecoration(
                            labelText: tr(context, '配置版本'),
                          ),
                          validator: requiredValue,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: source,
                          enabled: !locked,
                          maxLength: 300,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: tr(context, 'HTTPS 配置来源'),
                          ),
                          validator: (value) {
                            final uri = Uri.tryParse(value?.trim() ?? '');
                            return uri == null ||
                                    uri.scheme != 'https' ||
                                    uri.host.isEmpty
                                ? tr(context, '请填写有效的 HTTPS 地址')
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: templateId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr(context, '默认检查模板'),
                          ),
                          items: [
                            DropdownMenuItem<int>(
                              value: null,
                              child: Text(tr(context, '不指定模板')),
                            ),
                            ...rows.values.map(
                              (t) => DropdownMenuItem<int>(
                                value: t['id'] as int,
                                child: Text(
                                  '${t['name']} · v${t['version']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: locked
                              ? null
                              : (value) => setState(() {
                                  templateId = value;
                                  dirty = true;
                                }),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: note,
                          enabled: !locked,
                          maxLength: 300,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: tr(context, '配置备注'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: locked ? null : save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr(context, '保存打印配置')),
                ),
              ],
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ],
      ),
    );
  }
}

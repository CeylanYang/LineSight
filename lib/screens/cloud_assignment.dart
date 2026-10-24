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
    show
        cloudAccessRequired,
        cloudScopeChanged,
        CloudTaskConflictComparison,
        cloudTaskSnapshot;

class CloudAssignmentPage extends StatefulWidget {
  final Map<String, dynamic> job;
  final int workspaceId;
  const CloudAssignmentPage({
    super.key,
    required this.job,
    required this.workspaceId,
  });
  @override
  State<CloudAssignmentPage> createState() => _CloudAssignmentPageState();
}

class _CloudAssignmentPageState extends State<CloudAssignmentPage> {
  final form = GlobalKey<FormState>();
  final feedback = GlobalKey();
  final note = TextEditingController();
  late Map<String, dynamic> job = Map<String, dynamic>.from(widget.job);
  late int? selected = widget.job['assignee_id'] as int?;
  String? binding, fingerprint, requestKey;
  Map<String, dynamic>? current;
  List<Map<String, dynamic>> members = [];
  Object? failure;
  bool bound = false,
      loading = true,
      busy = false,
      dirty = false,
      selectedByUser = false,
      mayLeave = false,
      asking = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      bound = true;
      binding = CloudScope.of(context).accessScope;
      loadMembers();
    }
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> loadMembers() async {
    final account = CloudScope.of(context);
    if (!account.retainsAccess(binding)) return;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final rows =
          (await account.request(
                    'GET',
                    'workspaces/${widget.workspaceId}/members/',
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      if (mounted && account.retainsAccess(binding)) {
        setState(() {
          members = rows
              .where(
                (m) =>
                    const {'owner', 'operator'}.contains(m['role']) &&
                    m['active'] != false,
              )
              .toList();
        });
      }
    } catch (error) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() => failure = error);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> leave() async {
    if (busy || asking) return;
    asking = true;
    final discard = await confirm(
      context,
      tr(context, '放弃未保存的修改？'),
      tr(context, '负责人变更尚未保存。'),
      confirmLabel: '放弃并返回',
    );
    asking = false;
    if (mounted && discard) {
      setState(() => mayLeave = true);
      Navigator.pop(context);
    }
  }

  Future<void> save() async {
    final account = CloudScope.of(context);
    if (busy ||
        loading ||
        current != null ||
        !selectedByUser ||
        selected == job['assignee_id'] ||
        !validateCloudForm(form)) {
      return;
    }
    if (!account.retainsAccess(binding) || !account.canEdit) return;
    FocusScope.of(context).unfocus();
    final payload = {
      'version': job['version'],
      'assignee_id': selected,
      'note': note.text.trim(),
    };
    final next = jsonEncode(payload);
    if (fingerprint != next) {
      fingerprint = next;
      requestKey = 'assignment-${uid()}';
    }
    setState(() {
      busy = true;
      failure = null;
      current = null;
    });
    try {
      final result = Map<String, dynamic>.from(
        await account.request(
              'POST',
              'workspaces/${widget.workspaceId}/jobs/${job['id']}/assignment/',
              body: payload,
              idempotencyKey: requestKey,
            )
            as Map,
      );
      if (!mounted || !account.retainsAccess(binding)) return;
      setState(() {
        dirty = false;
        mayLeave = true;
      });
      cloudOutcome(context, '负责人已更新');
      Navigator.pop(context, result);
    } catch (error) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() {
          failure = error;
          if (error is CollaborationApiException &&
              error.details?['code'] == 'version_conflict' &&
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
          if (mounted &&
              failure != null &&
              target != null &&
              account.retainsAccess(binding)) {
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
    if (!account.retainsAccess(binding) ||
        !account.canEdit ||
        account.activeWorkspace?['id'] != widget.workspaceId) {
      return cloudScopeChanged(context);
    }
    final closed = job['status'] == 'closed';
    final options = members.any((m) => m['id'] == selected) ? selected : null;
    return PopScope(
      canPop: mayLeave || (!busy && !dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) leave();
      },
      child: DetailScaffold(
        title: tr(context, '更改负责人'),
        children: [
          PageHeading(
            eyebrow: 'TEAM / ASSIGNMENT',
            title: '${job['part_name']}',
            subtitle: tr(
              context,
              job['status'] == 'exception' ? '交接当前任务及所有未完成异常。' : '为任务选择接手成员。',
            ),
          ),
          GlassPanel(
            child: Column(
              children: [
                InfoRow(
                  tr(context, '当前负责人'),
                  '${job['assignee'] ?? ''}'.isEmpty
                      ? tr(context, '未指派')
                      : '${job['assignee']}',
                ),
                InfoRow(tr(context, '任务版本'), '${job['version']}'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(key: feedback),
          if (closed)
            Text(tr(context, '已关闭任务不能更改负责人'))
          else if (loading)
            const CloudLoadingPanel()
          else ...[
            if (failure != null) ...[
              if (current != null)
                GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr(context, '任务已更新，请核对最新版本')),
                      const SizedBox(height: 12),
                      CloudTaskConflictComparison(
                        before: cloudTaskSnapshot(job),
                        current: current!,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () async {
                                setState(() {
                                  job = current!;
                                  current = null;
                                  failure = null;
                                  fingerprint = null;
                                });
                                await loadMembers();
                              },
                        child: Text(tr(context, '按最新任务继续')),
                      ),
                    ],
                  ),
                )
              else
                CloudFailurePanel(failure: failure!, onRetry: loadMembers),
              const SizedBox(height: 14),
            ],
            if (members.isEmpty && failure == null)
              EmptyState(
                icon: Icons.group_outlined,
                title: tr(context, '暂无可接手成员'),
                subtitle: tr(context, '请刷新成员列表后重试。'),
                action: TextButton(
                  onPressed: loadMembers,
                  child: Text(tr(context, '刷新')),
                ),
              ),
            Form(
              key: form,
              child: GlassPanel(
                child: Column(
                  children: [
                    DropdownButtonFormField<int>(
                      key: ValueKey('$options-${members.length}'),
                      initialValue: options,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr(context, '新负责人'),
                      ),
                      items: [
                        DropdownMenuItem<int>(
                          value: null,
                          child: Text(tr(context, '未指派')),
                        ),
                        ...members.map(
                          (m) => DropdownMenuItem<int>(
                            value: m['id'] as int,
                            child: Text(
                              '${m['display_name'] ?? m['username']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() {
                              selected = value;
                              selectedByUser = true;
                              dirty = true;
                            }),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: note,
                      enabled: !busy,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: tr(context, '交接说明'),
                      ),
                      onChanged: (_) => setState(() => dirty = true),
                      validator: (value) =>
                          job['status'] == 'exception' &&
                              (value ?? '').trim().isEmpty
                          ? tr(context, '请填写交接说明')
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed:
                  busy ||
                      current != null ||
                      members.isEmpty ||
                      !selectedByUser ||
                      selected == job['assignee_id'] ||
                      (selected != null &&
                          !members.any((m) => m['id'] == selected))
                  ? null
                  : save,
              icon: const Icon(Icons.person_outline),
              label: Text(tr(context, '确认更改负责人')),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

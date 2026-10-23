import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cloud_account.dart';
import '../cloud_outbox.dart';
import '../cloud_filters.dart';
import '../cloud_form.dart';
import '../cloud_history.dart';
import '../cloud_lifecycle.dart';
import 'cloud_evidence_compare.dart';
import '../cloud_feedback.dart';
import '../store.dart' show AppFeedback;
import '../cloud_trace.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../models.dart' show uid;
import '../ui.dart';
import '../time.dart' show zonedStamp;
import 'cloud_business.dart';
import 'cloud_shell.dart' show CloudLoginPage, cloudReauthenticate;

String cloudTimestamp(Object? value) {
  final parsed = DateTime.tryParse('$value');
  return parsed == null ? '$value' : zonedStamp(parsed);
}

const taskStatusLabels = {
  'queued': '待打印',
  'printing': '打印中',
  'inspection': '待质检',
  'exception': '异常处理中',
  'closed': '已关闭',
};
Color taskColor(String status) => switch (status) {
  'closed' => green,
  'exception' => red,
  'inspection' => amber,
  _ => blue,
};

Map<String, dynamic> cloudTaskSnapshot(Map<String, dynamic> job) => {
  for (final name in [
    'version',
    'status',
    'part_name',
    'printer',
    'quantity',
    'batch_code',
    'assignee',
    'updated_at',
  ])
    if (job.containsKey(name)) name: job[name],
  if (job.containsKey('template'))
    'template': job['template'] is Map
        ? {
            for (final name in ['id', 'name', 'version'])
              name: job['template'][name],
          }
        : null,
  if (job['inspections'] is List)
    'inspection_round': (job['inspections'] as List).fold<int>(0, (
      round,
      check,
    ) {
      final next = check['round_no'] as int? ?? 0;
      return next > round ? next : round;
    }),
};

class CloudTaskConflictComparison extends StatelessWidget {
  final Map<String, dynamic> before, current;
  const CloudTaskConflictComparison({
    super.key,
    required this.before,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final after = cloudTaskSnapshot(current);
    String value(Map<String, dynamic> row, String field) {
      if (!row.containsKey(field)) return '—';
      final raw = row[field];
      if (field == 'status') {
        return tr(context, taskStatusLabels[raw] ?? '$raw');
      }
      if (field == 'updated_at') return raw == null ? '—' : cloudTimestamp(raw);
      if (field == 'template') {
        return raw is Map
            ? '${raw['name']} · v${raw['version']}'
            : tr(context, '未选择');
      }
      if (field == 'assignee') {
        return raw == null || '$raw'.isEmpty ? tr(context, '未指派') : '$raw';
      }
      return raw == null || '$raw'.isEmpty ? '—' : '$raw';
    }

    const fields = {
      'version': '版本',
      'status': '状态',
      'inspection_round': '检验轮次',
      'part_name': '任务名称',
      'quantity': '工件数量',
      'printer': '打印设备',
      'batch_code': '批次号',
      'assignee': '负责人',
      'template': '检查模板',
      'updated_at': '更新时间',
    };
    final visible = fields.entries.where(
      (field) =>
          ['version', 'status', 'inspection_round'].contains(field.key) ||
          value(before, field.key) != value(after, field.key),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr(context, '编辑时'),
                style: const TextStyle(color: muted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tr(context, '任务更新后'),
                style: const TextStyle(
                  color: blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        for (final field in visible) ...[
          const SizedBox(height: 12),
          Text(
            tr(context, field.value),
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  value(before, field.key),
                  style: const TextStyle(fontSize: 13, color: ink),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value(after, field.key),
                  style: TextStyle(
                    fontSize: 13,
                    color: value(before, field.key) == value(after, field.key)
                        ? ink
                        : blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

Widget cloudAccessRequired(BuildContext context, {VoidCallback? onLogin}) =>
    DetailScaffold(
      title: tr(context, '登录'),
      children: [
        Text(tr(context, '登录后查看任务与检验记录')),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onLogin ?? () => openPage(context, const CloudLoginPage()),
          child: Text(tr(context, '登录')),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          child: Text(tr(context, '返回工作台')),
        ),
      ],
    );

Future<String> cloudRestoreDraftAccess(
  CloudAccount account,
  Object? ownerId,
  int workspaceId, {
  bool write = true,
}) async {
  if (!account.signedIn ||
      ownerId == null ||
      account.profile?['id'] != ownerId) {
    throw const CollaborationApiException(403, '账户或团队已切换，请重新打开页面');
  }
  if (account.activeWorkspace?['id'] != workspaceId) {
    final matches = account.workspaces.where((w) => w['id'] == workspaceId);
    if (matches.isEmpty) {
      throw const CollaborationApiException(403, '当前账户没有访问权限');
    }
    await account.selectWorkspace(matches.first);
    if (account.error != null) {
      throw const CollaborationApiException(503, '无法恢复草稿，请重试');
    }
  }
  if (account.profile?['id'] != ownerId ||
      account.activeWorkspace?['id'] != workspaceId ||
      (write && !account.canEdit)) {
    throw const CollaborationApiException(403, '当前账户没有访问权限');
  }
  final captured = account.accessScope;
  account.requireAccess(captured, write: write);
  return captured!;
}

Widget cloudDraftRecoveryFailure(
  BuildContext context,
  Object failure,
  Future<void> Function() retry,
) => DetailScaffold(
  title: tr(context, '恢复草稿'),
  children: [
    CloudFailurePanel(failure: failure, onRetry: retry),
    TextButton(
      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
      child: Text(tr(context, '返回工作台')),
    ),
  ],
);

Widget cloudScopeChanged(BuildContext context) => DetailScaffold(
  title: tr(context, '工作区已切换'),
  children: [
    Text(tr(context, '返回工作台后重新打开页面')),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
      child: Text(tr(context, '返回工作台')),
    ),
  ],
);

class CloudTaskListPage extends StatefulWidget {
  final String? status;
  final Map<String, String> filters;
  const CloudTaskListPage({super.key, this.status, this.filters = const {}});
  @override
  State<CloudTaskListPage> createState() => _CloudTaskListPageState();
}

class _CloudTaskListPageState extends State<CloudTaskListPage> {
  final search = TextEditingController();
  Map<String, String> filters = {};
  List<Map<String, dynamic>>? rows;
  String? scope;
  Object? error;
  String sourceVersion = '';
  bool busy = false;
  int serial = 0;
  @override
  void initState() {
    super.initState();
    filters = {
      ...widget.filters,
      if (widget.status != null) 'status': widget.status!,
    };
    search.text = filters['q'] ?? '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = CloudScope.of(context);
    final next = account.draftKey('task-query');
    final revision = account.jobs
        .map((row) => '${row['id']}/${row['version']}')
        .join(',');
    final changed = revision != sourceVersion;
    sourceVersion = revision;
    if (next != scope) {
      if (scope != null) {
        filters.clear();
        search.clear();
      }
      scope = next;
      if (next != null) load();
    } else if (changed && next != null) {
      load();
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context), captured = scope, ticket = ++serial;
    setState(() {
      busy = true;
      error = null;
      rows = null;
    });
    try {
      final data =
          await account.request(
                'GET',
                'workspaces/${account.activeWorkspace!['id']}/jobs/${cloudQuery(filters)}',
              )
              as List;
      if (mounted &&
          ticket == serial &&
          captured == account.draftKey('task-query')) {
        setState(() => rows = data.cast<Map<String, dynamic>>());
      }
    } catch (failure) {
      if (mounted && ticket == serial) setState(() => error = failure);
    } finally {
      if (mounted && ticket == serial) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    final jobs = rows ?? <Map<String, dynamic>>[];
    return DetailScaffold(
      title: tr(context, '生产任务'),
      actions: [
        IconButton(
          tooltip: tr(context, '刷新'),
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: search,
                onSubmitted: (_) {
                  if (search.text.trim().isEmpty) {
                    filters.remove('q');
                  } else {
                    filters['q'] = search.text.trim();
                  }
                  load();
                },
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
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final e in {'': '全部', ...taskStatusLabels}.entries)
                    ChoiceChip(
                      label: Text(tr(context, e.value)),
                      selected: (filters['status'] ?? '') == e.key,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        setState(() {
                          if (e.key.isEmpty) {
                            filters.remove('status');
                          } else {
                            filters['status'] = e.key;
                          }
                        });
                        load();
                      },
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.filter_list, size: 16),
                    label: Text(tr(context, '筛选范围')),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final selected = await cloudFilterDialog(
                        context,
                        filters,
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
              if (filters.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(
                    cloudScopeLabel(context, filters),
                    style: const TextStyle(fontSize: 10.5, color: muted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: blue.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${busy || error != null ? '—' : jobs.length} ${tr(context, '个任务')}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: blue,
                ),
              ),
            ),
            const Spacer(),
            if (account.canEdit)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: TextStyle(
                      fontFamily: Theme.of(
                        context,
                      ).textTheme.labelLarge?.fontFamily,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  onPressed: () =>
                      openPage(context, const CloudCreateTaskPage()),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(tr(context, '新建任务')),
                ),
              ),
            IconButton.filledTonal(
              tooltip: tr(context, '范围报告'),
              onPressed: () =>
                  openPage(context, CloudReportPage(filters: Map.of(filters))),
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
        const SizedBox(height: 10),
        if (busy) const CloudLoadingPanel(),
        if (error != null) CloudFailurePanel(failure: error!, onRetry: load),
        if (!busy && error == null && jobs.isEmpty)
          EmptyState(
            title: tr(context, '暂无生产任务'),
            subtitle: tr(context, '没有符合条件的任务。'),
            action: account.canEdit
                ? FilledButton.icon(
                    onPressed: () =>
                        openPage(context, const CloudCreateTaskPage()),
                    icon: const Icon(Icons.add),
                    label: Text(tr(context, '新建任务')),
                  )
                : null,
          ),
        ...jobs.map((job) => CloudTaskTile(job: job)),
      ],
    );
  }
}

class CloudTaskTile extends StatelessWidget {
  final Map<String, dynamic> job;
  const CloudTaskTile({super.key, required this.job});
  @override
  Widget build(BuildContext context) {
    final status = '${job['status']}';
    final assignee = '${job['assignee'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hairline),
          boxShadow: const [
            BoxShadow(color: panelShadow, blurRadius: 20, offset: Offset(0, 7)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => openPage(
              context,
              CloudTaskPage(
                job: job,
                workspaceId:
                    CloudScope.of(context).activeWorkspace!['id'] as int,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  PartThumb(
                    partName: '${job['part_name']}',
                    size: 62,
                    defect: status == 'exception',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${job['part_name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                  letterSpacing: -.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Tag(
                              tr(context, taskStatusLabels[status] ?? status),
                              color: taskColor(status),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.print_outlined,
                              size: 13,
                              color: Color(0xFF8FA2BA),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${job['printer']} · ${job['quantity']} ${tr(context, '件')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: muted,
                                ),
                              ),
                            ),
                            if ('${job['batch_code'] ?? ''}'.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '${job['batch_code']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Container(
                              width: 19,
                              height: 19,
                              decoration: BoxDecoration(
                                color: blue.withValues(alpha: .09),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                assignee.isEmpty
                                    ? '—'
                                    : assignee.characters.first,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: blue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                assignee.isEmpty
                                    ? tr(context, '未指派')
                                    : assignee,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: Color(0xFFA9B8CC),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CloudCreateTaskPage extends StatefulWidget {
  const CloudCreateTaskPage({super.key});
  @override
  State<CloudCreateTaskPage> createState() => _CloudCreateTaskPageState();
}

class _CloudCreateTaskPageState extends State<CloudCreateTaskPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      printer = TextEditingController(),
      quantity = TextEditingController(text: '1'),
      note = TextEditingController(),
      batch = TextEditingController(),
      serials = TextEditingController();
  int? templateId, assigneeId;
  List<Map<String, dynamic>> teamMembers = [];
  bool serialMode = false;
  String key = 'cloud-${uid()}';
  bool busy = false;
  String? error;
  String? draftStorageKey, accessBinding;
  Object? draftOwner, recoveryFailure;
  int? draftWorkspace;
  bool recovering = false;
  bool draftLoaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!draftLoaded) {
      draftLoaded = true;
      final account = CloudScope.of(context);
      accessBinding = account.accessScope;
      draftOwner = account.profile?['id'];
      draftWorkspace = account.activeWorkspace?['id'] as int?;
      draftStorageKey = account.draftKey('create');
      loadMembers(account);
      if (draftStorageKey != null) restoreDraft(account);
    }
  }

  Future<void> recoverLogin() async {
    if (await cloudReauthenticate(context) && mounted) await reopenDraft();
  }

  Future<void> reopenDraft() async {
    final account = CloudScope.of(context);
    setState(() {
      recovering = true;
      recoveryFailure = null;
    });
    try {
      final captured = await cloudRestoreDraftAccess(
        account,
        draftOwner,
        draftWorkspace!,
      );
      if (!mounted) return;
      account.requireAccess(captured, write: true);
      setState(() => accessBinding = captured);
      await loadMembers(account);
    } catch (failure) {
      if (mounted) setState(() => recoveryFailure = failure);
    } finally {
      if (mounted) setState(() => recovering = false);
    }
  }

  Future<void> loadMembers(CloudAccount account) async {
    if (account.activeWorkspace == null) return;
    try {
      final rows =
          (await account.request(
                    'GET',
                    'workspaces/${account.activeWorkspace!['id']}/members/',
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      if (mounted && account.retainsAccess(accessBinding)) {
        setState(() {
          teamMembers = rows;
          if (assigneeId != null && !rows.any((m) => m['id'] == assigneeId)) {
            assigneeId = null;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> restoreDraft(CloudAccount account) async {
    try {
      final data = await account.readDraft(draftStorageKey!);
      if (!mounted || data == null || !account.retainsAccess(accessBinding)) {
        return;
      }
      setState(() {
        key = data['request_key'] as String? ?? key;
        name.text = '${data['name'] ?? ''}';
        printer.text = '${data['printer'] ?? ''}';
        quantity.text = '${data['quantity'] ?? '1'}';
        note.text = '${data['note'] ?? ''}';
        batch.text = '${data['batch'] ?? ''}';
        serials.text = '${data['serials'] ?? ''}';
        serialMode = data['serialMode'] == true;
        templateId = data['templateId'] as int?;
        final savedAssignee = data['assignee_id'] as int?;
        assigneeId =
            teamMembers.isEmpty ||
                teamMembers.any((m) => m['id'] == savedAssignee)
            ? savedAssignee
            : null;
      });
    } catch (failure) {
      if (mounted) setState(() => error = '无法恢复草稿，请重试');
    }
  }

  Future<void> saveDraft() async {
    final account = CloudScope.of(context);
    if (draftStorageKey == null ||
        draftStorageKey != account.draftKey('create')) {
      return;
    }
    try {
      await account.saveDraft(draftStorageKey!, {
        'request_key': key,
        'name': name.text,
        'printer': printer.text,
        'quantity': quantity.text,
        'note': note.text,
        'batch': batch.text,
        'serials': serials.text,
        'serialMode': serialMode,
        'templateId': templateId,
        'assignee_id': assigneeId,
      });
    } catch (failure) {
      if (mounted) setState(() => error = '草稿保存失败，请重试');
    }
  }

  @override
  void dispose() {
    for (final controller in [name, printer, quantity, note, batch, serials]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!validateCloudForm(form)) return;
    final account = CloudScope.of(context),
        workspace = CloudScope.of(context).activeWorkspace;
    if (!account.retainsAccess(accessBinding) ||
        !account.canEdit ||
        workspace == null ||
        (draftStorageKey != null &&
            draftStorageKey != account.draftKey('create'))) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await account.request(
        'POST',
        'workspaces/${workspace['id']}/jobs/',
        idempotencyKey: key,
        body: {
          'part_name': name.text.trim(),
          'printer': printer.text.trim(),
          'quantity': int.parse(quantity.text),
          'note': note.text.trim(),
          'batch_code': batch.text.trim(),
          if (assigneeId != null) 'assignee_id': assigneeId,
          'tracking_mode': serialMode ? 'serial' : 'batch',
          'serial_numbers': serialMode
              ? serials.text
                    .split(RegExp(r'[\s,，]+'))
                    .where((s) => s.isNotEmpty)
                    .toList()
              : [],
          if (templateId != null || account.templates.isNotEmpty)
            'template_id': templateId ?? account.templates.first['id'],
        },
      );
      if (draftStorageKey != null) await account.deleteDraft(draftStorageKey!);
      await account.reload();
      if (mounted && account.retainsAccess(accessBinding)) {
        cloudOutcome(context, '任务已创建');
        Navigator.pop(context);
      }
    } on CollaborationApiException catch (failure) {
      if (mounted && account.retainsAccess(accessBinding)) {
        AppScope.of(context).feedback(kind: AppFeedback.warning);
        setState(() => error = failure.message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) {
      return cloudAccessRequired(context, onLogin: recoverLogin);
    }
    if (recovering) {
      return DetailScaffold(
        title: tr(context, '恢复草稿'),
        children: const [CloudLoadingPanel()],
      );
    }
    if (recoveryFailure != null) {
      return cloudDraftRecoveryFailure(context, recoveryFailure!, reopenDraft);
    }
    if (!account.retainsAccess(accessBinding) ||
        (draftStorageKey != null &&
            draftStorageKey != account.draftKey('create'))) {
      return cloudScopeChanged(context);
    }
    InputDecoration field(String label, IconData icon) => InputDecoration(
      labelText: tr(context, label),
      errorMaxLines: 3,
      prefixIcon: Icon(icon, size: 19),
    );
    return DetailScaffold(
      title: tr(context, '新建任务'),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.add_task, color: blue, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, '创建生产质检单'),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr(context, '填写工件信息，草稿会自动保存在本机。'),
                      style: const TextStyle(fontSize: 10.5, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Form(
          key: form,
          onChanged: saveDraft,
          child: Column(
            children: [
              SectionHeader(
                tr(context, '基本信息'),
                icon: Icons.inventory_2_outlined,
              ),
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: name,
                      enabled: !busy,
                      maxLength: 100,
                      decoration: field('零件名称', Icons.badge_outlined),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? tr(context, '请填写零件名称')
                          : null,
                    ),
                    TextFormField(
                      controller: printer,
                      enabled: !busy,
                      maxLength: 80,
                      decoration: field('打印设备', Icons.print_outlined),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? tr(context, '请填写打印设备')
                          : null,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: quantity,
                            enabled: !busy,
                            keyboardType: TextInputType.number,
                            decoration: field('工件数量', Icons.numbers),
                            validator: (v) =>
                                (int.tryParse(v ?? '') ?? 0) < 1 ||
                                    (int.tryParse(v ?? '') ?? 0) > 999
                                ? tr(context, '数量需要在1至999之间')
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: batch,
                            enabled: !busy,
                            maxLength: 80,
                            decoration: field('批次号', Icons.qr_code_2),
                          ),
                        ),
                      ],
                    ),
                    if (account.templates.isNotEmpty)
                      DropdownButtonFormField<int>(
                        initialValue:
                            templateId ?? account.templates.first['id'] as int,
                        isExpanded: true,
                        decoration: field('检查模板', Icons.fact_check_outlined),
                        items: account.templates
                            .map(
                              (t) => DropdownMenuItem<int>(
                                value: t['id'] as int,
                                child: Text('${t['name']} · v${t['version']}'),
                              ),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (value) {
                                setState(() => templateId = value);
                                saveDraft();
                              },
                      ),
                    if (teamMembers.isNotEmpty)
                      DropdownButtonFormField<int>(
                        initialValue: assigneeId,
                        isExpanded: true,
                        decoration: field('负责人', Icons.person_outline),
                        items: [
                          DropdownMenuItem<int>(
                            value: null,
                            child: Text(tr(context, '未指派')),
                          ),
                          ...teamMembers.map(
                            (m) => DropdownMenuItem<int>(
                              value: m['id'] as int,
                              child: Text(
                                '${m['display_name'] ?? m['username']}',
                              ),
                            ),
                          ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) {
                                setState(() => assigneeId = value);
                                saveDraft();
                              },
                      ),
                  ],
                ),
              ),
              SectionHeader(tr(context, '追踪与备注'), icon: Icons.route_outlined),
              GlassPanel(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        tr(context, '逐件SN追踪'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      subtitle: Text(
                        tr(context, '为每个工件登记独立检验结论'),
                        style: const TextStyle(fontSize: 10.5, color: muted),
                      ),
                      value: serialMode,
                      onChanged: busy
                          ? null
                          : (value) {
                              setState(() => serialMode = value);
                              saveDraft();
                            },
                    ),
                    if (serialMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextFormField(
                          controller: serials,
                          enabled: !busy,
                          minLines: 2,
                          maxLines: 5,
                          decoration: field('SN，每行一个', Icons.list_alt),
                          validator: (value) {
                            final rows = (value ?? '')
                                .split(RegExp(r'[\s,，]+'))
                                .where((s) => s.isNotEmpty)
                                .toList();
                            if (rows.length != int.tryParse(quantity.text) ||
                                rows.toSet().length != rows.length ||
                                rows.any((s) => s.length > 100)) {
                              return tr(context, 'SN需要与工件数量一致且不能重复');
                            }
                            return null;
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextFormField(
                        controller: note,
                        enabled: !busy,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 4,
                        decoration: field('备注', Icons.notes_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  textStyle: TextStyle(
                    fontFamily: Theme.of(
                      context,
                    ).textTheme.labelLarge?.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(tr(context, '保存草稿')),
                onPressed: busy
                    ? null
                    : () async {
                        await saveDraft();
                        if (context.mounted && error == null) {
                          toast(context, '草稿已保存');
                        }
                      },
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  textStyle: TextStyle(
                    fontFamily: Theme.of(
                      context,
                    ).textTheme.labelLarge?.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: busy || !account.canEdit ? null : submit,
                icon: const Icon(Icons.check, size: 18),
                label: Text(tr(context, '创建任务')),
              ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              trMessage(context, error!),
              style: const TextStyle(color: red, fontSize: 12),
            ),
          ),
        if (busy) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

class CloudTaskPage extends StatefulWidget {
  final Map<String, dynamic> job;
  final int workspaceId;
  const CloudTaskPage({
    super.key,
    required this.job,
    required this.workspaceId,
  });
  @override
  State<CloudTaskPage> createState() => _CloudTaskPageState();
}

class _CloudTaskPageState extends State<CloudTaskPage> {
  late Map<String, dynamic> job = widget.job;
  List<Map<String, dynamic>> history = [];
  int tab = 0;
  bool busy = false, loaded = false, wasCurrent = false;
  Object? error;
  String? binding;
  Object? pageOwner, recoveryFailure;
  bool recovering = false;
  String get base => 'workspaces/${widget.workspaceId}/jobs/${job['id']}/';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    final account = CloudScope.of(context);
    if (!loaded) {
      loaded = true;
      binding = account.accessScope;
      pageOwner = account.profile?['id'];
      load();
    } else if (current &&
        !wasCurrent &&
        !recovering &&
        (account.retainsAccess(binding) ||
            (pageOwner != null && account.profile?['id'] == pageOwner)) &&
        account.activeWorkspace?['id'] == widget.workspaceId) {
      binding = account.accessScope;
      load();
    }
    wasCurrent = current;
  }

  Future<void> recoverLogin() async {
    setState(() => recovering = true);
    try {
      if (await cloudReauthenticate(context) && mounted) await reopenPage();
    } finally {
      if (mounted) setState(() => recovering = false);
    }
  }

  Future<void> reopenPage() async {
    final account = CloudScope.of(context);
    setState(() {
      recovering = true;
      recoveryFailure = null;
    });
    try {
      final captured = await cloudRestoreDraftAccess(
        account,
        pageOwner,
        widget.workspaceId,
        write: false,
      );
      if (!mounted) return;
      account.requireAccess(captured);
      setState(() {
        binding = captured;
        wasCurrent = true;
      });
      await load();
    } catch (failure) {
      if (mounted) setState(() => recoveryFailure = failure);
    } finally {
      if (mounted) setState(() => recovering = false);
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context), captured = binding;
    if (!account.retainsAccess(captured)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final latest = Map<String, dynamic>.from(
        await account.request('GET', base) as Map,
      );
      final events = (await account.request('GET', '${base}history/') as List)
          .cast<Map<String, dynamic>>();
      if (mounted && captured == binding && account.retainsAccess(captured)) {
        setState(() {
          job = latest;
          history = events;
        });
      }
    } on CollaborationApiException catch (failure) {
      if (mounted && captured == binding && account.retainsAccess(captured)) {
        setState(() => error = failure);
      }
    } catch (failure) {
      if (mounted && captured == binding && account.retainsAccess(captured)) {
        setState(() => error = failure);
      }
    } finally {
      if (mounted && captured == binding) setState(() => busy = false);
    }
  }

  Future<void> command(String action, {Map<String, dynamic>? issue}) async {
    await Navigator.of(context).push<void>(
      appPageRoute<void>(
        context,
        CloudTaskCommandPage(
          job: job,
          workspaceId: widget.workspaceId,
          action: action,
          issue: issue,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) {
      return cloudAccessRequired(context, onLogin: recoverLogin);
    }
    if (recovering) {
      return DetailScaffold(
        title: tr(context, '正在加载'),
        children: const [CloudLoadingPanel()],
      );
    }
    if (recoveryFailure != null) {
      return cloudDraftRecoveryFailure(context, recoveryFailure!, reopenPage);
    }
    if (account.activeWorkspace?['id'] != widget.workspaceId) {
      return cloudScopeChanged(context);
    }
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    final canEdit =
        account.canEdit && account.activeWorkspace?['id'] == widget.workspaceId;
    final status = '${job['status']}',
        checks = (job['inspections'] as List? ?? []),
        issues = (job['exceptions'] as List? ?? []),
        evidence = (job['evidence'] as List? ?? []);
    final partName = '${job['part_name']}';
    final openIssues = issues.where((i) => i['status'] == 'open').length;
    final actionLabel = switch (status) {
      'queued' => tr(context, '开始打印'),
      'printing' => tr(context, '送检'),
      'inspection' => tr(context, '登记检验'),
      'exception' => tr(context, '处理异常'),
      _ => null,
    };
    void primaryAction() {
      if (status == 'exception') {
        setState(() => tab = 2);
      } else {
        command(
          status == 'inspection'
              ? 'inspect'
              : status == 'queued'
              ? 'printing'
              : 'inspection',
        );
      }
    }

    return DetailScaffold(
      title: partName,
      actions: [
        IconButton(
          icon: const Icon(Icons.qr_code, size: 21),
          tooltip: tr(context, '任务二维码'),
          onPressed: () => openPage(
            context,
            CloudTraceCodePage(
              trace: TaskTrace(widget.workspaceId, '${job['id']}'),
              partName: partName,
              batchCode: '${job['batch_code'] ?? ''}',
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 21),
          tooltip: tr(context, '复制追溯号'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: '${job['id']}'));
            if (context.mounted) toast(context, '已复制');
          },
        ),
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh, size: 21),
          tooltip: tr(context, '刷新'),
        ),
      ],
      children: [
        PartArt(
          partName: partName,
          defect: status == 'exception' || openIssues > 0,
          height: 186,
          caption: 'CAM 01 · TOP',
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
                        SelectableText(
                          '${job['id']}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: muted,
                            letterSpacing: .3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tag(
                    tr(context, taskStatusLabels[status] ?? status),
                    color: taskColor(status),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InfoGrid(
                items: {
                  tr(context, '打印设备'): '${job['printer'] ?? ''}',
                  tr(context, '工件数量'):
                      '${job['quantity'] ?? ''} ${tr(context, '件')}',
                  tr(context, '批次号'): '${job['batch_code'] ?? ''}',
                  tr(context, '负责人'): '${job['assignee'] ?? ''}'.isEmpty
                      ? tr(context, '未指派')
                      : '${job['assignee']}',
                  tr(context, '创建时间'): cloudTimestamp(job['created_at']),
                },
              ),
              if ('${job['note'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFF),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFEDF3FB)),
                  ),
                  child: Text(
                    '${job['note']}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: muted,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        textStyle: TextStyle(
                          fontFamily: Theme.of(
                            context,
                          ).textTheme.labelLarge?.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      icon: const Icon(Icons.description_outlined, size: 17),
                      label: Text(tr(context, '质量报告')),
                      onPressed: () => openPage(
                        context,
                        CloudReportPage(jobId: '${job['id']}'),
                      ),
                    ),
                  ),
                  if (canEdit &&
                      !busy &&
                      error == null &&
                      actionLabel != null) ...[
                    const SizedBox(width: 9),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          textStyle: TextStyle(
                            fontFamily: Theme.of(
                              context,
                            ).textTheme.labelLarge?.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: primaryAction,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                        label: Text(actionLabel),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CloudLifecycleTrack(job: job),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final e in {0: '概览', 1: '质检', 2: '异常', 3: '历史'}.entries)
                ButtonSegment(value: e.key, label: Text(tr(context, e.value))),
            ],
            selected: {tab},
            onSelectionChanged: (selected) =>
                setState(() => tab = selected.first),
          ),
        ),
        const SizedBox(height: 14),
        if (busy) const CloudLoadingPanel(),
        if (error != null) CloudFailurePanel(failure: error!, onRetry: load),
        if (tab == 0) ...[
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: tr(context, '检验轮次'),
                  value: '${checks.length}',
                  icon: Icons.fact_check_outlined,
                  color: blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: tr(context, '未关闭异常'),
                  value: '$openIssues',
                  icon: Icons.report_gmailerrorred_outlined,
                  color: openIssues > 0 ? red : green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: tr(context, '照片证据'),
                  value: '${evidence.length}',
                  icon: Icons.photo_library_outlined,
                  color: green,
                ),
              ),
            ],
          ),
          SectionHeader(tr(context, '最近动态'), icon: Icons.history),
          if (history.isEmpty)
            GlassPanel(
              padding: const EdgeInsets.all(14),
              child: Text(
                tr(context, '暂无事件'),
                style: const TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
          ...history.take(4).map((event) => CloudHistoryEvent(event: event)),
        ],
        if (tab == 1) ...[
          if (canEdit && !busy && error == null && status == 'inspection')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FilledButton.icon(
                onPressed: () => command('inspect'),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text(tr(context, '登记检验')),
              ),
            ),
          if (checks.isEmpty)
            EmptyState(
              title: tr(context, '暂无检验记录'),
              subtitle: tr(context, '完成检验后可在这里查看记录。'),
            ),
          for (var i = 0; i < checks.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: GlassPanel(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => openPage(
                      context,
                      CloudInspectionDetailPage(
                        record: Map<String, dynamic>.from(checks[i] as Map),
                      ),
                    ),
                    child: Row(
                      children: [
                        PartThumb(
                          partName: partName,
                          size: 52,
                          defect: checks[i]['verdict'] != 'pass',
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${tr(context, '检验轮次')} ${checks[i]['round_no'] ?? checks.length - i}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: ink,
                                      ),
                                    ),
                                  ),
                                  Tag(
                                    tr(
                                      context,
                                      checks[i]['verdict'] == 'pass'
                                          ? '合格'
                                          : '异常',
                                    ),
                                    color: checks[i]['verdict'] == 'pass'
                                        ? green
                                        : red,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cloudTimestamp(checks[i]['created_at']),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: muted,
                                ),
                              ),
                              if ('${checks[i]['note'] ?? ''}'.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    '${checks[i]['note']}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF7D8EA5),
                                    ),
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
        ],
        if (tab == 2) ...[
          if (issues.isEmpty)
            EmptyState(
              title: tr(context, '暂无异常'),
              subtitle: tr(context, '当前任务没有异常记录。'),
            ),
          ...issues.map(
            (issue) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PartThumb(partName: partName, size: 40, defect: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Tag(
                                tr(
                                  context,
                                  issue['status'] == 'open' ? '待处理' : '已处理',
                                ),
                                color: issue['status'] == 'open' ? red : green,
                              ),
                              const SizedBox(width: 6),
                              Tag(
                                tr(context, switch (issue['severity']) {
                                  'critical' => '严重',
                                  'minor' => '轻微',
                                  _ => '主要',
                                }),
                                color: amber,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          tr(
                            context,
                            cloudCategories[issue['category']] ?? '其他',
                          ),
                          style: const TextStyle(fontSize: 10.5, color: muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Text(
                      '${issue['note']}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${tr(context, '负责人')}：${issue['assignee'] ?? tr(context, '未指派')}',
                      style: const TextStyle(fontSize: 10.5, color: muted),
                    ),
                    if ('${issue['resolution'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: green.withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${issue['resolution']}',
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              color: Color(0xFF31725F),
                            ),
                          ),
                        ),
                      ),
                    if (canEdit &&
                        !busy &&
                        error == null &&
                        issue['status'] == 'open') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final stage in {
                            'before': '处置前照片',
                            'after': '处置后照片',
                          }.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  textStyle: TextStyle(
                                    fontFamily: Theme.of(
                                      context,
                                    ).textTheme.labelLarge?.fontFamily,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                icon: const Icon(Icons.add_a_photo, size: 15),
                                label: Text(tr(context, stage.value)),
                                onPressed: () async {
                                  try {
                                    await cloudPickPhoto(
                                      context,
                                      job,
                                      issue: Map<String, dynamic>.from(
                                        issue as Map,
                                      ),
                                      stage: stage.key,
                                    );
                                    if (mounted) await load();
                                  } catch (failure) {
                                    if (mounted) {
                                      setState(() => error = failure);
                                    }
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                    OutlinedButton.icon(
                      icon: const Icon(Icons.compare, size: 16),
                      label: Text(tr(context, '整改前后对比')),
                      onPressed: () => openPage(
                        context,
                        CloudEvidenceComparePage(
                          jobId: '${job['id']}',
                          issueId: issue['id'] as int,
                          photos: evidence
                              .map(
                                (row) => Map<String, dynamic>.from(row as Map),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                    for (final photo in evidence.where(
                      (p) => p['issue_id'] == issue['id'],
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            alignment: Alignment.centerLeft,
                            textStyle: TextStyle(
                              fontFamily: Theme.of(
                                context,
                              ).textTheme.labelLarge?.fontFamily,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(Icons.photo, size: 15),
                          label: Text(
                            tr(
                              context,
                              photo['stage'] == 'after' ? '处置后照片' : '处置前照片',
                            ),
                          ),
                          onPressed: () => openPage(
                            context,
                            CloudEvidencePage(
                              jobId: '${job['id']}',
                              photo: Map<String, dynamic>.from(photo as Map),
                            ),
                          ),
                        ),
                      ),
                    if (canEdit &&
                        !busy &&
                        error == null &&
                        issue['status'] == 'open')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            textStyle: TextStyle(
                              fontFamily: Theme.of(
                                context,
                              ).textTheme.labelLarge?.fontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: () => command(
                            'resolve',
                            issue: Map<String, dynamic>.from(issue as Map),
                          ),
                          icon: const Icon(Icons.build_outlined, size: 16),
                          label: Text(tr(context, '处理异常')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (tab == 3) ...[
          if (history.isEmpty && !busy)
            EmptyState(
              title: tr(context, '暂无事件'),
              subtitle: tr(context, '任务操作后可在这里查看历史。'),
            ),
          ...history.map((event) => CloudHistoryEvent(event: event)),
        ],
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(height: 9),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            height: 1,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: -.7,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: muted),
        ),
      ],
    ),
  );
}

class CloudTaskCommandPage extends StatefulWidget {
  final Map<String, dynamic> job;
  final int workspaceId;
  final String action;
  final Map<String, dynamic>? issue;
  const CloudTaskCommandPage({
    super.key,
    required this.job,
    required this.workspaceId,
    required this.action,
    this.issue,
  });
  @override
  State<CloudTaskCommandPage> createState() => _CloudTaskCommandPageState();
}

class _CloudTaskCommandPageState extends State<CloudTaskCommandPage> {
  final form = GlobalKey<FormState>();
  Map<String, dynamic>? acceptedJob;
  late Map<String, dynamic> comparisonBase;
  final note = TextEditingController(), closureReason = TextEditingController();
  String nextStatus = 'inspection', disposition = 'scrapped';
  String key = 'cloud-${uid()}';
  String verdict = 'pass', category = 'other', severity = 'major';
  Map<String, dynamic>? template;
  final Map<String, String> answers = {}, answerNotes = {}, serialResults = {};
  final List<int> evidence = [];
  final passed = TextEditingController(),
      failed = TextEditingController(text: '0'),
      scrapped = TextEditingController(text: '0');
  String? accessBinding;
  Object? draftOwner, recoveryFailure;
  bool recovering = false;
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      comparisonBase = cloudTaskSnapshot(widget.job);
      final account = CloudScope.of(context);
      accessBinding = account.accessScope;
      draftOwner = account.profile?['id'];
      template =
          widget.job['template'] as Map<String, dynamic>? ??
          (account.templates.isEmpty ? null : account.templates.first);
      passed.text = '${widget.job['quantity']}';
      draftAccount = account;
      if (widget.action == 'inspect' || widget.action == 'resolve') {
        draftStorageKey = account.draftKey(
          '${widget.action}-${widget.job['id']}',
        );
      }
      for (final sn in widget.job['serial_numbers'] as List? ?? []) {
        serialResults['$sn'] = 'pass';
      }
      for (final controller in [
        note,
        passed,
        failed,
        scrapped,
        closureReason,
      ]) {
        controller.addListener(changedText);
      }
      if (draftStorageKey != null) {
        unawaited(restoreDraft());
      } else {
        draftReady = true;
      }
    }
  }

  CloudAccount? draftAccount;
  Future<void> recoverLogin() async {
    if (await cloudReauthenticate(context) && mounted) await reopenDraft();
  }

  Future<void> reopenDraft() async {
    final account = CloudScope.of(context);
    setState(() {
      recovering = true;
      recoveryFailure = null;
    });
    try {
      final captured = await cloudRestoreDraftAccess(
        account,
        draftOwner,
        widget.workspaceId,
      );
      final latest = Map<String, dynamic>.from(
        await account.request(
              'GET',
              'workspaces/${widget.workspaceId}/jobs/${widget.job['id']}/',
            )
            as Map,
      );
      if (!mounted) return;
      account.requireAccess(captured, write: true);
      setState(() {
        accessBinding = captured;
        savedVersion ??=
            acceptedJob?['version'] as int? ?? widget.job['version'] as int?;
        if (latest['version'] != savedVersion) {
          conflict = latest;
          error = '任务已更新，请核对当前任务后处理草稿';
        } else {
          acceptedJob = latest;
        }
      });
    } catch (failure) {
      if (mounted) setState(() => recoveryFailure = failure);
    } finally {
      if (mounted) setState(() => recovering = false);
    }
  }

  String? draftStorageKey, draftError;
  bool draftReady = false, draftFinished = false, restoreFailed = false;
  int? savedVersion;
  void changedText() {
    if (draftReady && !draftFinished) unawaited(persistDraft());
  }

  void edit(VoidCallback change) {
    setState(change);
    changedText();
  }

  Future<void> restoreDraft() async {
    try {
      final data = await draftAccount!.readDraft(draftStorageKey!);
      if (!mounted || !draftAccount!.retainsAccess(accessBinding)) return;
      if (data != null) {
        note.text = '${data['note'] ?? ''}';
        nextStatus = '${data['next_status'] ?? 'inspection'}';
        disposition = '${data['disposition'] ?? 'scrapped'}';
        closureReason.text = '${data['closure_reason'] ?? ''}';
        key = data['request_key'] as String? ?? key;
        verdict = '${data['verdict'] ?? 'pass'}';
        category = '${data['category'] ?? 'other'}';
        severity = '${data['severity'] ?? 'major'}';
        passed.text = '${data['passed'] ?? widget.job['quantity']}';
        failed.text = '${data['failed'] ?? 0}';
        scrapped.text = '${data['scrapped'] ?? 0}';
        answers.addAll(Map<String, String>.from(data['answers'] as Map? ?? {}));
        answerNotes.addAll(
          Map<String, String>.from(data['answer_notes'] as Map? ?? {}),
        );
        serialResults.addAll(
          Map<String, String>.from(data['serial_results'] as Map? ?? {}),
        );
        evidence.addAll((data['evidence'] as List? ?? []).cast<int>());
        if (data['template'] is Map) {
          template = Map<String, dynamic>.from(data['template'] as Map);
        }
        savedVersion = data['version'] as int?;
        if (data['task_snapshot'] is Map) {
          comparisonBase = Map<String, dynamic>.from(
            data['task_snapshot'] as Map,
          );
        } else if (savedVersion != null &&
            savedVersion != widget.job['version']) {
          comparisonBase = {'version': savedVersion};
        }
        if (savedVersion != null && savedVersion != widget.job['version']) {
          conflict = widget.job;
          error = '任务已更新，请核对当前任务后处理草稿';
        }
      }
      setState(() {
        draftReady = true;
        restoreFailed = false;
        draftError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          draftReady = true;
          restoreFailed = true;
          draftError = '无法恢复草稿，请重试';
        });
      }
    }
  }

  Future<void> persistDraft() async {
    final account = draftAccount;
    if (restoreFailed ||
        !draftReady ||
        draftFinished ||
        draftStorageKey == null ||
        account == null ||
        draftStorageKey !=
            account.draftKey('${widget.action}-${widget.job['id']}')) {
      return;
    }
    try {
      await account.saveDraft(draftStorageKey!, {
        'request_key': key,
        'job_id': widget.job['id'],
        'part_name': widget.job['part_name'],
        'action': widget.action,
        'issue_id': widget.issue?['id'],
        'version': savedVersion ?? widget.job['version'],
        'task_snapshot': comparisonBase,
        'note': note.text,
        'next_status': nextStatus,
        'disposition': disposition,
        'closure_reason': closureReason.text,
        'verdict': verdict,
        'category': category,
        'severity': severity,
        'passed': passed.text,
        'failed': failed.text,
        'scrapped': scrapped.text,
        'answers': answers,
        'answer_notes': answerNotes,
        'serial_results': serialResults,
        'evidence': evidence,
        'template': template,
      });
      if (mounted && draftError != null) setState(() => draftError = null);
    } catch (_) {
      if (mounted) setState(() => draftError = '草稿保存失败，请重试');
    }
  }

  bool busy = false;
  bool checklistChanged = false;
  String? error;
  Map<String, dynamic>? conflict;
  @override
  void dispose() {
    note.dispose();
    closureReason.dispose();
    passed.dispose();
    failed.dispose();
    scrapped.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final account = CloudScope.of(context), action = widget.action;
    if (!account.retainsAccess(accessBinding) ||
        !account.canEdit ||
        account.activeWorkspace?['id'] != widget.workspaceId) {
      return;
    }
    if (!validateCloudForm(form)) {
      AppScope.of(context).feedback(kind: AppFeedback.warning);
      return;
    }
    edit(() {
      busy = true;
      error = null;
    });
    try {
      await persistDraft();
      if (draftError != null) throw CollaborationApiException(503, draftError!);
      CloudOutbox? outbox;
      List<Map<String, dynamic>> uploads = [];
      if (draftStorageKey != null) {
        outbox = CloudOutbox(account);
        uploads = (await outbox.list())
            .where((r) => r['job_id'] == '${widget.job['id']}')
            .toList();
        if (uploads.any((r) => r['state'] != 'uploaded')) {
          throw const CollaborationApiException(409, '还有图片待上传，请先在同步页面完成上传');
        }
        if (action == 'inspect' && uploads.isNotEmpty) {
          final latest =
              await account.request(
                    'GET',
                    'workspaces/${widget.workspaceId}/jobs/${widget.job['id']}/',
                  )
                  as Map;
          final unbound = (latest['evidence'] as List? ?? [])
              .where((p) => p['inspection_id'] == null)
              .map((p) => p['id'])
              .toSet();
          for (final row in uploads.where(
            (r) =>
                r['stage'] == 'inspection' &&
                unbound.contains(r['evidence_id']),
          )) {
            if (!evidence.contains(row['evidence_id'])) {
              evidence.add(row['evidence_id'] as int);
            }
          }
          await persistDraft();
        }
      }
      account.requireAccess(accessBinding, write: true);
      final base = 'workspaces/${widget.workspaceId}';
      final path = action == 'resolve'
          ? '$base/exceptions/${widget.issue!['id']}/resolve/'
          : '$base/jobs/${widget.job['id']}/${action == 'inspect' ? 'inspection/' : ''}';
      await account.request(
        action == 'inspect' || action == 'resolve' ? 'POST' : 'PATCH',
        path,
        idempotencyKey: key,
        body: {
          'version': savedVersion ?? widget.job['version'],
          if (action == 'inspect') ...{
            'verdict': verdict,
            'note': note.text.trim(),
            'inspected_qty':
                (int.tryParse(passed.text) ?? 0) +
                (int.tryParse(failed.text) ?? 0) +
                (int.tryParse(scrapped.text) ?? 0),
            'pass_qty': int.tryParse(passed.text) ?? -1,
            'fail_qty': int.tryParse(failed.text) ?? -1,
            'scrap_qty': int.tryParse(scrapped.text) ?? -1,
            if (template != null) 'template_id': template!['id'],
            'answers': [
              for (final item in template?['items'] as List? ?? [])
                {
                  'id': item['id'],
                  'result': answers['${item['id']}'],
                  'note': answerNotes['${item['id']}'] ?? '',
                },
            ],
            'serial_results': serialResults,
            'category': category,
            'severity': severity,
            'evidence_ids': evidence,
          },
          if (action == 'resolve') ...{
            'resolution': note.text.trim(),
            'next_status': nextStatus,
            if (nextStatus == 'closed') ...{
              'disposition': disposition,
              'closure_reason': closureReason.text.trim(),
            },
          },
          if (action != 'resolve' && action != 'inspect') 'status': action,
        },
      );
      draftFinished = true;
      if (draftStorageKey != null) await account.deleteDraft(draftStorageKey!);
      if (outbox != null) {
        await outbox.consume(
          '${widget.job['id']}',
          action == 'inspect'
              ? evidence
              : uploads.map((r) => r['evidence_id'] as int).toList(),
        );
      }
      await account.reload();
      if (mounted && account.retainsAccess(accessBinding)) {
        cloudOutcome(
          context,
          action == 'inspect'
              ? (verdict == 'fail' ? '异常已提交' : '检验已提交')
              : action == 'resolve'
              ? '处理结果已提交'
              : '任务状态已更新',
          warning: action == 'inspect' && verdict == 'fail',
        );
        Navigator.pop(context);
      }
    } on CollaborationApiException catch (failure) {
      if (mounted && account.retainsAccess(accessBinding)) {
        AppScope.of(context).feedback(kind: AppFeedback.warning);
        edit(() {
          error = failure.message;
          conflict = failure.details?['current'] as Map<String, dynamic>?;
        });
      }
    } catch (_) {
      if (mounted && account.retainsAccess(accessBinding)) {
        AppScope.of(context).feedback(kind: AppFeedback.warning);
        edit(() => error = '网络连接失败，草稿已保留，请重试');
      }
    } finally {
      if (mounted) edit(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) {
      return cloudAccessRequired(context, onLogin: recoverLogin);
    }
    if (recovering) {
      return DetailScaffold(
        title: tr(context, '恢复草稿'),
        children: const [CloudLoadingPanel()],
      );
    }
    if (recoveryFailure != null) {
      return cloudDraftRecoveryFailure(context, recoveryFailure!, reopenDraft);
    }
    if (!account.retainsAccess(accessBinding) ||
        (draftStorageKey != null &&
            draftStorageKey !=
                account.draftKey('${widget.action}-${widget.job['id']}')) ||
        account.activeWorkspace?['id'] != widget.workspaceId) {
      return cloudScopeChanged(context);
    }
    if (!draftReady) {
      return DetailScaffold(
        title: tr(context, '恢复草稿'),
        children: const [LinearProgressIndicator()],
      );
    }
    final title = switch (widget.action) {
      'inspect' => '登记检验',
      'resolve' => '处理异常',
      'printing' => '开始打印',
      _ => '送检',
    };
    final job = acceptedJob ?? widget.job;
    final partName = '${job['part_name']}';
    final status = '${job['status']}';
    final canEdit = account.canEdit;
    final inspect = widget.action == 'inspect';
    final failing = verdict == 'fail';
    final items = template?['items'] as List? ?? const [];
    const hint = TextStyle(fontSize: 11.5, height: 1.5, color: muted);

    Widget group(
      String label, {
      IconData? icon,
      String? caption,
      Widget? action,
      String? Function()? validate,
      required Widget child,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          tr(context, label),
          icon: icon,
          caption: caption,
          action: action,
        ),
        if (validate == null)
          child
        else
          CloudValidation(validate: validate, child: child),
      ],
    );

    return DetailScaffold(
      title: tr(context, title),
      children: [
        CloudForm(
          formKey: form,
          children: [
            PartArt(
              partName: partName,
              defect: failing || widget.action == 'resolve',
              height: 172,
              caption: widget.action == 'resolve'
                  ? tr(context, '异常工件')
                  : tr(context, '待检工件'),
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
                            const SizedBox(height: 5),
                            Text(
                              '${job['id']} · ${tr(context, '数量')} ${job['quantity']} ${tr(context, '件')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: muted,
                                letterSpacing: .2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tag(
                        tr(context, taskStatusLabels[status] ?? status),
                        color: taskColor(status),
                      ),
                    ],
                  ),
                  if (widget.issue != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7F4),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0xFFFFE0D6)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.report_gmailerrorred_outlined,
                            size: 18,
                            color: red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${widget.issue!['note'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (draftStorageKey != null) ...[
              const SizedBox(height: 12),
              GlassPanel(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: blue.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.cloud_done_outlined,
                        size: 19,
                        color: blue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context, '离线草稿'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(tr(context, '输入内容会自动保存在本机'), style: hint),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await persistDraft();
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                appPageRoute<void>(
                                  context,
                                  const CloudSyncPage(),
                                ),
                              );
                              if (mounted) edit(() {});
                            },
                      child: Text(tr(context, '同步与草稿')),
                    ),
                  ],
                ),
              ),
            ],
            if (restoreFailed)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: restoreDraft,
                    child: Text(tr(context, '重试恢复草稿')),
                  ),
                ),
              ),
            if (draftError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  trMessage(context, draftError!),
                  style: const TextStyle(color: red, fontSize: 12),
                ),
              ),
            if (checklistChanged)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  tr(context, '检查模板已更新，请重新逐项核对。'),
                  style: const TextStyle(color: amber),
                ),
              ),
            if (inspect) ...[
              group(
                '检验结论',
                icon: Icons.fact_check_outlined,
                child: GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: 'pass',
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: Text(tr(context, '合格')),
                            ),
                            ButtonSegment(
                              value: 'fail',
                              icon: const Icon(Icons.warning_amber, size: 18),
                              label: Text(tr(context, '异常')),
                            ),
                          ],
                          selected: {verdict},
                          onSelectionChanged: busy
                              ? null
                              : (value) => edit(() {
                                  verdict = value.first;
                                  if (serialResults.isEmpty) {
                                    passed.text = verdict == 'pass'
                                        ? '${job['quantity']}'
                                        : '0';
                                    failed.text = verdict == 'fail'
                                        ? '${job['quantity']}'
                                        : '0';
                                    scrapped.text = '0';
                                  }
                                }),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        failing
                            ? tr(context, '发现异常时将生成异常单，请补充类别与说明。')
                            : tr(context, '逐项核对检查项，并确认合格与异常数量。'),
                        style: hint,
                      ),
                    ],
                  ),
                ),
              ),
              if (items.isNotEmpty)
                group(
                  '检查项',
                  icon: Icons.checklist_rtl,
                  caption: '${items.length} ${tr(context, '项')}',
                  child: GlassPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          CloudValidation(
                            validate: () {
                              final result = answers['${items[i]['id']}'];
                              if (result == null &&
                                  items[i]['required'] == true) {
                                return '请选择检查结果';
                              }
                              if (result == 'fail' &&
                                  (answerNotes['${items[i]['id']}'] ?? '')
                                      .trim()
                                      .isEmpty) {
                                return '请填写问题说明';
                              }
                              if (result == 'fail' && verdict != 'fail') {
                                return '不合格项需要问题说明，并选择异常结论';
                              }
                              return null;
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: blue.withValues(alpha: .09),
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
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
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          '${items[i]['label']}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: ink,
                                          ),
                                        ),
                                      ),
                                      if (items[i]['required'] == true)
                                        Tag(tr(context, '必填'), color: amber),
                                    ],
                                  ),
                                  const SizedBox(height: 9),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final result in {
                                        'pass': '合格',
                                        'fail': '异常',
                                        if (items[i]['allow_na'] == true)
                                          'na': '不适用',
                                      }.entries)
                                        ChoiceChip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(
                                            tr(context, result.value),
                                          ),
                                          selected:
                                              answers['${items[i]['id']}'] ==
                                              result.key,
                                          onSelected: busy
                                              ? null
                                              : (_) => edit(() {
                                                  answers['${items[i]['id']}'] =
                                                      result.key;
                                                  if (result.key == 'fail') {
                                                    verdict = 'fail';
                                                  }
                                                }),
                                        ),
                                    ],
                                  ),
                                  if (answers['${items[i]['id']}'] == 'fail')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: TextFormField(
                                        key: ValueKey(
                                          'check-note-${template?['id']}-${template?['version']}-${items[i]['id']}',
                                        ),
                                        initialValue:
                                            answerNotes['${items[i]['id']}'] ??
                                            '',
                                        enabled: !busy,
                                        decoration: InputDecoration(
                                          labelText: tr(context, '问题说明'),
                                          isDense: true,
                                        ),
                                        onChanged: (value) {
                                          answerNotes['${items[i]['id']}'] =
                                              value;
                                          changedText();
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              group(
                '数量核对',
                icon: Icons.inventory_2_outlined,
                validate: () {
                  final counts = [
                    passed,
                    failed,
                    scrapped,
                  ].map((c) => int.tryParse(c.text.trim())).toList();
                  if (counts.any((n) => n == null || n < 0)) {
                    return '数量需要为非负整数';
                  }
                  final total = counts.fold<int>(0, (sum, n) => sum + n!);
                  if (total < 1 || total > (job['quantity'] as int)) {
                    return '送检数量必须等于合格、异常与报废数量之和，且不超过计划数量';
                  }
                  if ((verdict == 'pass' &&
                          (counts[1] != 0 ||
                              counts[2] != 0 ||
                              total != job['quantity'])) ||
                      (verdict == 'fail' && counts[1]! + counts[2]! == 0)) {
                    return '检验结论与工件数量不一致';
                  }
                  return null;
                },
                caption: serialResults.isEmpty
                    ? null
                    : tr(context, '已按 SN 自动统计'),
                child: GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      for (final field in <TextEditingController, String>{
                        passed: '合格数量',
                        failed: '异常数量',
                        scrapped: '报废数量',
                      }.entries) ...[
                        Expanded(
                          child: TextField(
                            controller: field.key,
                            enabled: !busy && serialResults.isEmpty,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: tr(context, field.value),
                            ),
                          ),
                        ),
                        if (field.key != scrapped) const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
              ),
              if (serialResults.isNotEmpty)
                group(
                  '逐件追溯',
                  icon: Icons.qr_code_2,
                  caption: '${serialResults.length} ${tr(context, '件')}',
                  child: GlassPanel(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                    child: Column(
                      children: [
                        for (final sn in serialResults.keys)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('serial-$sn'),
                              initialValue: serialResults[sn],
                              isDense: true,
                              decoration: InputDecoration(labelText: sn),
                              validator: (value) => value == null
                                  ? tr(context, '请为任务内每个SN填写唯一检验结论')
                                  : null,
                              items: [
                                for (final e in {
                                  'pass': '合格',
                                  'fail': '异常',
                                  'scrap': '报废',
                                }.entries)
                                  DropdownMenuItem(
                                    value: e.key,
                                    child: Text(tr(context, e.value)),
                                  ),
                              ],
                              onChanged: busy
                                  ? null
                                  : (value) => edit(() {
                                      serialResults[sn] = value!;
                                      passed.text =
                                          '${serialResults.values.where((v) => v == 'pass').length}';
                                      failed.text =
                                          '${serialResults.values.where((v) => v == 'fail').length}';
                                      scrapped.text =
                                          '${serialResults.values.where((v) => v == 'scrap').length}';
                                      verdict =
                                          int.parse(failed.text) +
                                                  int.parse(scrapped.text) >
                                              0
                                          ? 'fail'
                                          : 'pass';
                                    }),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (failing)
                group(
                  '异常信息',
                  icon: Icons.report_gmailerrorred_outlined,
                  child: GlassPanel(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: category,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: tr(context, '异常类别'),
                          ),
                          items: [
                            for (final e in {
                              'surface': '表面',
                              'dimension': '尺寸',
                              'crack': '裂纹',
                              'deformation': '变形',
                              'assembly': '装配',
                              'other': '其他',
                            }.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(tr(context, e.value)),
                              ),
                          ],
                          onChanged: busy ? null : (v) => category = v!,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: severity,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: tr(context, '严重程度'),
                          ),
                          items: [
                            for (final e in {
                              'minor': '轻微',
                              'major': '主要',
                              'critical': '严重',
                            }.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(tr(context, e.value)),
                              ),
                          ],
                          onChanged: busy ? null : (v) => severity = v!,
                        ),
                      ],
                    ),
                  ),
                ),
              group(
                '照片证据',
                icon: Icons.photo_camera_back_outlined,
                caption: '${evidence.length} ${tr(context, '张')}',
                child: GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F8FF),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: hairline),
                        ),
                        child: Icon(
                          evidence.isEmpty
                              ? Icons.add_photo_alternate_outlined
                              : Icons.photo_library_outlined,
                          size: 22,
                          color: evidence.isEmpty ? muted : blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          evidence.isEmpty
                              ? tr(context, '尚未添加照片，建议拍摄缺陷与整体外观。')
                              : tr(context, '已添加 {0} 张照片，提交后随检验记录归档。', [
                                  evidence.length,
                                ]),
                          style: hint,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            textStyle: TextStyle(
                              fontFamily: Theme.of(
                                context,
                              ).textTheme.labelLarge?.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          icon: const Icon(
                            Icons.add_a_photo_outlined,
                            size: 17,
                          ),
                          label: Text(tr(context, '添加检验照片')),
                          onPressed: busy
                              ? null
                              : () async {
                                  edit(() => busy = true);
                                  try {
                                    final id = await cloudPickPhoto(
                                      context,
                                      widget.job,
                                    );
                                    if (id != null && mounted) {
                                      edit(() => evidence.add(id));
                                    }
                                  } catch (failure) {
                                    if (mounted) {
                                      edit(() => error = '$failure');
                                    }
                                  } finally {
                                    if (mounted) edit(() => busy = false);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (widget.action == 'resolve' &&
                account.activeWorkspace?['role'] == 'owner') ...[
              group(
                '处置决定',
                icon: Icons.gavel_outlined,
                caption: tr(context, '仅团队所有者'),
                child: GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: nextStatus,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: tr(context, '处置后操作'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'inspection',
                            child: Text(tr(context, '送交复检')),
                          ),
                          DropdownMenuItem(
                            value: 'closed',
                            child: Text(tr(context, '授权关闭')),
                          ),
                        ],
                        onChanged: busy || conflict != null
                            ? null
                            : (value) => edit(() => nextStatus = value!),
                      ),
                      if (nextStatus == 'closed') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: disposition,
                          isDense: true,
                          decoration: InputDecoration(
                            labelText: tr(context, '关闭处置'),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'scrapped',
                              child: Text(tr(context, '报废关闭')),
                            ),
                            DropdownMenuItem(
                              value: 'concession',
                              child: Text(tr(context, '让步接收')),
                            ),
                          ],
                          onChanged: busy || conflict != null
                              ? null
                              : (value) => edit(() => disposition = value!),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: closureReason,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? tr(context, '请选择关闭处置并填写授权依据')
                              : null,
                          enabled: !busy && conflict == null,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 500,
                          decoration: InputDecoration(
                            labelText: tr(context, '授权依据'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (inspect || widget.action == 'resolve')
              group(
                widget.action == 'resolve' ? '处理结果' : '检验备注',
                icon: Icons.edit_note_outlined,
                child: GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: TextFormField(
                    controller: note,
                    validator: (value) =>
                        (widget.action == 'resolve' ||
                                (inspect && verdict == 'fail')) &&
                            (value ?? '').trim().isEmpty
                        ? tr(context, '请填写处理或异常说明')
                        : null,
                    enabled: !busy && conflict == null,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: widget.action == 'resolve'
                          ? tr(context, '说明处理方式、结果与后续安排')
                          : tr(context, '补充测量值、环境或沟通信息'),
                    ),
                  ),
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 18, color: red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          trMessage(context, error!),
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (conflict != null) ...[
              group(
                '状态冲突',
                icon: Icons.sync_problem_outlined,
                child: GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CloudTaskConflictComparison(
                        before: comparisonBase,
                        current: conflict!,
                      ),
                      const SizedBox(height: 12),
                      Text(tr(context, '任务已被其他人更新，请选择如何处理这份草稿。'), style: hint),
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: OutlinedButton.icon(
                          onPressed: () => openPage(
                            context,
                            CloudTaskPage(
                              job: conflict!,
                              workspaceId: widget.workspaceId,
                            ),
                          ),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(tr(context, '查看最新任务')),
                        ),
                      ),
                      if ((widget.action == 'inspect' &&
                              conflict!['status'] == 'inspection') ||
                          (widget.action == 'resolve' &&
                              conflict!['status'] == 'exception' &&
                              (conflict!['exceptions'] as List? ?? []).any(
                                (i) =>
                                    i['id'] == widget.issue?['id'] &&
                                    i['status'] == 'open',
                              )))
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: OutlinedButton(
                            onPressed: () async {
                              if (!await confirm(
                                context,
                                tr(context, '按当前任务继续'),
                                tr(context, '保留草稿内容继续编辑，已归档照片不会带入新检验。'),
                              )) {
                                return;
                              }
                              if (!mounted ||
                                  !account.retainsAccess(accessBinding) ||
                                  !account.canEdit) {
                                return;
                              }
                              edit(() {
                                final latest = conflict!;
                                final oldTemplate = comparisonBase['template'];
                                final newTemplate = latest['template'];
                                final templateChanged =
                                    (oldTemplate is Map
                                            ? oldTemplate['id']
                                            : null) !=
                                        (newTemplate is Map
                                            ? newTemplate['id']
                                            : null) ||
                                    (oldTemplate is Map
                                            ? oldTemplate['version']
                                            : null) !=
                                        (newTemplate is Map
                                            ? newTemplate['version']
                                            : null);
                                if (widget.action == 'inspect' &&
                                    templateChanged) {
                                  template = newTemplate is Map
                                      ? Map<String, dynamic>.from(newTemplate)
                                      : (account.templates.isEmpty
                                            ? null
                                            : account.templates.first);
                                  answers.clear();
                                  answerNotes.clear();
                                  checklistChanged = true;
                                }
                                if (latest['serial_numbers'] is List) {
                                  final serials =
                                      (latest['serial_numbers'] as List)
                                          .map((sn) => '$sn')
                                          .toSet();
                                  serialResults.removeWhere(
                                    (sn, _) => !serials.contains(sn),
                                  );
                                  for (final sn in serials) {
                                    serialResults.putIfAbsent(sn, () => 'pass');
                                  }
                                  if (serials.isNotEmpty) {
                                    passed.text =
                                        '${serialResults.values.where((v) => v == 'pass').length}';
                                    failed.text =
                                        '${serialResults.values.where((v) => v == 'fail').length}';
                                    scrapped.text =
                                        '${serialResults.values.where((v) => v == 'scrap').length}';
                                  }
                                }
                                savedVersion = latest['version'] as int;
                                acceptedJob = latest;
                                comparisonBase = cloudTaskSnapshot(latest);
                                final archived =
                                    (conflict!['evidence'] as List? ?? [])
                                        .where(
                                          (p) => p['inspection_id'] != null,
                                        )
                                        .map((p) => p['id'])
                                        .toSet();
                                evidence.removeWhere(archived.contains);
                                key = 'cloud-${uid()}';
                                conflict = null;
                                error = null;
                              });
                            },
                            child: Text(tr(context, '按当前任务继续')),
                          ),
                        ),
                      if (draftStorageKey != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton(
                            onPressed: () async {
                              if (!await confirm(
                                context,
                                tr(context, '放弃草稿'),
                                tr(context, '确认放弃这份未提交的草稿？'),
                              )) {
                                return;
                              }
                              draftFinished = true;
                              await account.deleteDraft(draftStorageKey!);
                              if (context.mounted) Navigator.pop(context);
                            },
                            child: Text(tr(context, '放弃草稿并刷新')),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr(context, '返回并刷新任务')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  textStyle: TextStyle(
                    fontFamily: Theme.of(
                      context,
                    ).textTheme.labelLarge?.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: busy || conflict != null || !canEdit ? null : submit,
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: Text(tr(context, '确认提交')),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, '提交后可在任务历史中查看结果并补充照片。'),
              textAlign: TextAlign.center,
              style: hint,
            ),
          ],
        ),
      ],
    );
  }
}

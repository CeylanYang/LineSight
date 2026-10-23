import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cloud_account.dart';
import '../cloud_outbox.dart';
import '../cloud_filters.dart';
import '../cloud_history.dart';
import '../cloud_feedback.dart';
import '../cloud_trace.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../models.dart' show uid;
import '../ui.dart';
import '../time.dart' show zonedStamp;
import 'cloud_business.dart';
import 'cloud_shell.dart' show CloudLoginPage;

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

Widget cloudAccessRequired(BuildContext context) => DetailScaffold(
  title: tr(context, '登录'),
  children: [
    Text(tr(context, '登录后查看任务与检验记录')),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: () => openPage(context, const CloudLoginPage()),
      child: Text(tr(context, '登录')),
    ),
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
                    textStyle: const TextStyle(
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
  bool draftLoaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!draftLoaded) {
      draftLoaded = true;
      final account = CloudScope.of(context);
      accessBinding = account.accessScope;
      draftStorageKey = account.draftKey('create');
      loadMembers(account);
      if (draftStorageKey != null) restoreDraft(account);
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
    if (!form.currentState!.validate()) return;
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
      if (mounted) Navigator.pop(context);
    } on CollaborationApiException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn ||
        (draftStorageKey != null &&
            draftStorageKey != account.draftKey('create'))) {
      return cloudAccessRequired(context);
    }
    if (!account.retainsAccess(accessBinding)) {
      return cloudScopeChanged(context);
    }
    InputDecoration field(String label, IconData icon) => InputDecoration(
      labelText: tr(context, label),
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
                            : (value) => setState(() => templateId = value),
                      ),
                    if (teamMembers.isNotEmpty)
                      DropdownButtonFormField<int>(
                        initialValue: assigneeId,
                        isExpanded: true,
                        decoration: field('负责人', Icons.person_outline),
                        items: teamMembers
                            .map(
                              (m) => DropdownMenuItem<int>(
                                value: m['id'] as int,
                                child: Text(
                                  '${m['display_name'] ?? m['username']}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (value) => setState(() => assigneeId = value),
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
                          : (value) => setState(() => serialMode = value),
                    ),
                    if (serialMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextFormField(
                          controller: serials,
                          minLines: 2,
                          maxLines: 5,
                          decoration: field('SN，每行一个', Icons.list_alt),
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
                  textStyle: const TextStyle(
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
                  textStyle: const TextStyle(
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
  bool busy = false, loaded = false;
  Object? error;
  String? binding;
  String get base => 'workspaces/${widget.workspaceId}/jobs/${job['id']}/';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      binding = CloudScope.of(context).accessScope;
      load();
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
    if (!account.retainsAccess(binding)) return;
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
      if (mounted && account.retainsAccess(binding)) {
        setState(() {
          job = latest;
          history = events;
        });
      }
    } on CollaborationApiException catch (failure) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() => error = failure);
      }
    } catch (failure) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() => error = failure);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> command(String action, {Map<String, dynamic>? issue}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CloudTaskCommandPage(
          job: job,
          workspaceId: widget.workspaceId,
          action: action,
          issue: issue,
        ),
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn ||
        account.activeWorkspace?['id'] != widget.workspaceId) {
      return cloudAccessRequired(context);
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
                        textStyle: const TextStyle(
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
                          textStyle: const TextStyle(
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
        _StatusTrack(status: status),
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
                                  textStyle: const TextStyle(
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
                    for (final photo in evidence.where(
                      (p) => p['issue_id'] == issue['id'],
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            alignment: Alignment.centerLeft,
                            textStyle: const TextStyle(
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
                            textStyle: const TextStyle(
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

class _StatusTrack extends StatelessWidget {
  final String status;
  const _StatusTrack({required this.status});
  @override
  Widget build(BuildContext context) {
    const steps = ['queued', 'printing', 'inspection', 'closed'];
    final exception = status == 'exception';
    final current = exception ? 2 : steps.indexOf(status).clamp(0, 3);
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0)
                SizedBox(
                  width: 20,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: Container(
                      height: 2,
                      color: i <= current ? blue : hairline,
                    ),
                  ),
                ),
              Column(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < current
                          ? green
                          : i == current
                          ? (exception ? red : blue)
                          : Colors.white,
                      border: Border.all(
                        color: i <= current
                            ? Colors.transparent
                            : const Color(0xFFD7E2F0),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: i < current
                        ? const Icon(Icons.check, size: 13, color: Colors.white)
                        : i == current
                        ? Icon(
                            exception
                                ? Icons.priority_high_rounded
                                : Icons.circle,
                            size: exception ? 14 : 8,
                            color: Colors.white,
                          )
                        : Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF9AA9BD),
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      context,
                      exception && i == 2
                          ? '异常处理中'
                          : taskStatusLabels[steps[i]] ?? steps[i],
                    ),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: i <= current ? ink : const Color(0xFF9AA9BD),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
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
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      final account = CloudScope.of(context);
      accessBinding = account.accessScope;
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
    if ((action == 'resolve' || (action == 'inspect' && verdict == 'fail')) &&
        note.text.trim().isEmpty) {
      edit(() => error = '请填写处理或异常说明');
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
      if (mounted) Navigator.pop(context);
    } on CollaborationApiException catch (failure) {
      if (mounted) {
        edit(() {
          error = failure.message;
          conflict = failure.details?['current'] as Map<String, dynamic>?;
        });
      }
    } catch (_) {
      if (mounted) edit(() => error = '网络连接失败，草稿已保留，请重试');
    } finally {
      if (mounted) edit(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn ||
        (draftStorageKey != null &&
            draftStorageKey !=
                account.draftKey('${widget.action}-${widget.job['id']}'))) {
      return cloudAccessRequired(context);
    }
    if (!account.retainsAccess(accessBinding) ||
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
    final job = widget.job;
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
        child,
      ],
    );

    return DetailScaffold(
      title: tr(context, title),
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
                            MaterialPageRoute<void>(
                              builder: (_) => const CloudSyncPage(),
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
                                    ? '${widget.job['quantity']}'
                                    : '0';
                                failed.text = verdict == 'fail'
                                    ? '${widget.job['quantity']}'
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
                      Padding(
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
                                  if (items[i]['allow_na'] == true) 'na': '不适用',
                                }.entries)
                                  ChoiceChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(tr(context, result.value)),
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
                                  initialValue:
                                      answerNotes['${items[i]['id']}'] ?? '',
                                  decoration: InputDecoration(
                                    labelText: tr(context, '问题说明'),
                                    isDense: true,
                                  ),
                                  onChanged: (value) {
                                    answerNotes['${items[i]['id']}'] = value;
                                    changedText();
                                  },
                                ),
                              ),
                          ],
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
            caption: serialResults.isEmpty ? null : tr(context, '已按 SN 自动统计'),
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
                          initialValue: serialResults[sn],
                          isDense: true,
                          decoration: InputDecoration(labelText: sn),
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
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    icon: const Icon(Icons.add_a_photo_outlined, size: 17),
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
                    TextField(
                      controller: closureReason,
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
              child: TextField(
                controller: note,
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
                  Text(
                    '${tr(context, '当前任务状态')}：${tr(context, taskStatusLabels[conflict!['status']] ?? '')}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(tr(context, '任务已被其他人更新，请选择如何处理这份草稿。'), style: hint),
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
                          if (!mounted) return;
                          edit(() {
                            savedVersion = conflict!['version'] as int;
                            final archived =
                                (conflict!['evidence'] as List? ?? [])
                                    .where((p) => p['inspection_id'] != null)
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
              textStyle: const TextStyle(
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
          tr(context, '提交后写入任务审计记录，可继续补充照片。'),
          textAlign: TextAlign.center,
          style: hint,
        ),
      ],
    );
  }
}

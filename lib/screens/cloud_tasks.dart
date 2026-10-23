import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cloud_account.dart';
import '../cloud_outbox.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../models.dart' show uid;
import '../ui.dart';
import '../time.dart' show zonedStamp;
import 'cloud_business.dart';

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
      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
      child: Text(tr(context, '返回工作台')),
    ),
  ],
);

class CloudTaskListPage extends StatefulWidget {
  final String? status;
  const CloudTaskListPage({super.key, this.status});
  @override
  State<CloudTaskListPage> createState() => _CloudTaskListPageState();
}

class _CloudTaskListPageState extends State<CloudTaskListPage> {
  final search = TextEditingController();
  String? status;
  @override
  void initState() {
    super.initState();
    status = widget.status;
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    final jobs = account.jobs
        .where(
          (j) =>
              (status == null || j['status'] == status) &&
              '${j['part_name']} ${j['printer']}'.toLowerCase().contains(
                search.text.trim().toLowerCase(),
              ),
        )
        .toList();
    return DetailScaffold(
      title: tr(context, '生产任务'),
      children: [
        TextField(
          controller: search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: tr(context, '搜索任务或设备'),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(tr(context, '全部')),
              selected: status == null,
              onSelected: (_) => setState(() => status = null),
            ),
            ...taskStatusLabels.entries.map(
              (e) => ChoiceChip(
                label: Text(tr(context, e.value)),
                selected: status == e.key,
                onSelected: (_) => setState(() => status = e.key),
              ),
            ),
          ],
        ),
        if (account.canEdit)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: FilledButton.icon(
              onPressed: () => openPage(context, const CloudCreateTaskPage()),
              icon: const Icon(Icons.add),
              label: Text(tr(context, '新建任务')),
            ),
          ),
        if (jobs.isEmpty)
          EmptyState(
            title: tr(context, '暂无生产任务'),
            subtitle: tr(context, '没有符合条件的任务。'),
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
  Widget build(BuildContext context) => GlassPanel(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${job['part_name']}'),
      subtitle: Text(
        '${job['printer']} · ${job['quantity']} ${tr(context, '件')}',
      ),
      trailing: Tag(
        tr(context, taskStatusLabels[job['status']] ?? '${job['status']}'),
        color: taskColor('${job['status']}'),
      ),
      onTap: () => openPage(
        context,
        CloudTaskPage(
          job: job,
          workspaceId: CloudScope.of(context).activeWorkspace!['id'] as int,
        ),
      ),
    ),
  );
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
  String? draftStorageKey;
  bool draftLoaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!draftLoaded) {
      draftLoaded = true;
      final account = CloudScope.of(context);
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
      if (mounted) {
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
      if (!mounted || data == null) return;
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
    if (workspace == null ||
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
  Widget build(BuildContext context) =>
      !CloudScope.of(context).signedIn ||
          (draftStorageKey != null &&
              draftStorageKey != CloudScope.of(context).draftKey('create'))
      ? cloudAccessRequired(context)
      : DetailScaffold(
          title: tr(context, '新建任务'),
          children: [
            Form(
              key: form,
              onChanged: saveDraft,
              child: Column(
                children: [
                  TextFormField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: tr(context, '零件名称')),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? tr(context, '请填写零件名称')
                        : null,
                  ),
                  TextFormField(
                    controller: printer,
                    enabled: !busy,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: tr(context, '打印设备')),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? tr(context, '请填写打印设备')
                        : null,
                  ),
                  TextFormField(
                    controller: quantity,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr(context, '工件数量')),
                    validator: (v) =>
                        (int.tryParse(v ?? '') ?? 0) < 1 ||
                            (int.tryParse(v ?? '') ?? 0) > 999
                        ? tr(context, '数量需要在1至999之间')
                        : null,
                  ),
                  TextFormField(
                    controller: batch,
                    enabled: !busy,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: tr(context, '批次号')),
                  ),
                  if (CloudScope.of(context).templates.isNotEmpty)
                    DropdownButtonFormField<int>(
                      initialValue:
                          templateId ??
                          CloudScope.of(context).templates.first['id'] as int,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr(context, '检查模板'),
                      ),
                      items: CloudScope.of(context).templates
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
                      decoration: InputDecoration(
                        labelText: tr(context, '负责人'),
                      ),
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
                  SwitchListTile(
                    title: Text(tr(context, '逐件SN追踪')),
                    value: serialMode,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => serialMode = value),
                  ),
                  if (serialMode)
                    TextFormField(
                      controller: serials,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: tr(context, 'SN，每行一个'),
                      ),
                    ),
                  TextFormField(
                    controller: note,
                    enabled: !busy,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: tr(context, '备注')),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.save_outlined),
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
            if (error != null)
              Text(
                trMessage(context, error!),
                style: const TextStyle(color: red),
              ),
            if (busy) const LinearProgressIndicator(),
            FilledButton(
              onPressed: busy || !CloudScope.of(context).canEdit
                  ? null
                  : submit,
              child: Text(tr(context, '创建任务')),
            ),
          ],
        );
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
  String? error;
  String get base => 'workspaces/${widget.workspaceId}/jobs/${job['id']}/';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      load();
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
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
      if (mounted) {
        setState(() {
          job = latest;
          history = events;
        });
      }
    } on CollaborationApiException catch (failure) {
      if (mounted) setState(() => error = failure.message);
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
    final canEdit =
        account.canEdit && account.activeWorkspace?['id'] == widget.workspaceId;
    final status = '${job['status']}',
        checks = (job['inspections'] as List? ?? []),
        issues = (job['exceptions'] as List? ?? []);
    return DetailScaffold(
      title: '${job['part_name']}',
      actions: [
        IconButton(
          icon: const Icon(Icons.copy),
          tooltip: tr(context, '复制追溯号'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: '${job['id']}'));
            if (context.mounted) toast(context, '已复制');
          },
        ),
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: tr(context, '刷新'),
        ),
      ],
      children: [
        Row(
          children: [
            Expanded(
              child: SelectableText(
                '${job['id']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            Tag(
              tr(context, taskStatusLabels[status] ?? status),
              color: taskColor(status),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: taskStatusLabels.entries
              .map(
                (e) => Chip(
                  avatar: Icon(
                    e.key == status
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: taskColor(e.key),
                  ),
                  label: Text(tr(context, e.value)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final e in {0: '概览', 1: '质检', 2: '异常', 3: '历史'}.entries)
              ButtonSegment(value: e.key, label: Text(tr(context, e.value))),
          ],
          selected: {tab},
          onSelectionChanged: (selected) =>
              setState(() => tab = selected.first),
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              trMessage(context, error!),
              style: const TextStyle(color: red),
            ),
          ),
        if (tab == 0) ...[
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job['printer']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text('${tr(context, '工件数量')}：${job['quantity']}'),
                Text('${tr(context, '批次号')}：${job['batch_code'] ?? ''}'),
                OutlinedButton.icon(
                  icon: const Icon(Icons.description_outlined),
                  label: Text(tr(context, '质量报告')),
                  onPressed: () =>
                      openPage(context, CloudReportPage(jobId: '${job['id']}')),
                ),
                Text('${tr(context, '负责人')}：${job['assignee'] ?? ''}'),
                const SizedBox(height: 8),
                Text(
                  '${tr(context, '创建时间')}：${cloudTimestamp(job['created_at'])}',
                ),
                if ('${job['note'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('${job['note']}'),
                  ),
              ],
            ),
          ),
          if (canEdit && !busy && error == null && status != 'closed')
            FilledButton(
              onPressed: () {
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
              },
              child: Text(
                tr(context, switch (status) {
                  'queued' => '开始打印',
                  'printing' => '送检',
                  'inspection' => '登记检验',
                  _ => '处理异常',
                }),
              ),
            ),
        ],
        if (tab == 1) ...[
          if (canEdit && !busy && error == null && status == 'inspection')
            FilledButton(
              onPressed: () => command('inspect'),
              child: Text(tr(context, '登记检验')),
            ),
          if (checks.isEmpty)
            EmptyState(
              title: tr(context, '暂无检验记录'),
              subtitle: tr(context, '完成检验后可在这里查看记录。'),
            ),
          for (var i = 0; i < checks.length; i++)
            GlassPanel(
              child: ListTile(
                onTap: () => openPage(
                  context,
                  CloudInspectionDetailPage(
                    record: Map<String, dynamic>.from(checks[i] as Map),
                  ),
                ),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  checks[i]['verdict'] == 'pass'
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  color: checks[i]['verdict'] == 'pass' ? green : red,
                ),
                title: Text(
                  '${tr(context, '检验轮次')} ${checks[i]['round_no'] ?? checks.length - i} · ${tr(context, checks[i]['verdict'] == 'pass' ? '合格' : '异常')}',
                ),
                subtitle: Text(
                  '${cloudTimestamp(checks[i]['created_at'])}\n${checks[i]['note']}',
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
            (issue) => GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tag(
                    tr(context, issue['status'] == 'open' ? '待处理' : '已处理'),
                    color: issue['status'] == 'open' ? red : green,
                  ),
                  const SizedBox(height: 12),
                  Text('${issue['note']}'),
                  Text(
                    '${tr(context, '负责人')}：${issue['assignee'] ?? ''} · ${tr(context, switch (issue['severity']) {
                      'critical' => '严重',
                      'minor' => '轻微',
                      _ => '主要',
                    })}',
                  ),
                  if (canEdit && issue['status'] == 'open')
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final stage in {
                          'before': '处置前照片',
                          'after': '处置后照片',
                        }.entries)
                          TextButton.icon(
                            icon: const Icon(Icons.add_a_photo),
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
                                if (mounted) setState(() => error = '$failure');
                              }
                            },
                          ),
                      ],
                    ),
                  for (final photo in (job['evidence'] as List? ?? []).where(
                    (p) => p['issue_id'] == issue['id'],
                  ))
                    TextButton.icon(
                      icon: const Icon(Icons.photo),
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
                  if ('${issue['resolution']}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('${issue['resolution']}'),
                    ),
                  if (canEdit &&
                      !busy &&
                      error == null &&
                      issue['status'] == 'open')
                    TextButton(
                      onPressed: () => command(
                        'resolve',
                        issue: Map<String, dynamic>.from(issue as Map),
                      ),
                      child: Text(tr(context, '处理异常')),
                    ),
                ],
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
          ...history.map(
            (event) => GlassPanel(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Text(
                    '${event['actor'] ?? ''}'.isEmpty
                        ? 'L'
                        : '${event['actor']}'.characters.first,
                  ),
                ),
                title: Text(
                  tr(context, switch (event['action']) {
                    'job.created' => '创建任务',
                    'job.status' => '任务状态更新',
                    'inspection.pass' => '检验合格',
                    'inspection.fail' => '检验异常',
                    'exception.created' => '创建异常',
                    'exception.resolved' => '完成异常处置',
                    _ => '任务操作',
                  }),
                ),
                subtitle: Text(
                  '${event['actor']} · ${cloudTimestamp(event['created_at'])}\n${(event['details'] as Map?)?['resolution'] ?? ''}',
                ),
              ),
            ),
          ),
        ],
      ],
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
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      final account = CloudScope.of(context);
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
      if (!mounted) return;
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
    return DetailScaffold(
      title: tr(context, title),
      children: [
        if (draftStorageKey != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.sync),
            label: Text(tr(context, '同步与草稿')),
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
          ),
        if (restoreFailed)
          TextButton(
            onPressed: restoreDraft,
            child: Text(tr(context, '重试恢复草稿')),
          ),
        if (draftError != null)
          Text(
            trMessage(context, draftError!),
            style: const TextStyle(color: red),
          ),
        Text(
          '${widget.job['part_name']}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (widget.issue != null)
          GlassPanel(child: Text('${widget.issue!['note']}')),
        if (widget.action == 'inspect') ...[
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'pass',
                icon: const Icon(Icons.check_circle_outline),
                label: Text(tr(context, '合格')),
              ),
              ButtonSegment(
                value: 'fail',
                icon: const Icon(Icons.warning_amber),
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
          const SizedBox(height: 16),
          for (final item in template?['items'] as List? ?? [])
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item['label']}'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final result in {
                        'pass': '合格',
                        'fail': '异常',
                        if (item['allow_na'] == true) 'na': '不适用',
                      }.entries)
                        ChoiceChip(
                          label: Text(tr(context, result.value)),
                          selected: answers['${item['id']}'] == result.key,
                          onSelected: busy
                              ? null
                              : (_) => edit(() {
                                  answers['${item['id']}'] = result.key;
                                  if (result.key == 'fail') verdict = 'fail';
                                }),
                        ),
                    ],
                  ),
                  if (answers['${item['id']}'] == 'fail')
                    TextFormField(
                      initialValue: answerNotes['${item['id']}'] ?? '',
                      decoration: InputDecoration(
                        labelText: tr(context, '问题说明'),
                      ),
                      onChanged: (value) {
                        answerNotes['${item['id']}'] = value;
                        changedText();
                      },
                    ),
                ],
              ),
            ),
          for (final field in <TextEditingController, String>{
            passed: '合格数量',
            failed: '异常数量',
            scrapped: '报废数量',
          }.entries)
            TextField(
              controller: field.key,
              enabled: !busy && serialResults.isEmpty,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr(context, field.value)),
            ),
          for (final sn in serialResults.keys)
            DropdownButtonFormField<String>(
              initialValue: serialResults[sn],
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
                          int.parse(failed.text) + int.parse(scrapped.text) > 0
                          ? 'fail'
                          : 'pass';
                    }),
            ),
          if (verdict == 'fail') ...[
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: InputDecoration(labelText: tr(context, '异常类别')),
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
            DropdownButtonFormField<String>(
              initialValue: severity,
              decoration: InputDecoration(labelText: tr(context, '严重程度')),
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
          OutlinedButton.icon(
            icon: const Icon(Icons.add_a_photo),
            label: Text('${tr(context, '添加检验照片')} (${evidence.length})'),
            onPressed: busy
                ? null
                : () async {
                    edit(() => busy = true);
                    try {
                      final id = await cloudPickPhoto(context, widget.job);
                      if (id != null && mounted) {
                        edit(() => evidence.add(id));
                      }
                    } catch (failure) {
                      if (mounted) edit(() => error = '$failure');
                    } finally {
                      if (mounted) edit(() => busy = false);
                    }
                  },
          ),
        ],
        if (widget.action == 'resolve' &&
            account.activeWorkspace?['role'] == 'owner') ...[
          DropdownButtonFormField<String>(
            initialValue: nextStatus,
            decoration: InputDecoration(labelText: tr(context, '处置后操作')),
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
            DropdownButtonFormField<String>(
              initialValue: disposition,
              decoration: InputDecoration(labelText: tr(context, '关闭处置')),
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
            TextField(
              controller: closureReason,
              enabled: !busy && conflict == null,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(labelText: tr(context, '授权依据')),
            ),
          ],
        ],
        if (widget.action == 'inspect' || widget.action == 'resolve')
          TextField(
            controller: note,
            enabled: !busy && conflict == null,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: tr(
                context,
                widget.action == 'resolve' ? '处理结果' : '检验备注',
              ),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              trMessage(context, error!),
              style: const TextStyle(color: red),
            ),
          ),
        if (conflict != null) ...[
          GlassPanel(
            child: Text(
              '${tr(context, '当前任务状态')}：${tr(context, taskStatusLabels[conflict!['status']] ?? '')}',
            ),
          ),
          if ((widget.action == 'inspect' &&
                  conflict!['status'] == 'inspection') ||
              (widget.action == 'resolve' &&
                  conflict!['status'] == 'exception' &&
                  (conflict!['exceptions'] as List? ?? []).any(
                    (i) =>
                        i['id'] == widget.issue?['id'] && i['status'] == 'open',
                  )))
            OutlinedButton(
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
                  final archived = (conflict!['evidence'] as List? ?? [])
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
          if (draftStorageKey != null)
            OutlinedButton(
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
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '返回并刷新任务')),
          ),
        ],
        if (busy) const LinearProgressIndicator(),
        FilledButton(
          onPressed: busy || conflict != null || !CloudScope.of(context).canEdit
              ? null
              : submit,
          child: Text(tr(context, '确认提交')),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../models.dart' show uid;
import '../ui.dart';
import '../time.dart' show zonedStamp;

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
      note = TextEditingController();
  final key = 'cloud-${uid()}';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final controller in [name, printer, quantity, note]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    final account = CloudScope.of(context),
        workspace = CloudScope.of(context).activeWorkspace;
    if (workspace == null) return;
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
        },
      );
      await account.reload();
      if (mounted) Navigator.pop(context);
    } on CollaborationApiException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => !CloudScope.of(context).signedIn
      ? cloudAccessRequired(context)
      : DetailScaffold(
          title: tr(context, '新建任务'),
          children: [
            Form(
              key: form,
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
    if (!account.signedIn) return cloudAccessRequired(context);
    final canEdit =
        account.canEdit && account.activeWorkspace?['id'] == widget.workspaceId;
    final status = '${job['status']}',
        checks = (job['inspections'] as List? ?? []),
        issues = (job['exceptions'] as List? ?? []);
    return DetailScaffold(
      title: '${job['part_name']}',
      actions: [
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
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  checks[i]['verdict'] == 'pass'
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  color: checks[i]['verdict'] == 'pass' ? green : red,
                ),
                title: Text(
                  '${tr(context, '检验轮次')} ${checks.length - i} · ${tr(context, checks[i]['verdict'] == 'pass' ? '合格' : '异常')}',
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
                leading: const Icon(Icons.history),
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
  final note = TextEditingController();
  final key = 'cloud-${uid()}';
  String verdict = 'pass';
  bool busy = false;
  String? error;
  Map<String, dynamic>? conflict;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final account = CloudScope.of(context), action = widget.action;
    if ((action == 'resolve' || (action == 'inspect' && verdict == 'fail')) &&
        note.text.trim().isEmpty) {
      setState(() => error = '请填写处理或异常说明');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final base = 'workspaces/${widget.workspaceId}';
      final path = action == 'resolve'
          ? '$base/exceptions/${widget.issue!['id']}/resolve/'
          : '$base/jobs/${widget.job['id']}/${action == 'inspect' ? 'inspection/' : ''}';
      await account.request(
        action == 'inspect' || action == 'resolve' ? 'POST' : 'PATCH',
        path,
        idempotencyKey: key,
        body: {
          'version': widget.job['version'],
          if (action == 'inspect') ...{
            'verdict': verdict,
            'note': note.text.trim(),
          },
          if (action == 'resolve') ...{
            'resolution': note.text.trim(),
            'next_status': 'inspection',
          },
          if (action != 'resolve' && action != 'inspect') 'status': action,
        },
      );
      await account.reload();
      if (mounted) Navigator.pop(context);
    } on CollaborationApiException catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.message;
          conflict = failure.details?['current'] as Map<String, dynamic>?;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!CloudScope.of(context).signedIn) return cloudAccessRequired(context);
    final title = switch (widget.action) {
      'inspect' => '登记检验',
      'resolve' => '处理异常',
      'printing' => '开始打印',
      _ => '送检',
    };
    return DetailScaffold(
      title: tr(context, title),
      children: [
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
                : (value) => setState(() => verdict = value.first),
          ),
          const SizedBox(height: 16),
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

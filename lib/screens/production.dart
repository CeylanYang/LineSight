import 'package:flutter/material.dart';
import '../l10n.dart';
import '../models.dart';
import '../store.dart';
import '../ui.dart';

class ProductionPage extends StatelessWidget {
  const ProductionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final jobs = [...store.data.jobs]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final active = jobs.where((job) => job.status != 'closed').length;
    return Scaffold(
      body: Backdrop(
        child: PageBody(
          children: [
            PageHeading(
              eyebrow: tr(context, '生产管理'),
              title: tr(context, '生产任务'),
              subtitle: tr(context, '把打印任务、质检决定和异常处理放在同一条流程里。'),
              trailing: IconButton.filledTonal(
                tooltip: tr(context, '新建任务'),
                onPressed: () => createJob(context),
                icon: const Icon(Icons.add),
              ),
            ),
            GlassPanel(
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, color: blue, size: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tr(context, '{0} 项任务处理中', [active]),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Tag(tr(context, '生产与质检'), color: green),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (jobs.isEmpty)
              EmptyState(
                title: tr(context, '暂无生产任务'),
                subtitle: tr(context, '新建一个打印任务，跟进打印、质检和异常闭环。'),
              ),
            ...jobs.map(
              (job) => Padding(
                key: ValueKey('production-job/${job.id}'),
                padding: const EdgeInsets.only(bottom: 12),
                child: _JobCard(job: job),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> createJob(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreateProductionJobDialog(store: AppScope.of(context)),
  );
}

class _CreateProductionJobDialog extends StatefulWidget {
  final AppStore store;
  const _CreateProductionJobDialog({required this.store});
  @override
  State<_CreateProductionJobDialog> createState() =>
      _CreateProductionJobDialogState();
}

class _CreateProductionJobDialogState
    extends State<_CreateProductionJobDialog> {
  final name = TextEditingController();
  final qty = TextEditingController(text: '1');
  final note = TextEditingController();
  final form = GlobalKey<FormState>();
  late final int session = widget.store.session;
  late final String? userId = widget.store.user?.id;
  String printer = 'Bambu Lab A1';
  String? pendingId, error;
  bool busy = false;
  bool get valid =>
      mounted &&
      identical(AppScope.of(context), widget.store) &&
      widget.store.session == session &&
      widget.store.user?.id == userId &&
      userId != null;

  @override
  void dispose() {
    name.dispose();
    qty.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !valid || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    pendingId ??= uid();
    final job = ProductionJob(
      id: pendingId!,
      partName: name.text.trim(),
      printer: printer,
      quantity: qty.text.trim(),
      status: 'queued',
      note: note.text.trim(),
      createdAt: DateTime.now(),
    );
    try {
      await widget.store.createProductionJob(job);
      if (mounted && valid) Navigator.pop(context);
    } catch (_) {
      if (!mounted || !valid) return;
      // The local transaction may have committed before a later list refresh
      // failed. Its existing ID proves creation; retry must not create it again.
      if (widget.store.data.jobs.any((row) => row.id == job.id)) {
        Navigator.pop(context);
      } else {
        setState(() => error = '保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = valid;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(tr(context, '新建生产任务')),
        content: !current
            ? Text(tr(context, '账户或团队已切换，请重新打开页面'))
            : Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      enabled: !busy,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: tr(context, '零件名称'),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? tr(context, '请输入零件名称')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: printer,
                      decoration: InputDecoration(
                        labelText: tr(context, '打印机配置'),
                      ),
                      items: const ['Bambu Lab A1', 'Bambu Lab P2S']
                          .map(
                            (x) => DropdownMenuItem(
                              value: x,
                              child: Text(
                                x,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (value) => setState(() => printer = value!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: qty,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr(context, '数量')),
                      validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1
                          ? tr(context, '数量必须大于 0')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: note,
                      enabled: !busy,
                      maxLength: 160,
                      decoration: InputDecoration(
                        labelText: tr(context, '交接备注'),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          tr(context, error!),
                          style: const TextStyle(color: red),
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(tr(context, '取消')),
          ),
          FilledButton(
            onPressed: busy || !current ? null : submit,
            child: Text(tr(context, busy ? '正在保存，请稍后' : '创建任务')),
          ),
        ],
      ),
    );
  }
}

class _JobCard extends StatefulWidget {
  final ProductionJob job;
  const _JobCard({required this.job});
  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard> {
  ProductionJob get job => widget.job;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final status = switch (job.status) {
      'queued' => tr(context, '待打印'),
      'printing' => tr(context, '打印中'),
      'inspection' => tr(context, '待质检'),
      'exception' => tr(context, '异常处理中'),
      _ => tr(context, '已关闭'),
    };
    final color = job.status == 'exception'
        ? red
        : job.status == 'closed'
        ? green
        : blue;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.partName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Tag(status, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${job.printer} · ${tr(context, '{0} 件', [job.quantity])} · ${stamp(job.createdAt)}',
          ),
          if (job.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(job.note),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: _actions(context, store)),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, AppStore store) {
    final actions = <Widget>[];
    void add(String next, String label, IconData icon) => actions.add(
      OutlinedButton.icon(
        onPressed: busy
            ? null
            : () async {
                final session = store.session;
                final actor = store.user?.id;
                setState(() => busy = true);
                try {
                  await store.updateProductionJob(job.id, status: next);
                } catch (_) {
                  if (mounted &&
                      context.mounted &&
                      store.session == session &&
                      store.user?.id == actor) {
                    toast(context, '保存失败，请重试');
                  }
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        icon: Icon(icon, size: 18),
        label: Text(tr(context, busy ? '正在保存，请稍后' : label)),
      ),
    );
    switch (job.status) {
      case 'queued':
        add('printing', '开始打印', Icons.play_arrow);
        break;
      case 'printing':
        add('inspection', '打印完成，送检', Icons.fact_check_outlined);
        break;
      case 'inspection':
        add('closed', '质检通过并关闭', Icons.check_circle_outline);
        add('exception', '发现异常', Icons.report_gmailerrorred_outlined);
        break;
      case 'exception':
        add('inspection', '重新送检', Icons.replay);
        add('closed', '接受处理并关闭', Icons.task_alt);
        break;
    }
    return actions;
  }
}

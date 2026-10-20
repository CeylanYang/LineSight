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
              eyebrow: 'PRODUCTION / QUALITY HANDOFF',
              title: tr(context, '生产任务'),
              subtitle: tr(context, '把打印任务、质检决定和异常处理放在同一条流程里。'),
              trailing: IconButton.filledTonal(
                tooltip: tr(context, '新建任务'),
                onPressed: () => _createJob(context),
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
                      tr(context, '本机工作区 · {0} 项未关闭', [active]),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Tag('LOCAL FIRST', color: green),
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
                padding: const EdgeInsets.only(bottom: 12),
                child: _JobCard(job: job),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createJob(BuildContext context) async {
    final name = TextEditingController();
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    var printer = 'Bambu Lab A1';
    final form = GlobalKey<FormState>();
    final result = await showDialog<ProductionJob>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr(context, '新建生产任务')),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: InputDecoration(labelText: tr(context, '零件名称')),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? tr(context, '请输入零件名称')
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: printer,
                  decoration: InputDecoration(labelText: tr(context, '打印机配置')),
                  items: const ['Bambu Lab A1', 'Bambu Lab P2S']
                      .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                      .toList(),
                  onChanged: (value) => setState(() => printer = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr(context, '数量')),
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1
                      ? tr(context, '数量必须大于 0')
                      : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLength: 160,
                  decoration: InputDecoration(labelText: tr(context, '交接备注')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr(context, '取消')),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(
                  dialogContext,
                  ProductionJob(
                    id: uid(),
                    partName: name.text.trim(),
                    printer: printer,
                    quantity: qty.text.trim(),
                    status: 'queued',
                    note: note.text.trim(),
                    createdAt: DateTime.now(),
                  ),
                );
              },
              child: Text(tr(context, '创建任务')),
            ),
          ],
        ),
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await AppScope.of(context).createProductionJob(result);
    } catch (error) {
      if (context.mounted) {
        _message(context, trMessage(context, error.toString()));
      }
    }
  }
}

class _JobCard extends StatelessWidget {
  final ProductionJob job;
  const _JobCard({required this.job});
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
        onPressed: () async {
          try {
            await store.updateProductionJob(job.id, status: next);
          } catch (error) {
            if (context.mounted) {
              _message(context, trMessage(context, error.toString()));
            }
          }
        },
        icon: Icon(icon, size: 18),
        label: Text(tr(context, label)),
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

void _message(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

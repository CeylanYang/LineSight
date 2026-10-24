import 'package:flutter/material.dart';
import 'l10n.dart';
import 'ui.dart';

/// The preview owns no account or API client. Its answers never become a record.
class CloudTemplatePreview extends StatefulWidget {
  final List<dynamic> items;
  const CloudTemplatePreview({super.key, required this.items});
  @override
  State<CloudTemplatePreview> createState() => _CloudTemplatePreviewState();
}

class _CloudTemplatePreviewState extends State<CloudTemplatePreview> {
  final answers = <String, String>{};
  final notes = <String, String>{};
  int selected = 0, revision = 0;

  Color colorFor(String? result) => switch (result) {
    'pass' => green,
    'fail' => red,
    'na' => muted,
    _ => blue,
  };

  String labelFor(String? result) => switch (result) {
    'pass' => '合格',
    'fail' => '异常',
    'na' => '不适用',
    _ => '待检查',
  };

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        AppScope.of(context).preferences['reduceMotion'] == true;
    final duration = Duration(milliseconds: reduceMotion ? 0 : 180);
    final complete = answers.length == items.length;
    final failures = answers.values.where((value) => value == 'fail').length;
    final passes = answers.values.where((value) => value == 'pass').length;
    final statusColor = failures > 0
        ? red
        : complete
        ? green
        : blue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, '交互预览'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, '重置预览'),
                    onPressed: answers.isEmpty
                        ? null
                        : () => setState(() {
                            answers.clear();
                            notes.clear();
                            selected = 0;
                            revision++;
                          }),
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: answers.length / items.length),
                      duration: duration,
                      builder: (context, value, _) => Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: value,
                            strokeWidth: 5,
                            backgroundColor: blue.withValues(alpha: .08),
                            color: statusColor,
                          ),
                          Center(
                            child: Text(
                              '${answers.length}/${items.length}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, complete ? '预览完成' : '检查进度'),
                          key: const ValueKey('template-preview-status'),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          tr(context, '已检查 {0} / {1} 项', [
                            answers.length,
                            items.length,
                          ]),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PreviewCount(
                    label: tr(context, '合格'),
                    value: passes,
                    color: green,
                  ),
                  _PreviewCount(
                    label: tr(context, '异常'),
                    value: failures,
                    color: red,
                  ),
                  _PreviewCount(
                    label: tr(context, '待检查'),
                    value: items.length - answers.length,
                    color: blue,
                  ),
                  if (answers.containsValue('na'))
                    _PreviewCount(
                      label: tr(context, '不适用'),
                      value: answers.values
                          .where((value) => value == 'na')
                          .length,
                      color: muted,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < items.length; i++) ...[
          Builder(
            builder: (context) {
              final item = items[i] as Map;
              final id = '${item['id']}';
              final result = answers[id];
              final active = selected == i;
              final color = colorFor(result);
              return AnimatedContainer(
                duration: duration,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: active ? color.withValues(alpha: .045) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: active
                        ? color.withValues(alpha: .45)
                        : blue.withValues(alpha: .10),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        key: ValueKey('preview-item-$id'),
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => setState(() => selected = i),
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: result == null
                                    ? Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      )
                                    : Icon(
                                        result == 'pass'
                                            ? Icons.check_rounded
                                            : result == 'fail'
                                            ? Icons.priority_high_rounded
                                            : Icons.remove_rounded,
                                        color: color,
                                        size: 20,
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${item['label']}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tr(context, labelFor(result)),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: result == null ? muted : color,
                                ),
                              ),
                              Icon(
                                active ? Icons.expand_less : Icons.expand_more,
                                color: muted,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (active)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  for (final entry in {
                                    'pass': '合格',
                                    'fail': '异常',
                                    if (item['allow_na'] == true) 'na': '不适用',
                                  }.entries)
                                    ChoiceChip(
                                      showCheckmark: false,
                                      key: ValueKey('preview-$id-${entry.key}'),
                                      label: Text(tr(context, entry.value)),
                                      avatar: Icon(
                                        entry.key == 'pass'
                                            ? Icons.check_circle_outline
                                            : entry.key == 'fail'
                                            ? Icons.error_outline
                                            : Icons.remove_circle_outline,
                                        color: colorFor(entry.key),
                                        size: 17,
                                      ),
                                      selected: result == entry.key,
                                      selectedColor: colorFor(
                                        entry.key,
                                      ).withValues(alpha: .12),
                                      onSelected: (_) => setState(
                                        () => answers[id] = entry.key,
                                      ),
                                    ),
                                ],
                              ),
                              if (result == 'fail') ...[
                                const SizedBox(height: 9),
                                TextFormField(
                                  key: ValueKey('preview-note-$id-$revision'),
                                  initialValue: notes[id] ?? '',
                                  decoration: InputDecoration(
                                    labelText: tr(context, '问题说明'),
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  maxLength: 500,
                                  minLines: 1,
                                  maxLines: 3,
                                  onChanged: (value) => notes[id] = value,
                                ),
                              ],
                              if (items.length > 1)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => setState(
                                      () => selected = (i + 1) % items.length,
                                    ),
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      tr(
                                        context,
                                        i == items.length - 1 ? '返回首项' : '下一项',
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _PreviewCount extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _PreviewCount({
    required this.label,
    required this.value,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      '$label $value',
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

class CloudTemplateCard extends StatelessWidget {
  final Map<String, dynamic> template;
  final VoidCallback onPreview;
  final VoidCallback? onUse;
  const CloudTemplateCard({
    super.key,
    required this.template,
    required this.onPreview,
    this.onUse,
  });
  @override
  Widget build(BuildContext context) {
    final items = template['items'] as List;
    final builtIn = template['built_in'] == true;
    final color = builtIn ? blue : green;
    return GlassPanel(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPreview,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        builtIn
                            ? Icons.fact_check_outlined
                            : Icons.groups_outlined,
                        color: color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${template['name']}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${tr(context, builtIn ? '内置模板' : '团队模板')} · v${template['version']} · ${items.length} ${tr(context, '检查项')}',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: muted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length && i < 2; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Icon(
                    Icons.check_box_outline_blank_rounded,
                    color: color.withValues(alpha: .6),
                    size: 14,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${items[i]['label']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ink, fontSize: 12),
                    ),
                  ),
                  if (i == 1 && items.length > 2)
                    Text(
                      '+${items.length - 2}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 290 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19;
              final preview = OutlinedButton.icon(
                onPressed: onPreview,
                icon: const Icon(Icons.touch_app_outlined, size: 18),
                label: Text(tr(context, '交互预览'), textAlign: TextAlign.center),
              );
              final use = FilledButton.icon(
                onPressed: onUse,
                icon: const Icon(Icons.add_task_rounded, size: 18),
                label: Text(tr(context, '用于任务'), textAlign: TextAlign.center),
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    preview,
                    if (onUse != null) ...[const SizedBox(height: 7), use],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: preview),
                  if (onUse != null) ...[
                    const SizedBox(width: 9),
                    Expanded(child: use),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'cloud_account.dart';
import 'l10n.dart';

const cloudStatuses = {
  'queued': '待打印',
  'printing': '打印中',
  'inspection': '待质检',
  'exception': '异常处理中',
  'closed': '已关闭',
};
const cloudCategories = {
  'dimension': '尺寸偏差',
  'surface': '表面缺陷',
  'crack': '裂纹',
  'deformation': '变形',
  'assembly': '装配问题',
  'other': '其他',
};

String cloudQuery(Map<String, String> filters) =>
    filters.isEmpty ? '' : '?${Uri(queryParameters: filters).query}';
String cloudScopeLabel(BuildContext context, Map<String, String> filters) {
  if (filters.isEmpty) return tr(context, '全部任务');
  const labels = {
    'q': '搜索',
    'status': '状态',
    'assignee': '负责人',
    'inspector': '检验人',
    'category': '异常类别',
    'verdict': '检验结论',
    'from': '任务起始日期',
    'to': '任务结束日期',
    'mine': '我的任务',
    'inspected_from': '检验起始日期',
    'inspected_to': '检验结束日期',
    'first_day': '首次检验日期（UTC）',
  };
  return filters.entries
      .map((entry) {
        var value = entry.value;
        if (entry.key == 'status') {
          value = tr(context, cloudStatuses[value] ?? value);
        }
        if (entry.key == 'category') {
          value = tr(context, cloudCategories[value] ?? value);
        }
        if (entry.key == 'verdict') {
          value = tr(context, value == 'pass' ? '合格' : '异常');
        }
        if (value == 'unassigned') value = tr(context, '未指派');
        if (entry.key == 'from' ||
            entry.key == 'to' ||
            entry.key == 'inspected_from' ||
            entry.key == 'inspected_to') {
          var date = DateTime.tryParse(value)?.toLocal();
          if (date != null) {
            if (entry.key == 'to' || entry.key == 'inspected_to') {
              date = date.subtract(const Duration(seconds: 1));
            }
            value =
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          }
        }
        return '${tr(context, labels[entry.key] ?? entry.key)}: $value';
      })
      .join(' · ');
}

Future<Map<String, String>?> cloudFilterDialog(
  BuildContext context,
  Map<String, String> initial, {
  bool records = false,
}) async {
  final account = CloudScope.of(context);
  final workspace = account.activeWorkspace?['id'];
  List<Map<String, dynamic>> members = [];
  try {
    members =
        (await account.request('GET', 'workspaces/$workspace/members/') as List)
            .cast<Map<String, dynamic>>();
  } catch (_) {
    // Keep all non-person filters usable if the member list cannot be loaded.
  }
  if (!context.mounted || workspace != account.activeWorkspace?['id']) {
    return null;
  }
  final values = Map<String, String>.from(initial);
  final search = TextEditingController(text: values['q']);
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) {
        Widget choice(String key, String label, Map<String, String> options) =>
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DropdownButtonFormField<String>(
                key: ValueKey('$key-${values[key]}'),
                isExpanded: true,
                initialValue: options.containsKey(values[key])
                    ? values[key]
                    : '',
                decoration: InputDecoration(labelText: tr(context, label)),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr(context, '全部'))),
                  ...options.entries.map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        tr(context, e.value),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => update(() {
                  if (value == null || value.isEmpty) {
                    values.remove(key);
                  } else {
                    values[key] = value;
                  }
                }),
              ),
            );
        final people = {
          for (final member in members)
            '${member['id']}':
                '${member['display_name'] ?? member['username']}',
        };
        return AlertDialog(
          title: Text(tr(context, '筛选范围')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: search,
                    decoration: InputDecoration(
                      labelText: tr(context, '任务号、批次或名称'),
                    ),
                  ),
                  choice('status', '状态', cloudStatuses),
                  choice('assignee', '负责人', {'unassigned': '未指派', ...people}),
                  if (records) choice('inspector', '检验人', people),
                  if (records)
                    choice('verdict', '检验结论', {'pass': '合格', 'fail': '异常'}),
                  choice('category', '异常类别', cloudCategories),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(tr(context, '任务日期')),
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange:
                            values['from'] == null || values['to'] == null
                            ? null
                            : DateTimeRange(
                                start: DateTime.parse(
                                  values['from']!,
                                ).toLocal(),
                                end: DateTime.parse(values['to']!)
                                    .toLocal()
                                    .subtract(const Duration(seconds: 1)),
                              ),
                      );
                      if (range != null) {
                        update(() {
                          values['from'] = DateTime(
                            range.start.year,
                            range.start.month,
                            range.start.day,
                          ).toUtc().toIso8601String();
                          values['to'] = DateTime(
                            range.end.year,
                            range.end.month,
                            range.end.day + 1,
                          ).toUtc().toIso8601String();
                        });
                      }
                    },
                  ),
                  if (records)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(tr(context, '检验日期')),
                      onPressed: () async {
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDateRange:
                              values['inspected_from'] == null ||
                                  values['inspected_to'] == null
                              ? null
                              : DateTimeRange(
                                  start: DateTime.parse(
                                    values['inspected_from']!,
                                  ).toLocal(),
                                  end: DateTime.parse(values['inspected_to']!)
                                      .toLocal()
                                      .subtract(const Duration(seconds: 1)),
                                ),
                        );
                        if (range != null) {
                          update(() {
                            values['inspected_from'] = DateTime(
                              range.start.year,
                              range.start.month,
                              range.start.day,
                            ).toUtc().toIso8601String();
                            values['inspected_to'] = DateTime(
                              range.end.year,
                              range.end.month,
                              range.end.day + 1,
                            ).toUtc().toIso8601String();
                          });
                        }
                      },
                    ),
                  Text(cloudScopeLabel(context, values)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => update(() {
                values.clear();
                search.clear();
              }),
              child: Text(tr(context, '清空筛选')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, '取消')),
            ),
            FilledButton(
              onPressed: () {
                if (search.text.trim().isEmpty) {
                  values.remove('q');
                } else {
                  values['q'] = search.text.trim();
                }
                Navigator.pop(context, values);
              },
              child: Text(tr(context, '应用筛选')),
            ),
          ],
        );
      },
    ),
  );
  search.dispose();
  return result;
}

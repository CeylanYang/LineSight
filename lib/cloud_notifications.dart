import 'package:flutter/material.dart';
import 'cloud_account.dart';
import 'cloud_trace.dart';
import 'ui.dart';
import 'l10n.dart';

/// Notifications resolve from their server ID, independent of dashboard caches.
void openCloudNotification(BuildContext context, Map<String, dynamic> notice) {
  final account = CloudScope.of(context),
      scope = CloudScope.of(context).accessScope;
  if (!account.retainsAccess(scope)) return;
  if (notice['bulletin'] == true) {
    openPage(context, CloudBulletinPage(notice: notice, scope: scope!));
    return;
  }
  openPage(
    context,
    CloudTracePage(
      link: TaskTrace(
        account.activeWorkspace!['id'] as int,
        '${notice['task_id']}',
      ).link,
      requiredAccessScope: scope,
    ),
  );
}

class CloudBulletinPage extends StatefulWidget {
  final Map<String, dynamic> notice;
  final String scope;
  const CloudBulletinPage({
    super.key,
    required this.notice,
    required this.scope,
  });
  @override
  State<CloudBulletinPage> createState() => _CloudBulletinPageState();
}

class _CloudBulletinPageState extends State<CloudBulletinPage> {
  bool marking = false, confirmedRead = false, fetchingTemplate = false;
  Map<String, dynamic> get notice => widget.notice;
  String get scope => widget.scope;
  Future<void> viewChecklist() async {
    final account = CloudScope.of(context);
    if (fetchingTemplate || !account.retainsAccess(scope)) return;
    setState(() => fetchingTemplate = true);
    try {
      var rows = account.templates.where(
        (t) => t['id'] == notice['template_id'],
      );
      if (rows.isEmpty) {
        await account.reloadTemplates(scope);
        if (!mounted || !account.retainsAccess(scope)) return;
        rows = account.templates.where((t) => t['id'] == notice['template_id']);
      }
      if (rows.isEmpty) {
        toast(context, '模板已不可用，请联系团队管理员');
        return;
      }
      final template = rows.first;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => !CloudScope.of(c).retainsAccess(scope)
            ? SafeArea(child: ListTile(title: Text(tr(c, '工作区已切换'))))
            : SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      '${template['name']}',
                      style: Theme.of(c).textTheme.titleLarge,
                    ),
                    for (final item in template['items'] as List? ?? [])
                      ListTile(
                        leading: const Icon(Icons.checklist),
                        title: Text('${item['label']}'),
                      ),
                  ],
                ),
              ),
      );
    } catch (_) {
      if (mounted && account.retainsAccess(scope)) {
        toast(context, '检查清单加载失败，请重试');
      }
    } finally {
      if (mounted) setState(() => fetchingTemplate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.retainsAccess(scope)) {
      return DetailScaffold(
        title: tr(context, '工作区已切换'),
        children: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '返回')),
          ),
        ],
      );
    }
    final kind = notice['kind'];
    final latest = account.notifications.where(
      (n) =>
          n['task_id'] == notice['task_id'] &&
          n['version'] == notice['version'],
    );
    final isRead =
        confirmedRead ||
        (latest.isEmpty
            ? notice['read'] == true
            : latest.first['read'] == true);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr(
            context,
            kind == 'task'
                ? '生产安排'
                : kind == 'template'
                ? '模板更新'
                : '通知预告',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${notice['part_name']}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            (DateTime.tryParse(
                      '${notice['updated_at']}',
                    )?.toLocal().toString() ??
                    '')
                .split('.')
                .first,
          ),
          const Divider(height: 30),
          Text(
            '${notice['body'] ?? ''}',
            style: const TextStyle(fontSize: 18, height: 1.8),
          ),
          const SizedBox(height: 24),
          if (notice['linked_task'] != null)
            FilledButton(
              onPressed: () => openPage(
                context,
                CloudTracePage(
                  link: TaskTrace(
                    account.activeWorkspace!['id'] as int,
                    '${notice['linked_task']}',
                  ).link,
                  requiredAccessScope: scope,
                ),
              ),
              child: Text(tr(context, '查看生产任务')),
            ),
          if (notice['template_id'] != null)
            FilledButton.tonal(
              onPressed: fetchingTemplate ? null : viewChecklist,
              child: Text(tr(context, '查看检查清单')),
            ),
          TextButton(
            onPressed: marking || isRead
                ? null
                : () async {
                    if (marking || !account.retainsAccess(scope)) return;
                    setState(() => marking = true);
                    try {
                      await account.markNotificationRead(notice, scope);
                      if (context.mounted && account.retainsAccess(scope)) {
                        setState(() => confirmedRead = true);
                        toast(context, '已标记为已读');
                      }
                    } catch (_) {
                      if (context.mounted && account.retainsAccess(scope)) {
                        toast(context, '同步失败，请重试');
                      }
                    } finally {
                      if (mounted) setState(() => marking = false);
                    }
                  },
            child: Text(tr(context, isRead ? '已读' : '标为已读')),
          ),
        ],
      ),
    );
  }
}

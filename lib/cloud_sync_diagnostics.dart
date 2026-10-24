import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cloud_account.dart';
import 'cloud_outbox.dart';
import 'cloud_feedback.dart';
import 'collaboration_api.dart';
import 'l10n.dart';
import 'ui.dart';
import 'screens/cloud_tasks.dart';

class CloudDiagnosticsPage extends StatefulWidget {
  final DateTime Function() now;
  const CloudDiagnosticsPage({super.key, this.now = DateTime.now});
  @override
  State<CloudDiagnosticsPage> createState() => _CloudDiagnosticsPageState();
}

class _CloudDiagnosticsPageState extends State<CloudDiagnosticsPage> {
  String? scope;
  bool busy = false;
  Object? failure;
  bool localReadFailed = false;
  Map<String, dynamic>? report;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CloudScope.of(context).accessScope;
    if (scope != next) {
      scope = next;
      report = null;
      failure = null;
      localReadFailed = false;
      busy = false;
      generation++;
      if (next != null) check();
    }
  }

  Future<void> check() async {
    final account = CloudScope.of(context),
        captured = scope,
        ticket = ++generation;
    if (!account.retainsAccess(captured)) return;
    setState(() {
      busy = true;
      failure = null;
    });
    final next = <String, dynamic>{
      'app_version': appVersion,
      'platform': Platform.operatingSystem,
      'checked_at': widget.now().toUtc().toIso8601String(),
      'workspace_id': account.activeWorkspace?['id'],
    };
    bool localFailed = false;
    Object? cloudFailure;
    bool currentScope() =>
        mounted && ticket == generation && account.retainsAccess(captured);
    try {
      final photos = await CloudOutbox(account).list();
      if (!currentScope()) return;
      final drafts = await account.listDrafts();
      if (!currentScope()) return;
      next['pending_photos'] = photos
          .where((photo) => photo['state'] != 'uploaded')
          .length;
      next['acknowledged_photos'] = photos
          .where((photo) => photo['state'] == 'uploaded')
          .length;
      next['drafts'] = drafts.length;
    } catch (_) {
      localFailed = true;
    }
    if (!currentScope()) return;
    try {
      await account.request(
        'GET',
        'workspaces/${next['workspace_id']}/metrics/',
      );
      next['status'] = 200;
    } on CollaborationApiException catch (failure) {
      next['status'] = failure.status;
      cloudFailure = failure;
    } catch (error) {
      next['status'] = 0;
      cloudFailure = error;
    }
    if (!currentScope()) return;
    next['local_storage'] = localFailed ? 'unavailable' : 'readable';
    setState(() {
      report = next;
      busy = false;
      failure = cloudFailure;
      localReadFailed = localFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (account.activeWorkspace == null) {
      return DetailScaffold(
        title: tr(context, '同步诊断'),
        children: [CloudWorkspaceStatus(account: account)],
      );
    }
    final data = report;
    return DetailScaffold(
      title: tr(context, '同步诊断'),
      children: [
        const Text('LineSight $appVersion'),
        if (busy) const LinearProgressIndicator(),
        if (data != null) ...[
          ListTile(
            title: Text(tr(context, '云端连接')),
            trailing: Text(
              tr(context, data['status'] == 200 ? '连接正常' : '需要处理'),
            ),
          ),
          ListTile(
            title: Text(tr(context, '待上传图片')),
            trailing: Text('${data['pending_photos'] ?? '—'}'),
          ),
          ListTile(
            title: Text(tr(context, '已上传')),
            trailing: Text('${data['acknowledged_photos'] ?? '—'}'),
          ),
          ListTile(
            title: Text(tr(context, '本机草稿')),
            trailing: Text('${data['drafts'] ?? '—'}'),
          ),
          Text('${tr(context, '检查时间')} · ${data['checked_at']}'),
        ],
        if (localReadFailed)
          Text(
            tr(context, '未能读取本机待上传图片与草稿，请重新检查。'),
            style: const TextStyle(color: red),
          ),
        if (failure != null)
          CloudFailurePanel(failure: failure!, onRetry: check),
        if (failure == null)
          FilledButton.icon(
            onPressed: busy ? null : check,
            icon: const Icon(Icons.refresh),
            label: Text(tr(context, '检查连接')),
          ),
        OutlinedButton.icon(
          onPressed: data == null || busy
              ? null
              : () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ').convert(data),
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr(context, '诊断信息已复制'))),
                    );
                  }
                },
          icon: const Icon(Icons.copy),
          label: Text(tr(context, '复制诊断信息')),
        ),
      ],
    );
  }
}

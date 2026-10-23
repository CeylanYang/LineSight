import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cloud_account.dart';
import 'cloud_outbox.dart';
import 'collaboration_api.dart';
import 'l10n.dart';
import 'ui.dart';
import 'screens/cloud_tasks.dart';

class CloudDiagnosticsPage extends StatefulWidget {
  const CloudDiagnosticsPage({super.key});
  @override
  State<CloudDiagnosticsPage> createState() => _CloudDiagnosticsPageState();
}

class _CloudDiagnosticsPageState extends State<CloudDiagnosticsPage> {
  String? scope;
  bool busy = false;
  String? error;
  Map<String, dynamic>? report;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CloudScope.of(context).draftKey('diagnostics');
    if (scope != next) {
      scope = next;
      report = null;
      error = null;
      if (next != null) check();
    }
  }

  Future<void> check() async {
    final account = CloudScope.of(context),
        captured = scope,
        ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    final next = <String, dynamic>{
      'app_version': appVersion,
      'platform': Platform.operatingSystem,
      'checked_at': DateTime.now().toUtc().toIso8601String(),
      'workspace_id': account.activeWorkspace?['id'],
    };
    try {
      final photos = await CloudOutbox(account).list();
      final drafts = await account.listDrafts();
      next['pending_photos'] = photos
          .where((photo) => photo['state'] != 'uploaded')
          .length;
      next['acknowledged_photos'] = photos
          .where((photo) => photo['state'] == 'uploaded')
          .length;
      next['drafts'] = drafts.length;
      await account.request(
        'GET',
        'workspaces/${next['workspace_id']}/metrics/',
      );
      next['status'] = 200;
    } on CollaborationApiException catch (failure) {
      next['status'] = failure.status;
    } catch (_) {
      next['status'] = 0;
    }
    if (!mounted ||
        ticket != generation ||
        captured != account.draftKey('diagnostics')) {
      return;
    }
    setState(() {
      report = next;
      busy = false;
      if (next['status'] != 200) error = '连接未完成，请检查网络或重新登录';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!CloudScope.of(context).signedIn) return cloudAccessRequired(context);
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
        if (error != null)
          Text(tr(context, error!), style: const TextStyle(color: red)),
        FilledButton.icon(
          onPressed: busy ? null : check,
          icon: const Icon(Icons.refresh),
          label: Text(tr(context, '检查连接')),
        ),
        OutlinedButton.icon(
          onPressed: data == null
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

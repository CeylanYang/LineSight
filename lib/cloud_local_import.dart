import 'dart:convert';
import 'package:flutter/material.dart';
import 'cloud_account.dart';
import 'cloud_feedback.dart';
import 'l10n_catalog.dart';
import 'collaboration_api.dart';
import 'l10n.dart';
import 'models.dart';
import 'store.dart';
import 'ui.dart';
import 'screens/cloud_tasks.dart';

/// A preview is bound to both the local authorization and the cloud destination.
class CloudImportPlan {
  final AppStore local;
  final CloudAccount cloud;
  final int localSession, workspaceId;
  final String scope;
  final String? accessScope;
  final List<Inspection> records;
  CloudImportPlan.capture(this.local, this.cloud)
    : localSession = local.session,
      workspaceId = cloud.activeWorkspace?['id'] as int? ?? 0,
      scope = cloud.draftKey('legacy-import') ?? '',
      accessScope = cloud.accessScope,
      records = local.captureTeamImport() {
    authorize();
  }
  void authorize() {
    local.requireSession(localSession, elevated: true);
    cloud.requireAccess(accessScope, write: true);
    if (scope.isEmpty ||
        cloud.draftKey('legacy-import') != scope ||
        !cloud.canEdit) {
      throw const CollaborationApiException(403, '账户或工作区已变化，请重新预览');
    }
  }

  List<Inspection> selected(bool includeSamples) =>
      records.where((row) => includeSamples || !row.sample).toList();

  Future<Map<String, int>> upload({
    bool includeSamples = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    authorize();
    final rows = selected(includeSamples).map((row) => row.toJson()).toList();
    var imported = 0, skipped = 0, completed = 0;
    var batch = <Map<String, dynamic>>[], size = 0;
    Future<void> send() async {
      if (batch.isEmpty) return;
      authorize();
      final count = batch.length;
      final response = await cloud.request(
        'POST',
        'workspaces/$workspaceId/legacy-inspections/',
        body: {'records': batch, 'include_samples': includeSamples},
      );
      authorize();
      imported += response['imported'] as int;
      skipped += response['skipped'] as int;
      completed += count;
      onProgress?.call(completed, rows.length);
      batch = [];
      size = 0;
    }

    for (final row in rows) {
      final length = utf8.encode(jsonEncode(row)).length;
      if (length > 3 * 1024 * 1024) {
        throw const FormatException('单条记录超过导入限制，未上传');
      }
      if (batch.isNotEmpty &&
          (size + length > 3 * 1024 * 1024 || batch.length >= 250)) {
        await send();
      }
      batch.add(row);
      size += length;
    }
    await send();
    return {'imported': imported, 'skipped': skipped};
  }
}

class CloudLocalImportPage extends StatefulWidget {
  const CloudLocalImportPage({super.key});
  @override
  State<CloudLocalImportPage> createState() => _CloudLocalImportPageState();
}

class _CloudLocalImportPageState extends State<CloudLocalImportPage> {
  final username = TextEditingController(), password = TextEditingController();
  CloudImportPlan? plan;
  bool busy = false, includeSamples = false;
  int completed = 0, total = 0;
  Object? error, historyFailure;
  bool historyLoading = false;
  String? binding;
  bool bound = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      binding = CloudScope.of(context).accessScope;
      bound = true;
    }
    if (plan != null) {
      try {
        plan!.authorize();
      } catch (_) {
        plan = null;
        history = null;
        result = null;
        historyFailure = null;
      }
    }
  }

  Map<String, int>? result;
  Map<String, dynamic>? history;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> preview() async {
    if (busy) return;
    final local = AppScope.of(context), cloud = CloudScope.of(context);
    setState(() {
      busy = true;
      error = null;
      result = null;
      history = null;
      historyFailure = null;
      plan = null;
    });
    try {
      cloud.requireAccess(binding, write: true);
      if (!local.engineer || local.user?.enabled != true) {
        await local.login(username.text, password.text);
        password.clear();
      }
      if (!mounted) return;
      cloud.requireAccess(binding, write: true);
      final next = CloudImportPlan.capture(local, cloud);
      if (mounted) {
        setState(() {
          plan = next;
          includeSamples = false;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() => error = failure);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadHistory() async {
    final captured = plan;
    if (captured == null || historyLoading) return;
    setState(() {
      historyLoading = true;
      historyFailure = null;
    });
    try {
      captured.authorize();
      final records = Map<String, dynamic>.from(
        await captured.cloud.request(
          'GET',
          'workspaces/${captured.workspaceId}/legacy-inspections/',
        ),
      );
      captured.authorize();
      if (mounted && identical(plan, captured)) {
        setState(() => history = records);
      }
    } catch (failure) {
      if (mounted && identical(plan, captured)) {
        setState(() => historyFailure = failure);
      }
    } finally {
      if (mounted) setState(() => historyLoading = false);
    }
  }

  Future<void> upload() async {
    if (busy || plan == null) return;
    final captured = plan!, samples = includeSamples;
    setState(() => busy = true);
    try {
      captured.authorize();
      if (!await confirm(
        context,
        tr(context, '确认导入'),
        tr(context, '将 {0} 条记录导入 {1}', [
          captured.selected(samples).length,
          captured.cloud.activeWorkspace?['name'] ?? '',
        ]),
      )) {
        return;
      }
      captured.authorize();
      if (!mounted) return;
      setState(() {
        error = null;
        result = null;
        history = null;
        historyFailure = null;
        completed = 0;
        total = captured.selected(samples).length;
      });
      final uploaded = await captured.upload(
        includeSamples: samples,
        onProgress: (done, count) {
          if (mounted && identical(plan, captured)) {
            setState(() {
              completed = done;
              total = count;
            });
          }
        },
      );
      captured.authorize();
      if (!mounted || !identical(plan, captured)) return;
      setState(() => result = uploaded);
      await loadHistory();
    } catch (failure) {
      if (mounted && identical(plan, captured)) {
        setState(() => error = failure);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String failureMessage(BuildContext context, Object failure) {
    final raw = failure is StateError
        ? failure.message
        : failure is CollaborationApiException
        ? failure.message
        : '';
    return tr(context, englishMessages.containsKey(raw) ? raw : '操作未完成，请重试。');
  }

  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.of(context), local = AppScope.of(context);
    if (!cloud.signedIn || cloud.activeWorkspace == null) {
      return cloudAccessRequired(context);
    }
    if (!cloud.retainsAccess(binding)) return cloudScopeChanged(context);
    if (!cloud.canEdit) {
      return DetailScaffold(
        title: tr(context, '导入本机记录'),
        children: [Text(tr(context, '当前角色仅可查看记录'))],
      );
    }
    final captured = plan;
    var valid = captured != null;
    if (valid) {
      try {
        captured.authorize();
      } catch (_) {
        valid = false;
      }
    }
    final selected = valid
        ? captured!.selected(includeSamples)
        : <Inspection>[];
    return DetailScaffold(
      title: tr(context, '导入本机记录'),
      children: [
        Text('${tr(context, '目标团队')} · ${cloud.activeWorkspace!['name']}'),
        const SizedBox(height: 12),
        if (!valid) ...[
          Text(tr(context, '使用本机工程师或管理员账户授权读取记录')),
          if (!local.engineer || local.user?.enabled != true) ...[
            TextField(
              controller: username,
              decoration: InputDecoration(labelText: tr(context, '本机用户名')),
              enabled: !busy,
            ),
            TextField(
              controller: password,
              decoration: InputDecoration(labelText: tr(context, '本机密码')),
              obscureText: true,
              enabled: !busy,
            ),
          ],
          FilledButton(
            onPressed: busy ? null : preview,
            child: Text(tr(context, '授权并预览')),
          ),
        ] else ...[
          Text(tr(context, '将创建团队记录副本，本机记录保持不变。')),
          CheckboxListTile(
            value: includeSamples,
            title: Text(tr(context, '包含示例记录')),
            onChanged: busy
                ? null
                : (value) => setState(() {
                    includeSamples = value ?? false;
                    result = null;
                    history = null;
                    historyFailure = null;
                  }),
          ),
          if (selected.isEmpty) Text(tr(context, '没有可导入的记录')),
          Text(tr(context, '记录数：{0}', [selected.length])),
          Text(
            tr(context, '合格：{0} · 异常：{1}', [
              selected.where((row) => row.finalPassed).length,
              selected.where((row) => !row.finalPassed).length,
            ]),
          ),
          for (final row in selected.take(20))
            ListTile(
              title: Text('${row.recipeName} · ${row.serial}'),
              subtitle: Text(stamp(row.at)),
              trailing: Text(tr(context, row.finalPassed ? '合格' : '异常')),
            ),
          FilledButton.icon(
            onPressed: busy || selected.isEmpty ? null : upload,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(tr(context, result == null ? '确认导入' : '再次导入')),
          ),
        ],
        if (busy && total > 0 && valid) ...[
          LinearProgressIndicator(value: total == 0 ? null : completed / total),
          Text('$completed / $total'),
        ],
        if (error != null)
          Text(
            failureMessage(context, error!),
            style: const TextStyle(color: red),
          ),
        if (valid && result != null)
          Text(
            tr(context, '已导入 {0} 条，跳过 {1} 条', [
              result!['imported'],
              result!['skipped'],
            ]),
          ),
        if (valid && historyLoading) const CloudLoadingPanel(),
        if (valid && historyFailure != null)
          CloudFailurePanel(failure: historyFailure!, onRetry: loadHistory),
        if (valid && history != null) ...[
          SectionHeading(tr(context, '团队历史记录')),
          Text(tr(context, '记录数：{0}', [history!['count']])),
          for (final row in history!['records'] as List)
            ListTile(
              title: Text('${row['recipe']} · ${row['serial']}'),
              subtitle: Text('${row['at']}'),
              trailing: Wrap(
                spacing: 6,
                children: [
                  if (row['sample'] == true)
                    Tag(tr(context, '演示数据'), color: amber),
                  Text(tr(context, row['passed'] == true ? '合格' : '异常')),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

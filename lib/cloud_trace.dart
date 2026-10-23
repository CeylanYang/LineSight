import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'cloud_account.dart';
import 'cloud_feedback.dart';
import 'collaboration_api.dart';
import 'l10n.dart';
import 'ui.dart';
import 'screens/cloud_business.dart';
import 'screens/cloud_shell.dart';
import 'screens/cloud_tasks.dart';

class TaskTrace {
  final int workspaceId;
  final String jobId;
  const TaskTrace(this.workspaceId, this.jobId);
  String get link => 'linesight://task/$workspaceId/$jobId';
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static bool isLink(String value) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'linesight' && uri?.host == 'task';
  }

  static TaskTrace? parse(String raw, {int? workspaceId}) {
    final value = raw.trim();
    if (workspaceId != null && workspaceId > 0 && _uuid.hasMatch(value)) {
      return TaskTrace(workspaceId, value.toLowerCase());
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !isLink(value) ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.pathSegments.length != 2) {
      return null;
    }
    final workspace = int.tryParse(uri.pathSegments[0]);
    if (workspace == null ||
        workspace <= 0 ||
        workspace > 9223372036854775807 ||
        !_uuid.hasMatch(uri.pathSegments[1])) {
      return null;
    }
    return TaskTrace(workspace, uri.pathSegments[1].toLowerCase());
  }
}

Future<void> openCloudTraceInput(BuildContext context) async {
  final value = await cloudTextPrompt(context, '输入任务ID、批次号或工件SN');
  if (value == null || !context.mounted) return;
  await openCloudCode(context, value);
}

class BatchTrace {
  final int workspaceId;
  final String code;
  const BatchTrace(this.workspaceId, this.code);
  String get link =>
      'linesight://batch/$workspaceId/${Uri.encodeComponent(code)}';
  static bool isLink(String value) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'linesight' && uri?.host == 'batch';
  }

  static BatchTrace? parse(String raw, {int? workspaceId}) {
    var code = raw.trim();
    var workspace = workspaceId;
    final uri = Uri.tryParse(code);
    if (uri?.scheme == 'linesight') {
      if (uri!.host != 'batch' ||
          uri.pathSegments.length != 2 ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort) {
        return null;
      }
      workspace = int.tryParse(uri.pathSegments[0]);
      code = uri.pathSegments[1];
    } else if (uri?.hasScheme == true) {
      return null;
    }
    if (workspace == null ||
        workspace <= 0 ||
        code.isEmpty ||
        code.length > 160 ||
        code.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return null;
    }
    return BatchTrace(workspace, code);
  }
}

Future<void> openCloudCode(BuildContext context, String value) async {
  final trace = TaskTrace.parse(
    value,
    workspaceId: CloudScope.of(context).activeWorkspace?['id'] as int?,
  );
  final batch = BatchTrace.parse(
    value,
    workspaceId: CloudScope.of(context).activeWorkspace?['id'] as int?,
  );
  if (trace == null && batch == null) {
    toast(context, '追溯号无效，请检查后重试');
    return;
  }
  await Navigator.of(context).push(
    appPageRoute<void>(
      context,
      trace != null
          ? CloudTracePage(link: trace.link)
          : CloudBatchTracePage(trace: batch!),
    ),
  );
}

class CloudTraceCodePage extends StatelessWidget {
  final TaskTrace trace;
  final String partName;
  final String? batchCode;
  const CloudTraceCodePage({
    super.key,
    required this.trace,
    required this.partName,
    this.batchCode,
  });
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn ||
        account.activeWorkspace?['id'] != trace.workspaceId) {
      return cloudAccessRequired(context);
    }
    return DetailScaffold(
      title: tr(context, '任务二维码'),
      children: [
        Text(partName, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        if (batchCode?.isNotEmpty == true) ...[
          SectionHeader(tr(context, '批次二维码'), icon: Icons.qr_code_2),
          Center(
            child: QrImageView(
              data: BatchTrace(trace.workspaceId, batchCode!).link,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
          Center(child: SelectableText(batchCode!)),
          const SizedBox(height: 16),
        ],
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: ColoredBox(
              color: Colors.white,
              child: RepaintBoundary(
                key: const ValueKey('task-qr-image'),
                child: QrImageView(
                  data: trace.link,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(24),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(trace.jobId),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(tr(context, '复制任务ID')),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: trace.jobId));
            if (context.mounted) toast(context, '已复制');
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.link),
          label: Text(tr(context, '复制追溯链接')),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: trace.link));
            if (context.mounted) toast(context, '已复制');
          },
        ),
      ],
    );
  }
}

class CloudTracePage extends StatefulWidget {
  final String link;
  final String? requiredAccessScope;
  const CloudTracePage({
    super.key,
    required this.link,
    this.requiredAccessScope,
  });
  @override
  State<CloudTracePage> createState() => _CloudTracePageState();
}

class _CloudTracePageState extends State<CloudTracePage> {
  String? identity;
  Object? error;
  bool busy = false;
  Map<String, dynamic>? job;
  int generation = 0;
  String? identityOf(CloudAccount account) =>
      account.signedIn ? '${account.profile?['id']}' : null;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = CloudScope.of(context);
    final next = identityOf(account);
    if (widget.requiredAccessScope != null &&
        !account.retainsAccess(widget.requiredAccessScope)) {
      generation++;
      job = null;
      busy = false;
      error = const CollaborationApiException(403, '账户或团队已切换，请重新打开页面');
      return;
    }
    if (next != identity) {
      identity = next;
      job = null;
      error = null;
      if (next != null) load();
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context),
        trace = TaskTrace.parse(widget.link),
        captured = identity,
        ticket = ++generation;
    if (trace == null) return;
    setState(() {
      busy = true;
      error = null;
      job = null;
    });
    try {
      if (widget.requiredAccessScope != null) {
        account.requireAccess(widget.requiredAccessScope);
      }
      final data = Map<String, dynamic>.from(
        await account.request(
              'GET',
              'workspaces/${trace.workspaceId}/jobs/${trace.jobId}/',
            )
            as Map,
      );
      if (captured != identityOf(account)) return;
      if (widget.requiredAccessScope != null) {
        account.requireAccess(widget.requiredAccessScope);
      }
      if (account.activeWorkspace?['id'] != trace.workspaceId) {
        final matches = account.workspaces.where(
          (workspace) => workspace['id'] == trace.workspaceId,
        );
        if (matches.isEmpty) {
          throw const CollaborationApiException(403, '当前账户无法访问该任务');
        }
        await account.selectWorkspace(matches.first);
        if (account.error != null) {
          throw const CollaborationApiException(503, '无法打开任务，请重试');
        }
      }
      if (mounted && ticket == generation && captured == identityOf(account)) {
        setState(() => job = data);
      }
    } catch (failure) {
      if (mounted && ticket == generation && captured == identityOf(account)) {
        setState(() => error = failure);
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context),
        trace = TaskTrace.parse(widget.link);
    if (trace != null && job != null && account.signedIn) {
      return CloudTaskPage(job: job!, workspaceId: trace.workspaceId);
    }
    return DetailScaffold(
      title: tr(context, '任务追溯'),
      children: [
        if (trace == null)
          Text(tr(context, '追溯号无效，请检查后重试'))
        else if (!account.signedIn) ...[
          Text(tr(context, '登录后查看任务与检验记录')),
          FilledButton.icon(
            icon: const Icon(Icons.login),
            label: Text(tr(context, '登录')),
            onPressed: () => openPage(context, const CloudLoginPage()),
          ),
        ] else ...[
          if (busy || account.restoring) const LinearProgressIndicator(),
          if (error != null) CloudFailurePanel(failure: error!, onRetry: load),
          if (!busy && error == null)
            FilledButton(onPressed: load, child: Text(tr(context, '重试'))),
        ],
      ],
    );
  }
}

class CloudScanPage extends StatefulWidget {
  const CloudScanPage({super.key});
  @override
  State<CloudScanPage> createState() => _CloudScanPageState();
}

class _CloudScanPageState extends State<CloudScanPage> {
  bool captured = false;
  String? error;
  void detected(BarcodeCapture result) {
    if (captured) return;
    for (final barcode in result.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      final trace = TaskTrace.parse(
        value,
        workspaceId: CloudScope.of(context).activeWorkspace?['id'] as int?,
      );
      final batch = BatchTrace.parse(
        value,
        workspaceId: CloudScope.of(context).activeWorkspace?['id'] as int?,
      );
      if (trace == null && batch == null) {
        setState(() => error = '请扫描任务二维码、批次条码或工件SN');
        continue;
      }
      captured = true;
      Navigator.of(context).pushReplacement(
        appPageRoute<void>(
          context,
          trace != null
              ? CloudTracePage(link: trace.link)
              : CloudBatchTracePage(trace: batch!),
        ),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: tr(context, '扫码追溯'),
    children: [
      AspectRatio(
        aspectRatio: 1,
        child: captured
            ? const SizedBox.expand()
            : MobileScanner(
                onDetect: detected,
                errorBuilder: (context, failure) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(tr(context, '相机不可用，请允许相机访问或输入追溯号')),
                  ),
                ),
              ),
      ),
      if (error != null) Text(trMessage(context, error!)),
      OutlinedButton.icon(
        icon: const Icon(Icons.keyboard),
        label: Text(tr(context, '输入任务ID、批次号或工件SN')),
        onPressed: () async {
          setState(() => captured = true);
          await openCloudTraceInput(context);
          if (mounted) setState(() => captured = false);
        },
      ),
    ],
  );
}

class CloudBatchTracePage extends StatefulWidget {
  final BatchTrace trace;
  const CloudBatchTracePage({super.key, required this.trace});
  @override
  State<CloudBatchTracePage> createState() => _CloudBatchTracePageState();
}

class _CloudBatchTracePageState extends State<CloudBatchTracePage> {
  bool bound = false, busy = false;
  String? binding;
  Object? error;
  List<Map<String, dynamic>> rows = [];
  bool truncated = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound || (binding == null && CloudScope.of(context).signedIn)) {
      bound = true;
      binding = CloudScope.of(context).accessScope;
      if (binding != null) load();
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
    if (!account.retainsAccess(binding)) return;
    setState(() {
      busy = true;
      error = null;
      rows = [];
    });
    try {
      final data =
          await account.request(
                'GET',
                'workspaces/${widget.trace.workspaceId}/trace/lookup/?${Uri(queryParameters: {'code': widget.trace.code}).query}',
              )
              as Map;
      if (mounted && account.retainsAccess(binding)) {
        setState(() {
          rows = (data['jobs'] as List).cast<Map<String, dynamic>>();
          truncated = data['truncated'] == true;
        });
      }
    } catch (failure) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() => error = failure);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    return DetailScaffold(
      title: tr(context, '工件与批次追溯'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
          tooltip: tr(context, '刷新'),
        ),
      ],
      children: [
        SelectableText(
          widget.trace.code,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        if (busy) const CloudLoadingPanel(),
        if (error != null) CloudFailurePanel(failure: error!, onRetry: load),
        if (!busy && error == null && rows.isEmpty)
          EmptyState(
            title: tr(context, '没有匹配的工件或批次'),
            subtitle: tr(context, '核对编号后重新扫码或输入。'),
          ),
        for (final job in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassPanel(
              child: ListTile(
                title: Text('${job['part_name']}'),
                subtitle: Text(
                  '${job['batch_code']} · ${job['quantity']} ${tr(context, '件')}'
                  '${job['matched_serial'] == null ? '' : '\n${job['matched_serial']} · ${tr(context, switch (job['piece_verdict']) {
                          'pass' => '合格',
                          'fail' => '异常',
                          'scrap' => '报废',
                          _ => '待检验',
                        })}'}',
                ),
                trailing: Tag(
                  tr(context, taskStatusLabels[job['status']] ?? '待打印'),
                  color: taskColor('${job['status']}'),
                ),
                onTap: () => openPage(
                  context,
                  CloudTracePage(
                    link: TaskTrace(
                      widget.trace.workspaceId,
                      '${job['id']}',
                    ).link,
                  ),
                ),
              ),
            ),
          ),
        if (truncated) Text(tr(context, '结果超过100条，请按工件SN继续查询')),
      ],
    );
  }
}

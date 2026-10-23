import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'cloud_account.dart';
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
  final value = await cloudTextPrompt(context, '输入任务ID或追溯链接');
  if (value == null || !context.mounted) return;
  final trace = TaskTrace.parse(
    value,
    workspaceId: CloudScope.of(context).activeWorkspace?['id'] as int?,
  );
  if (trace == null) {
    toast(context, '追溯号无效，请检查后重试');
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CloudTracePage(link: trace.link)),
  );
}

class CloudTraceCodePage extends StatelessWidget {
  final TaskTrace trace;
  final String partName;
  const CloudTraceCodePage({
    super.key,
    required this.trace,
    required this.partName,
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
  const CloudTracePage({super.key, required this.link});
  @override
  State<CloudTracePage> createState() => _CloudTracePageState();
}

class _CloudTracePageState extends State<CloudTracePage> {
  String? identity, error;
  bool busy = false;
  Map<String, dynamic>? job;
  int generation = 0;
  String? identityOf(CloudAccount account) =>
      account.signedIn ? '${account.profile?['id']}' : null;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = identityOf(CloudScope.of(context));
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
      final data = Map<String, dynamic>.from(
        await account.request(
              'GET',
              'workspaces/${trace.workspaceId}/jobs/${trace.jobId}/',
            )
            as Map,
      );
      if (captured != identityOf(account)) return;
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
    } on CollaborationApiException catch (failure) {
      if (mounted && ticket == generation) {
        setState(
          () => error = failure.status == 403 || failure.status == 404
              ? '当前账户无法访问该任务'
              : failure.message,
        );
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => error = '无法打开任务，请检查网络后重试');
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
          if (error != null)
            Text(
              trMessage(context, error!),
              style: const TextStyle(color: red),
            ),
          if (!busy)
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
      if (trace == null) {
        setState(() => error = '请扫描LineSight任务二维码');
        continue;
      }
      captured = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CloudTracePage(link: trace.link),
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
        label: Text(tr(context, '输入任务ID或追溯链接')),
        onPressed: () async {
          setState(() => captured = true);
          await openCloudTraceInput(context);
          if (mounted) setState(() => captured = false);
        },
      ),
    ],
  );
}

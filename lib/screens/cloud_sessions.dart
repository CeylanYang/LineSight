import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_feedback.dart';
import '../l10n.dart';
import '../ui.dart';
import 'cloud_tasks.dart';

String identityDeviceLabel(Object? value) {
  final agent = '$value'.toLowerCase();
  for (final name in [
    'Android',
    'iPhone',
    'iPad',
    'Windows',
    'Mac',
    'Firefox',
    'Chrome',
    'Safari',
  ]) {
    if (agent.contains(name.toLowerCase())) return name;
  }
  return '其他设备';
}

class CloudSessionsPage extends StatefulWidget {
  const CloudSessionsPage({super.key});
  @override
  State<CloudSessionsPage> createState() => _CloudSessionsPageState();
}

class _CloudSessionsPageState extends State<CloudSessionsPage> {
  String? binding;
  bool initialized = false, busy = false;
  Object? error;
  List<Map<String, dynamic>> rows = [];
  bool current(CloudAccount account) =>
      binding != null && binding == account.identityScope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      binding = CloudScope.of(context).identityScope;
      load();
    }
    if (!current(CloudScope.of(context))) rows = [];
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
    if (!current(account) || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await account.listIdentitySessions();
      if (mounted && current(account)) setState(() => rows = result);
    } catch (failure) {
      if (mounted && current(account)) setState(() => error = failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(Map<String, dynamic>? row) async {
    final account = CloudScope.of(context);
    if (!await confirm(
          context,
          tr(context, row == null ? '退出其他会话？' : '退出此会话？'),
          tr(context, row == null ? '其他设备需要重新登录，当前会话保留。' : '此会话将立即退出，需要重新登录。'),
        ) ||
        !mounted ||
        !current(account) ||
        busy) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (row == null) {
        await account.revokeOtherIdentitySessions();
      } else {
        await account.revokeIdentitySession('${row['id']}');
      }
      if (mounted && current(account)) {
        final result = await account.listIdentitySessions();
        if (mounted && current(account)) setState(() => rows = result);
      }
    } catch (failure) {
      if (mounted && current(account)) setState(() => error = failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String timestamp(Object? seconds) => seconds is num
      ? cloudTimestamp(
          DateTime.fromMillisecondsSinceEpoch(
            seconds.toInt() * 1000,
          ).toIso8601String(),
        )
      : '—';

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!current(account)) return cloudScopeChanged(context);
    return DetailScaffold(
      title: tr(context, '登录会话'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr(context, '管理当前账户的登录设备'),
                style: const TextStyle(color: muted),
              ),
            ),
            IconButton(
              onPressed: busy ? null : load,
              tooltip: tr(context, '刷新'),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: busy || !rows.any((row) => row['current'] != true)
              ? null
              : () => revoke(null),
          icon: const Icon(Icons.logout),
          label: Text(tr(context, '退出其他会话')),
        ),
        const SizedBox(height: 16),
        if (busy) const CloudLoadingPanel(),
        if (error != null) CloudFailurePanel(failure: error!, onRetry: load),
        if (!busy && error == null && rows.isEmpty)
          EmptyState(
            icon: Icons.devices,
            title: tr(context, '暂无登录会话'),
            subtitle: tr(context, '刷新查看最新登录状态'),
          ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices, color: blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr(context, identityDeviceLabel(row['browser'])),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (row['current'] == true)
                        Text(
                          tr(context, '当前会话'),
                          style: const TextStyle(color: green),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${tr(context, '登录时间')} · ${timestamp(row['started'])}',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  Text(
                    '${tr(context, '最近活动')} · ${timestamp(row['lastAccess'])}',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: busy ? null : () => revoke(row),
                      icon: const Icon(Icons.logout, size: 16),
                      label: Text(tr(context, '退出此会话')),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

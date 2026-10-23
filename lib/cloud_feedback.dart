import 'package:flutter/material.dart';
import 'cloud_account.dart';
import 'collaboration_api.dart';
import 'l10n.dart';
import 'l10n_catalog.dart';
import 'screens/cloud_shell.dart' show CloudLoginPage;
import 'ui.dart';

/// Read recovery only: callers supply a GET reload, never a write command.
class CloudFailurePanel extends StatefulWidget {
  final Object failure;
  final Future<void> Function() onRetry;
  const CloudFailurePanel({
    super.key,
    required this.failure,
    required this.onRetry,
  });
  @override
  State<CloudFailurePanel> createState() => _CloudFailurePanelState();
}

class _CloudFailurePanelState extends State<CloudFailurePanel> {
  bool busy = false;
  Object? actionFailure;
  @override
  void didUpdateWidget(CloudFailurePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.failure != widget.failure) actionFailure = null;
  }

  @override
  Widget build(BuildContext context) {
    final failure = actionFailure ?? widget.failure;
    final status = failure is CollaborationApiException ? failure.status : 0;
    final (title, message, action, icon) = switch (status) {
      401 => ('请重新登录', '登录后继续，未提交内容会保留。', '登录', Icons.lock_outline),
      403 => (
        '当前账户没有访问权限',
        '刷新团队权限，或返回工作台选择其他工作区。',
        '刷新权限',
        Icons.shield_outlined,
      ),
      404 => ('记录暂不可访问', '记录可能已移除，或不在当前工作区。', '返回工作台', Icons.search_off),
      409 => (
        '任务已更新',
        '刷新当前状态后核对内容，再决定是否提交。',
        '刷新当前状态',
        Icons.sync_problem_outlined,
      ),
      413 => (
        '照片文件过大',
        '返回拍照页面，压缩照片后重新上传。',
        '返回工作台',
        Icons.photo_size_select_large,
      ),
      >= 500 => (
        '服务暂不可用',
        '稍后重试，或在同步页面查看连接状态。',
        '重试',
        Icons.cloud_off_outlined,
      ),
      400 || 422 => ('请核对填写内容', '检查必填项与数量后重新提交。', '重新加载', Icons.edit_note),
      _ => ('连接未完成', '检查网络连接后重试，当前筛选条件会保留。', '重试', Icons.wifi_off_outlined),
    };
    final raw = failure is CollaborationApiException
        ? failure.message
        : '$failure';
    // Only catalogued application messages are customer copy. Transport/HTML
    // responses and exception strings may contain internal or private data.
    final detail = englishMessages.containsKey(raw)
        ? tr(context, raw)
        : tr(context, message);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Semantics(
        liveRegion: true,
        child: GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: status == 409 ? amber : red, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, title),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              if (status == 404 || status == 413) {
                                Navigator.of(
                                  context,
                                ).popUntil((route) => route.isFirst);
                              } else if (status == 401) {
                                openPage(context, const CloudLoginPage());
                              } else if (status == 403) {
                                final account = CloudScope.of(context);
                                await account.reload();
                                if (context.mounted &&
                                    account.signedIn &&
                                    account.error == null) {
                                  await widget.onRetry();
                                }
                              } else {
                                await widget.onRetry();
                              }
                            } catch (failure) {
                              if (mounted) {
                                setState(() => actionFailure = failure);
                              }
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: Text(tr(context, busy ? '正在加载' : action)),
                  ),
                  if (status == 403)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst),
                      child: Text(tr(context, '返回工作台')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CloudLoadingPanel extends StatelessWidget {
  const CloudLoadingPanel({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: tr(context, '正在加载'),
    child: GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(context, '正在加载'),
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 12),
          for (final width in [1.0, .72, .45])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: width,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: hairline.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

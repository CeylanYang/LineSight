import 'package:flutter/material.dart';
import '../l10n.dart';
import '../ota_update.dart';
import '../ui.dart';

class AppUpdatesPage extends StatelessWidget {
  const AppUpdatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = OtaUpdates.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, '应用更新'))),
      body: ListenableBuilder(
        listenable: updates,
        builder: (context, _) {
          final busy = {
            OtaStatus.checking,
            OtaStatus.downloading,
          }.contains(updates.status);
          final message = switch (updates.status) {
            OtaStatus.checking => '正在检查更新',
            OtaStatus.downloading => '正在下载更新',
            OtaStatus.ready => '更新已准备好，下次启动生效',
            OtaStatus.offline => '暂时无法检查更新，请稍后重试',
            OtaStatus.rejected => '本次更新未应用，继续使用当前版本',
            OtaStatus.unavailable => '当前版本暂不支持自动更新',
            _ => '已是最新内容',
          };
          return PageBody(
            children: [
              PageHeading(
                eyebrow: 'LineSight',
                title: tr(context, '应用更新'),
                subtitle: tr(context, '自动下载更新，下次启动生效。'),
              ),
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LineSight $appVersion',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(tr(context, '内容版本 {0}', [otaRevision])),
                    const SizedBox(height: 20),
                    Text(tr(context, message)),
                    if (busy) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: updates.status == OtaStatus.downloading
                            ? updates.progress
                            : null,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: busy ? null : updates.check,
                      icon: const Icon(Icons.refresh),
                      label: Text(tr(context, '检查更新')),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

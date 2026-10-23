import 'package:flutter/material.dart';
import 'cloud_account.dart';
import 'cloud_trace.dart';
import 'ui.dart';

/// Notifications resolve from their server ID, independent of dashboard caches.
void openCloudNotification(BuildContext context, Map<String, dynamic> notice) {
  final account = CloudScope.of(context),
      scope = CloudScope.of(context).accessScope;
  if (!account.retainsAccess(scope)) return;
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

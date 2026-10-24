import 'package:flutter/material.dart';
import '../cloud_layout.dart';
import '../cloud_account.dart';
import '../cloud_feedback.dart';
import '../ui.dart';
import 'cloud_business.dart';
import 'cloud_tasks.dart';

class CloudInspectionHub extends StatefulWidget {
  final int initialTab;
  final ValueChanged<int>? onTabChanged;
  const CloudInspectionHub({super.key, this.initialTab = 0, this.onTabChanged});
  @override
  State<CloudInspectionHub> createState() => _CloudInspectionHubState();
}

class _CloudInspectionHubState extends State<CloudInspectionHub> {
  late int tab = widget.initialTab;
  late final visited = <int>{tab};
  @override
  void didUpdateWidget(CloudInspectionHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      tab = widget.initialTab;
      visited.add(tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.workspaceDataReady) {
      return PageBody(children: [CloudWorkspaceStatus(account: account)]);
    }
    return Column(
      children: [
        CloudSectionTabs(
          labels: const ['待检任务', '检测记录', '质量报告'],
          selected: tab,
          onSelected: (value) => setState(() {
            tab = value;
            visited.add(value);
            widget.onTabChanged?.call(value);
          }),
        ),
        Expanded(
          child: IndexedStack(
            index: tab,
            children: [
              if (visited.contains(0))
                const CloudTaskListPage(status: 'inspection', embedded: true)
              else
                const SizedBox.shrink(),
              if (visited.contains(1))
                const CloudRecordsPage(compact: true)
              else
                const SizedBox.shrink(),
              if (visited.contains(2))
                const CloudReportPage(embedded: true)
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

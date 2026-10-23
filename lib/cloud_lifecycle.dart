import 'package:flutter/material.dart';
import 'l10n.dart';
import 'ui.dart';

enum LifecycleState { pending, active, complete, skipped }

class LifecycleStep {
  final String label;
  final LifecycleState state;
  const LifecycleStep(this.label, this.state);
}

List<LifecycleStep> cloudLifecycle(Map<String, dynamic> job) {
  final status = job['status'];
  final issue =
      (job['exceptions'] as List? ?? []).isNotEmpty ||
      (job['inspections'] as List? ?? []).any(
        (row) => row['verdict'] == 'fail',
      );
  final index = switch (status) {
    'queued' => 0,
    'printing' => 1,
    'inspection' => issue ? 3 : 2,
    'exception' => 3,
    'closed' => 4,
    _ => -1,
  };
  return [
    for (var i = 0; i < 5; i++)
      LifecycleStep(
        i == 3
            ? (status == 'exception'
                  ? '异常处理中'
                  : status == 'inspection' && issue
                  ? '待复检'
                  : '异常／复检')
            : ['待打印', '打印中', '质检', '', '已关闭'][i],
        i == 3 && status == 'closed' && !issue
            ? LifecycleState.skipped
            : i == index
            ? LifecycleState.active
            : i < index
            ? LifecycleState.complete
            : LifecycleState.pending,
      ),
  ];
}

class CloudLifecycleTrack extends StatelessWidget {
  final Map<String, dynamic> job;
  const CloudLifecycleTrack({super.key, required this.job});
  @override
  Widget build(BuildContext context) {
    final steps = cloudLifecycle(job);
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, box) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: box.maxWidth < MediaQuery.textScalerOf(context).scale(280)
                  ? MediaQuery.textScalerOf(context).scale(280)
                  : box.maxWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < steps.length; i++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final step = steps[i];
                          final color =
                              step.state == LifecycleState.complete ||
                                  (i == 4 &&
                                      step.state == LifecycleState.active)
                              ? green
                              : step.state == LifecycleState.active
                              ? (job['status'] == 'exception' ? red : blue)
                              : muted;
                          final state = switch (step.state) {
                            LifecycleState.pending => '待进行',
                            LifecycleState.active => i == 4 ? '已完成' : '当前阶段',
                            LifecycleState.complete => '已完成',
                            LifecycleState.skipped => '已跳过',
                          };
                          return Semantics(
                            label:
                                '${tr(context, step.label)}，${tr(context, state)}',
                            child: ExcludeSemantics(
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 2,
                                          color: i == 0
                                              ? Colors.transparent
                                              : hairline,
                                        ),
                                      ),
                                      Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: .12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          step.state == LifecycleState.skipped
                                              ? Icons.remove
                                              : step.state ==
                                                        LifecycleState
                                                            .complete ||
                                                    i == 4 &&
                                                        step.state ==
                                                            LifecycleState
                                                                .active
                                              ? Icons.check
                                              : step.state ==
                                                    LifecycleState.active
                                              ? Icons.circle
                                              : Icons.circle_outlined,
                                          size: 14,
                                          color: color,
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          height: 2,
                                          color: i == 4
                                              ? Colors.transparent
                                              : hairline,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    tr(context, step.label),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                    ),
                                  ),
                                  if (step.state == LifecycleState.skipped)
                                    Text(
                                      tr(context, '已跳过'),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

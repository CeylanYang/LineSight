import 'package:flutter/material.dart';
import '../files.dart';
import '../models.dart';
import '../record_csv.dart';
import '../stream_backup.dart';
import '../ui.dart';
import 'backup_transfer.dart';

class CsvExportPage extends StatefulWidget {
  final CsvSnapshot snapshot;
  final int session;
  final String scope, filterSummary;
  const CsvExportPage({
    super.key,
    required this.snapshot,
    required this.session,
    required this.scope,
    required this.filterSummary,
  });
  @override
  State<CsvExportPage> createState() => _CsvExportPageState();
}

class _CsvExportPageState extends State<CsvExportPage> {
  ArchiveTask<PreparedArchive>? task;
  bool busy = false, saving = false;
  @override
  void dispose() {
    task?.cancel();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      saving = false;
      task = null;
    });
    try {
      await exportRecords(
        context,
        widget.snapshot,
        expectedSession: widget.session,
        scope: widget.scope,
        onTask: (job) {
          if (!mounted) {
            job.cancel();
            return;
          }
          setState(() => task = job);
        },
        onSaving: () {
          if (mounted) setState(() => saving = true);
        },
      );
    } catch (e) {
      if (mounted) {
        toast(context, e is StateError ? e.message.toString() : '导出未完成，请重试。');
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot, records = snapshot.records;
    final archived = records.where((r) => r.archived).length;
    return DetailScaffold(
      title: '导出检测记录',
      children: [
        const PageHeading(
          eyebrow: 'DATA / CSV',
          title: '把记录带到表格。',
          subtitle: '先确认范围，保存后自动检查文件完整性。',
        ),
        GlassPanel(
          child: Column(
            children: [
              InfoRow('导出范围', widget.scope),
              InfoRow('筛选与顺序', widget.filterSummary),
              InfoRow('检测记录', '${records.length} 条'),
              InfoRow('其中归档', '$archived 条'),
              InfoRow('示例 / 模拟', '${records.where((r) => r.sample).length} 条'),
              InfoRow('快照时间', zonedStamp(snapshot.capturedAt, precise: true)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '保存打开此页时的记录、工位名称和排列顺序。之后的复核、归档或新增记录不会改变本次内容；需要最新数据时，请返回后重新打开导出。',
          style: TextStyle(height: 1.7),
        ),
        const SectionHeading('表格包含什么'),
        const GlassPanel(
          child: Text(
            '15 列：记录 ID、序列号、工位、检测时间、配方快照名称、原始结果、缺陷、置信度、复核结果、复核人、复核时间、依据、操作员、示例标记和归档标记。\n\n时间统一使用 UTC，末尾带 Z。UTF-8 编码兼容中文；可能被表格软件当作公式的文本会加单引号保护。CSV 用于分析，不能替代业务备份。',
            style: TextStyle(height: 1.7),
          ),
        ),
        if (records.isNotEmpty) ...[
          const SectionHeading('前 3 条预览'),
          GlassPanel(
            child: Column(
              children: [
                for (final row in records.take(3))
                  InfoRow(
                    row.serial,
                    '${row.values[2]}\n${instantJson(row.at)}',
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          '生成文件时可取消。生成后选择保存位置，保存完成会回读校验。文件上限 256 MB，内容未加密，请妥善保管。',
          style: TextStyle(fontSize: 12, height: 1.7),
        ),
        const SizedBox(height: 24),
        if (busy) ...[
          if (task != null && !saving)
            ValueListenableBuilder<BackupProgress>(
              valueListenable: task!.progress,
              builder: (_, progress, _) => TransferProgress(progress: progress),
            )
          else
            GlassPanel(
              child: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(saving ? '等待保存并回读校验…' : '正在准备导出…')),
                ],
              ),
            ),
          if (task != null && !saving)
            OutlinedButton.icon(
              onPressed: () => task!.cancel(),
              icon: const Icon(Icons.close),
              label: const Text('取消准备'),
            ),
        ] else
          BusyButton(
            label: '保存 CSV',
            icon: Icons.save_alt_rounded,
            onPressed: AppScope.of(context).engineer ? save : null,
          ),
      ],
    );
  }
}

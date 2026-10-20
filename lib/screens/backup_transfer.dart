import '../l10n.dart';
import 'package:flutter/material.dart';
import '../backup.dart';
import '../files.dart';
import '../stream_backup.dart';
import '../ui.dart';
import 'restore.dart';

class BackupExportPage extends StatefulWidget {
  const BackupExportPage({super.key});
  @override
  State<BackupExportPage> createState() => _BackupExportPageState();
}

class _BackupExportPageState extends State<BackupExportPage> {
  ArchiveTask<PreparedArchive>? task;
  bool compatible = false, busy = false, saving = false;
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
      if (compatible) {
        await exportBackup(context);
      } else {
        await exportStreamBackup(
          context,
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
      }
    } catch (error) {
      if (mounted) {
        toast(
          context,
          error is StateError
              ? error.message.toString()
              : error is FormatException
              ? error.message
              : tr(context, "备份未完成，请检查存储空间后重试。"),
        );
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
    final s = AppScope.of(context);
    return DetailScaffold(
      title: tr(context, "保存业务备份"),
      children: [
        PageHeading(
          eyebrow: 'DATA / BACKUP',
          title: tr(context, "完整保存，随时接续。"),
          subtitle: tr(context, "包含归档记录、配方、工位及全部操作日志。"),
        ),
        GlassPanel(
          child: Column(
            children: [
              InfoRow(
                tr(context, "检测记录"),
                tr(context, "{0} 条", [s.data.inspections.length]),
              ),
              InfoRow(
                tr(context, "操作日志"),
                tr(context, "{0} 条", [s.data.audits.length]),
              ),
              InfoRow(
                tr(context, "工位 / 配方"),
                '${s.data.stations.length} / ${s.data.recipes.length}',
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "备份格式")),
        RadioGroup<bool>(
          groupValue: compatible,
          onChanged: (v) {
            if (!busy && v != null) setState(() => compatible = v);
          },
          child: Column(
            children: [
              RadioListTile<bool>(
                value: false,
                enabled: !busy,
                title: Text(tr(context, "完整备份 LSB")),
                subtitle: Text(tr(context, "推荐 · 最大 256 MB")),
              ),
              RadioListTile<bool>(
                value: true,
                enabled: !busy,
                title: Text(tr(context, "兼容 JSON")),
                subtitle: Text(tr(context, "旧版应用 · 最大 20 MB")),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          child: Text(
            compatible
                ? tr(
                    context,
                    "适合交给旧版 LineSight，最大 20 MB。超过限制时可切换为完整备份，无需清理或删减历史。",
                  )
                : tr(
                    context,
                    "推荐用于日常备份，最大 256 MB。保存后会重新读取目标文件并校验完整性，恢复时也会检查。需要 LineSight 1.1.4 或更新版本。",
                  ),
            style: const TextStyle(height: 1.7),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr(
            context,
            "保存开始备份时的数据，期间的变更需另行备份。不包含本机账户、密码、恢复码和升级原件。文件未加密，请选择妥善保存的位置。恢复前可查看逐项差异。",
          ),
          style: const TextStyle(fontSize: 12, height: 1.7),
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
                  Expanded(
                    child: Text(
                      saving
                          ? tr(context, "等待保存并回读校验…")
                          : tr(context, "正在准备文件…"),
                    ),
                  ),
                ],
              ),
            ),
          if (task != null && !saving) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => task!.cancel(),
              icon: const Icon(Icons.close),
              label: Text(tr(context, "取消准备")),
            ),
          ],
        ] else
          BusyButton(
            label: compatible
                ? tr(context, "保存兼容 JSON")
                : tr(context, "保存完整备份"),
            icon: Icons.save_alt_rounded,
            onPressed: !s.engineer ? null : save,
          ),
      ],
    );
  }
}

class TransferProgress extends StatelessWidget {
  final BackupProgress progress;
  const TransferProgress({super.key, required this.progress});
  @override
  Widget build(BuildContext context) => GlassPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trMessage(context, progress.message),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: progress.fraction.clamp(0, 1)),
        const SizedBox(height: 10),
        Text(
          '${(progress.fraction * 100).floor()}% · ${fileSize(progress.bytes)}',
        ),
      ],
    ),
  );
}

class BackupImportPage extends StatefulWidget {
  final String path, name;
  final int session;
  final bool storageRecovery;
  final Widget Function(BackupDocument)? previewBuilder;
  const BackupImportPage({
    super.key,
    required this.path,
    required this.name,
    required this.session,
    this.storageRecovery = false,
    this.previewBuilder,
  }) : assert(!storageRecovery || previewBuilder != null);
  @override
  State<BackupImportPage> createState() => _BackupImportPageState();
}

class _BackupImportPageState extends State<BackupImportPage> {
  ArchiveTask<BackupDocument>? task;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    task?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted) return;
    final s = AppScope.of(context);
    void requireAccess() {
      if (widget.storageRecovery) {
        s.requireStorageRecovery(widget.session);
      } else {
        s.requireSession(widget.session, owner: true);
      }
    }

    try {
      requireAccess();
      final archive = await isArchiveFile(widget.path);
      requireAccess();
      if (!mounted) return;
      final BackupDocument document;
      if (archive) {
        final job = ArchiveTask.read(widget.path);
        setState(() => task = job);
        document = await job.result;
      } else {
        document = await readBackupFile(widget.path);
      }
      requireAccess();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.previewBuilder?.call(document) ??
              RestorePreviewPage(
                incoming: document.workspace,
                document: document,
                fileName: widget.name,
              ),
        ),
      );
    } on BackupCancelled {
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : e is StateError
              ? e.message.toString()
              : tr(context, "无法读取备份，请检查文件后重试。"),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: tr(context, "检查备份"),
    children: [
      PageHeading(
        eyebrow: 'DATA / VERIFY',
        title: tr(context, "先检查，再恢复。"),
        subtitle: widget.name,
      ),
      if (error != null) ...[
        EmptyState(
          title: tr(context, "备份未通过检查"),
          subtitle: tr(context, "{0} 当前业务数据尚未修改。", [
            trMessage(context, error!),
          ]),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(context, "返回选择其他文件")),
        ),
      ] else ...[
        if (task == null)
          GlassPanel(
            child: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 18),
                Expanded(child: Text(tr(context, "正在读取备份…"))),
              ],
            ),
          )
        else
          ValueListenableBuilder<BackupProgress>(
            valueListenable: task!.progress,
            builder: (_, progress, _) => TransferProgress(progress: progress),
          ),
        const SizedBox(height: 20),
        Text(
          tr(context, "检查通过后会显示恢复预览。此步骤不会写入业务数据。"),
          style: const TextStyle(height: 1.7),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () {
            task?.cancel();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.close),
          label: Text(tr(context, "取消读取")),
        ),
      ],
    ],
  );
}

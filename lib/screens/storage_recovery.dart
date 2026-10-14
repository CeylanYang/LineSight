import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../backup.dart';
import '../files.dart';
import '../models.dart';
import '../recovery_storage.dart';
import '../stream_backup.dart';
import '../ui.dart';
import 'backup_transfer.dart';

class StorageFailurePage extends StatefulWidget {
  const StorageFailurePage({super.key});
  @override
  State<StorageFailurePage> createState() => _StorageFailurePageState();
}

class _StorageFailurePageState extends State<StorageFailurePage> {
  final username = TextEditingController(), secret = TextEditingController();
  bool useCode = false, hidden = true;
  @override
  void dispose() {
    username.dispose();
    secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DetailScaffold(
      title: '本机数据恢复',
      children: [
        const PageHeading(
          eyebrow: 'LOCAL / RECOVERY',
          title: '保留原件，恢复工作。',
          subtitle: '工作区暂时无法打开，现有存储仍保留在本机。',
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                size: 42,
                color: amber,
              ),
              const SizedBox(height: 16),
              Text(
                s.startupError ?? '请检查本机存储后重试。',
                style: const TextStyle(height: 1.7),
              ),
              const SizedBox(height: 12),
              InfoRow('未完成步骤', s.startupStage),
              const Text(
                '可以先释放设备存储空间，再重试读取。重试会继续读取原数据库。',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 18),
              BusyButton(
                label: '重试读取',
                icon: Icons.refresh,
                onPressed: s.initializing || s.writing ? null : () => s.init(),
              ),
            ],
          ),
        ),
        if (s.canRecoverStorage) ...[
          const SectionHeading('使用已有备份恢复'),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '先验证本机管理员，再选择 LSB 或 JSON 备份。恢复前会保留原始存储；本机账户保持原有密码和权限。',
                  style: TextStyle(height: 1.7),
                ),
                if (s.lockReason != null) ...[
                  const SizedBox(height: 12),
                  Text(s.lockReason!, style: const TextStyle(color: amber)),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: username,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    labelText: '管理员用户名',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('使用账户恢复码验证'),
                  value: useCode,
                  onChanged: (v) => setState(() {
                    useCode = v;
                    secret.clear();
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: secret,
                  obscureText: hidden,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: useCode ? '账户恢复码' : '管理员密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: hidden ? '显示凭据' : '隐藏凭据',
                      onPressed: () => setState(() => hidden = !hidden),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '恢复码验证仅用于本次数据恢复，不会重设密码。连续验证失败 5 次会限制尝试 1 分钟。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 20),
                BusyButton(
                  label: '验证管理员',
                  icon: Icons.verified_user_outlined,
                  onPressed: () => s.loginForStorageRecovery(
                    username.text,
                    secret.text,
                    recoveryCode: useCode,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SectionHeading('暂时无法验证管理员'),
          const GlassPanel(
            child: Text(
              '需要可读取且已启用的本机管理员账户才能恢复。请保留应用及其本机数据，检查设备存储后重试；如需进一步排查，可联系设备维护人员。现有备份可以在另一台设备建立工作区后导入。',
              style: TextStyle(height: 1.7),
            ),
          ),
        ],
        const SizedBox(height: 22),
        const Text(
          '卸载应用或清除应用数据会删除本机账户、记录和保留的原件。',
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
      ],
    );
  }
}

class StorageRecoveryPage extends StatelessWidget {
  const StorageRecoveryPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DetailScaffold(
      title: '从备份恢复工作区',
      actions: [
        IconButton(
          tooltip: '退出恢复验证',
          icon: const Icon(Icons.lock_outline),
          onPressed: () => s.lock(),
        ),
      ],
      children: [
        const PageHeading(
          eyebrow: 'RECOVERY / BACKUP',
          title: '选择可用的备份。',
          subtitle: '先检查文件，再确认恢复。',
        ),
        GlassPanel(
          child: Column(
            children: [
              InfoRow('已验证管理员', s.recoveryUser?.name ?? '验证已过期'),
              const InfoRow('账户与密码', '保留现有本机账户'),
              const InfoRow('恢复前原件', '成功恢复时自动保留'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const GlassPanel(
          child: Text(
            '当前工作区无法完整读取，不能可靠比较新旧内容。恢复以所选备份为准，备份之后的变更和损坏数据不会自动合并。旧还原点与备份回执会转入恢复前原件，可在恢复后导出排查。',
            style: TextStyle(height: 1.7),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '原件保留与新工作区写入会一起完成。空间不足或写入失败时，原数据库保持恢复前的状态。恢复验证离开应用 30 秒后自动锁定。',
          style: TextStyle(height: 1.7),
        ),
        const SizedBox(height: 24),
        BusyButton(
          label: '选择恢复备份',
          icon: Icons.file_open_outlined,
          onPressed: () async {
            final expected = s.session;
            s.requireStorageRecovery(expected);
            final picked = await FilePicker.platform.pickFiles(
              type: FileType.any,
              withData: false,
            );
            s.requireStorageRecovery(expected);
            if (picked == null) return;
            final file = picked.files.single;
            if (file.size > maxArchiveBytes) {
              throw const FormatException('备份不能超过 256 MB');
            }
            if (file.path == null) {
              throw const FormatException('无法读取此文件，请选择本机文件');
            }
            if (!context.mounted) return;
            openPage(
              context,
              BackupImportPage(
                path: file.path!,
                name: file.name,
                session: expected,
                storageRecovery: true,
                previewBuilder: (document) => StorageRecoveryPreviewPage(
                  document: document,
                  fileName: file.name,
                  session: expected,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

BackupDocument _interpretRecoveryTime((BackupDocument, String) input) =>
    input.$1.resolveLegacyTimes(
      input.$2 == 'local'
          ? const LegacyTimeChoice.local()
          : LegacyTimeChoice.fixed(int.parse(input.$2)),
    );

class StorageRecoveryPreviewPage extends StatefulWidget {
  final BackupDocument document;
  final String fileName;
  final int session;
  const StorageRecoveryPreviewPage({
    super.key,
    required this.document,
    required this.fileName,
    required this.session,
  });
  @override
  State<StorageRecoveryPreviewPage> createState() =>
      _StorageRecoveryPreviewPageState();
}

class _StorageRecoveryPreviewPageState
    extends State<StorageRecoveryPreviewPage> {
  late BackupDocument document = widget.document;
  bool acknowledged = false, resolving = false;
  String? selectedTime, error;
  int generation = 0;
  Future<void> chooseTime(String value) async {
    final current = ++generation;
    setState(() {
      resolving = true;
      acknowledged = false;
      selectedTime = value;
      error = null;
    });
    try {
      final result = await compute(_interpretRecoveryTime, (
        widget.document,
        value,
      ));
      if (!mounted || current != generation) return;
      AppScope.of(context).requireStorageRecovery(widget.session);
      setState(() => document = result);
    } catch (e) {
      if (mounted && current == generation) {
        setState(
          () => error = e is FormatException ? e.message : '无法解释旧时间，请重新选择。',
        );
      }
    } finally {
      if (mounted && current == generation) setState(() => resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), w = document.workspace;
    final valid = document.readyToRestore && !resolving && error == null;
    return DetailScaffold(
      title: '异常恢复确认',
      children: [
        const PageHeading(
          eyebrow: 'RECOVERY / CONFIRM',
          title: '确认恢复的内容。',
          subtitle: '原始存储将保留，业务数据以此备份为准。',
        ),
        GlassPanel(
          child: Column(
            children: [
              InfoRow('备份文件', widget.fileName),
              InfoRow('文件大小', fileSize(document.bytes)),
              InfoRow('格式', document.format),
              InfoRow(
                '导出时间',
                !valid
                    ? '等待时间解释'
                    : document.exportedAt == null
                    ? '旧备份未记录'
                    : zonedStamp(document.exportedAt!),
              ),
              if (document.checksum != null)
                const InfoRow('完整性校验', 'SHA-256 通过'),
              InfoRow('检测记录', '${w.inspections.length} 条（含归档）'),
              InfoRow('操作日志', '${w.audits.length} 条'),
              InfoRow('工位 / 配方', '${w.stations.length} / ${w.recipes.length}'),
            ],
          ),
        ),
        if (document.legacyTimeCount > 0) ...[
          const SectionHeading('解释旧备份时间'),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${document.legacyTimeCount} 个时间没有时区。请选择原设备的记录规则。'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedTime,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '来源时间解释'),
                  items: [
                    const DropdownMenuItem(
                      value: 'local',
                      child: Text('本机时区历史规则'),
                    ),
                    for (final offset in [
                      480,
                      0,
                      for (var m = -720; m <= 840; m += 15)
                        if (m != 480 && m != 0) m,
                    ])
                      DropdownMenuItem(
                        value: '$offset',
                        child: Text('固定 ${utcOffsetLabel(offset)}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) chooseTime(v);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  '固定偏移不会切换夏令时。来源跨夏令时时，请在对应时区设备选择历史规则；重复钟表时间需人工核对。中国标准时间可选 UTC+08:00。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
                if (resolving) const LinearProgressIndicator(),
                if (error != null)
                  Text(error!, style: const TextStyle(color: red)),
                if (valid && document.legacyExample != null) ...[
                  InfoRow('原始时间', document.legacyExample!),
                  InfoRow(
                    '本地时间',
                    zonedStamp(document.interpretedExample!, precise: true),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SectionHeading('恢复后会怎样'),
        const GlassPanel(
          child: Text(
            '保留本机账户、密码和角色。能读取的外观设置与时间升级原件继续保留；旧还原点、备份回执及其余原始存储进入恢复前原件。无法读取的旧日志不会合并到新工作区。恢复完成后需要重新登录。',
            style: TextStyle(height: 1.7),
          ),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('已确认备份内容、时间解释和恢复影响'),
          value: acknowledged,
          onChanged: valid
              ? (v) => setState(() => acknowledged = v ?? false)
              : null,
        ),
        const SizedBox(height: 18),
        BusyButton(
          label: '保留原件并恢复',
          icon: Icons.restore_rounded,
          onPressed: !valid || !acknowledged
              ? null
              : () async {
                  s.requireStorageRecovery(widget.session);
                  final accepted = await confirm(
                    context,
                    '恢复工作区？',
                    '将保留当前原始存储，并使用此备份建立可读取的工作区。备份之后的变更不会自动恢复。',
                    confirmLabel: '恢复工作区',
                  );
                  if (!accepted) return;
                  await s.recoverStorage(
                    document,
                    expectedSession: widget.session,
                    fileName: widget.fileName,
                    acknowledged: acknowledged,
                  );
                },
        ),
      ],
    );
  }
}

class RecoveryHistoryPage extends StatefulWidget {
  const RecoveryHistoryPage({super.key});
  @override
  State<RecoveryHistoryPage> createState() => _RecoveryHistoryPageState();
}

class _RecoveryHistoryPageState extends State<RecoveryHistoryPage> {
  Future<List<RecoverySnapshot>>? history;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    history ??= AppScope.of(context).recoveryHistory();
  }

  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: '异常恢复记录',
    children: [
      const PageHeading(
        eyebrow: 'RECOVERY / HISTORY',
        title: '恢复过程，有据可查。',
        subtitle: '恢复前原件保留在本机，可单独导出排查。',
      ),
      const GlassPanel(
        child: Text(
          '原件包含恢复前的原始业务存储与设置，可能含损坏内容；它不是可以直接恢复的业务备份。导出不包含账户密码和恢复码。卸载或清除应用数据会删除本机保留的原件。',
          style: TextStyle(height: 1.7),
        ),
      ),
      const SizedBox(height: 20),
      FutureBuilder<List<RecoverySnapshot>>(
        future: history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const EmptyState(
              title: '无法读取恢复记录',
              subtitle: '请返回重试，或检查本机存储空间。',
            );
          }
          if (snapshot.data!.isEmpty) {
            return const EmptyState(
              title: '暂无异常恢复记录',
              subtitle: '工作区正常打开时，请使用常规备份与恢复。',
            );
          }
          return Column(
            children: [
              for (final item in snapshot.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: GlassPanel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: Text(item.sourceName),
                      subtitle: Text(
                        '${zonedStamp(item.createdAt)}\n${item.actor} · 恢复 ${item.records} 条记录 · 原件 ${fileSize(item.bytes)}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openPage(
                        context,
                        RecoveryOriginalPage(snapshot: item),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class RecoveryOriginalPage extends StatefulWidget {
  final RecoverySnapshot snapshot;
  const RecoveryOriginalPage({super.key, required this.snapshot});
  @override
  State<RecoveryOriginalPage> createState() => _RecoveryOriginalPageState();
}

class _RecoveryOriginalPageState extends State<RecoveryOriginalPage> {
  bool busy = false, cancelled = false, saving = false;
  BackupProgress progress = const BackupProgress('准备中…', 0, 0);
  @override
  void dispose() {
    cancelled = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.snapshot;
    return DetailScaffold(
      title: '恢复前原件',
      children: [
        const PageHeading(
          eyebrow: 'RECOVERY / ORIGINAL',
          title: '保留最初的内容。',
          subtitle: '导出原件供排查，不会覆盖当前工作区。',
        ),
        GlassPanel(
          child: Column(
            children: [
              InfoRow('恢复时间', zonedStamp(item.createdAt, precise: true)),
              InfoRow('管理员', item.actor),
              InfoRow('使用的备份', item.sourceName),
              InfoRow('恢复记录数', '${item.records} 条'),
              InfoRow('原始内容大小', fileSize(item.bytes)),
              InfoRow('恢复编号', item.id),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '导出为 LSR 排查文件，保存后会回读校验。文件未加密，包含原始业务内容及设置，不能作为 LSB / JSON 备份导入。分段编码会使文件大于原始内容，导出文件上限为 256 MB。',
          style: TextStyle(height: 1.7),
        ),
        const SizedBox(height: 24),
        if (busy) ...[
          if (saving)
            const GlassPanel(
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 14),
                  Expanded(child: Text('等待保存并回读校验…')),
                ],
              ),
            )
          else
            TransferProgress(progress: progress),
          if (!saving)
            OutlinedButton(
              onPressed: () => setState(() => cancelled = true),
              child: const Text('取消准备'),
            ),
        ] else
          BusyButton(
            label: '导出恢复前原件',
            icon: Icons.save_alt_rounded,
            onPressed: () async {
              setState(() {
                busy = true;
                cancelled = false;
                saving = false;
                progress = const BackupProgress('准备中…', 0, 0);
              });
              try {
                await exportRecoveryOriginal(
                  context,
                  item,
                  cancelled: () => cancelled,
                  onProgress: (message, fraction, bytes) {
                    if (mounted) {
                      setState(
                        () =>
                            progress = BackupProgress(message, fraction, bytes),
                      );
                    }
                  },
                  onSaving: () {
                    if (mounted) setState(() => saving = true);
                  },
                );
              } catch (e) {
                if (context.mounted) {
                  toast(
                    context,
                    e is StateError
                        ? e.message.toString()
                        : '原件导出未完成，请检查存储空间后重试。',
                  );
                }
              } finally {
                if (mounted) setState(() => busy = false);
              }
            },
          ),
      ],
    );
  }
}

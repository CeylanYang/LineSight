import 'backup_transfer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../backup.dart';
import 'restore.dart';
import '../ui.dart';
import '../files.dart';
import 'auth.dart';
import 'audit.dart';
import 'modules.dart';
import 'storage_recovery.dart';
import 'csv_export.dart';

export 'audit.dart' show AuditPage;
export 'restore.dart' show RestorePreviewPage;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), u = s.user;
    if (u == null) return const SizedBox.shrink();
    return PageBody(
      children: [
        const PageHeading(
          eyebrow: 'PERSONAL / WORKSPACE',
          title: '你的工作区。',
          subtitle: '管理账户、数据，以及适合你的使用方式。',
        ),
        GlassPanel(
          child: Row(
            children: [
              CircleAvatar(
                radius: 31,
                backgroundColor: blue.withValues(alpha: .12),
                child: Text(
                  u.name.characters.first,
                  style: const TextStyle(
                    color: blue,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 5),
                    Text(
                      '@${u.username}',
                      style: const TextStyle(color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 10),
                    Tag(roleName(u.role), color: green),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编辑个人资料',
                onPressed: () => openPage(context, const AccountPage()),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
        const SectionHeading('账户与安全'),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingsTile(
                icon: Icons.manage_accounts_outlined,
                title: '个人资料与密码',
                subtitle: '修改显示名称、更新本机密码',
                onTap: () => openPage(context, const AccountPage()),
              ),
              const Divider(),
              if (s.admin) ...[
                SettingsTile(
                  icon: Icons.group_outlined,
                  title: '成员与权限',
                  subtitle: '${s.users.length} 个本机账户',
                  onTap: () => openPage(context, const MembersPage()),
                ),
                const Divider(),
              ],
              SettingsTile(
                icon: Icons.history_rounded,
                title: '操作日志',
                subtitle: '查看登录、检测、复核与配置变更',
                onTap: () => openPage(context, const AuditPage()),
              ),
            ],
          ),
        ),
        const SectionHeading('工作区管理'),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingsTile(
                icon: Icons.storage_outlined,
                title: '数据管理',
                subtitle: '导出、备份、恢复与示例数据',
                onTap: () => openPage(context, const DataPage()),
              ),
              const Divider(),
              SettingsTile(
                icon: Icons.monitor_heart_outlined,
                title: '系统状态',
                subtitle: '检查本机数据库与数据完整性',
                onTap: () => openPage(
                  context,
                  const DetailScaffold(
                    title: '系统状态',
                    children: [SystemPanel()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SectionHeading('外观与交互'),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined, color: blue),
                title: const Text('深色模式'),
                value: s.dark,
                onChanged: (v) =>
                    perform(context, () => s.preference('dark', v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.blur_on_rounded, color: blue),
                title: const Text('通透玻璃'),
                subtitle: const Text('半透明面板与背景模糊'),
                value: s.glass,
                onChanged: (v) =>
                    perform(context, () => s.preference('glass', v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration_rounded, color: blue),
                title: const Text('触觉反馈'),
                subtitle: const Text('导航与保存时的轻微反馈'),
                value: s.haptics,
                onChanged: (v) =>
                    perform(context, () => s.preference('haptics', v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.animation_rounded, color: blue),
                title: const Text('减少动态效果'),
                value: s.reduceMotion,
                onChanged: (v) =>
                    perform(context, () => s.preference('reduceMotion', v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.lock_clock_outlined, color: blue),
                title: const Text('离开后自动锁定'),
                subtitle: const Text('进入后台超过 30 秒后需重新登录'),
                value: s.autoLock,
                onChanged: (v) =>
                    perform(context, () => s.preference('autoLock', v)),
              ),
            ],
          ),
        ),
        const SectionHeading('帮助'),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: SettingsTile(
            icon: Icons.help_outline_rounded,
            title: '使用指南与关于',
            subtitle: '了解操作流程和示例环境',
            onTap: () => openPage(context, const HelpPage()),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => s.lock(),
                icon: const Icon(Icons.lock_outline),
                label: const Text('立即锁定'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => perform(context, () async {
                  if (await confirm(
                    context,
                    '退出本机账户？',
                    '检测数据、配置和操作日志会保留在此设备。',
                    confirmLabel: '退出',
                  )) {
                    await s.signOut();
                  }
                }),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('退出登录'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const Center(
          child: Text(
            'LineSight $appVersion · 离线工作区',
            style: TextStyle(fontSize: 11, color: Colors.blueGrey),
          ),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
    leading: Icon(icon, color: blue),
    title: Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(subtitle, style: const TextStyle(fontSize: 12)),
    ),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final old = TextEditingController(),
      next = TextEditingController(),
      repeat = TextEditingController();
  @override
  void dispose() {
    old.dispose();
    next.dispose();
    repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), u = s.user;
    if (u == null) return const SizedBox.shrink();
    return DetailScaffold(
      title: '个人资料与密码',
      children: [
        GlassPanel(
          child: Column(
            children: [
              InfoRow('用户名', u.username),
              InfoRow('账户角色', roleName(u.role)),
              InfoRow('显示名称', u.name),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => perform(context, () async {
                    final value = await inputDialog(
                      context,
                      title: '修改显示名称',
                      initial: u.name,
                      label: '名称',
                      maxLength: 40,
                    );
                    if (value != null) await s.rename(value);
                  }),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('修改名称'),
                ),
              ),
            ],
          ),
        ),
        const SectionHeading('修改密码'),
        GlassPanel(
          child: AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: old,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '当前密码'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '新密码（至少 8 位）'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: repeat,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '再次输入新密码'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: BusyButton(
                    label: '更新密码',
                    icon: Icons.password_rounded,
                    onPressed: () async {
                      if (next.text != repeat.text) {
                        throw StateError('两次密码输入不一致');
                      }
                      await s.changePassword(old.text, next.text);
                      if (!context.mounted) return;
                      old.clear();
                      next.clear();
                      repeat.clear();
                      toast(context, '密码已更新');
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionHeading('我的权限'),
        GlassPanel(
          child: Column(
            children: [
              const InfoRow('查看与检测', '已允许'),
              InfoRow('复核与配方', s.engineer ? '已允许' : '需要工程师或管理员'),
              InfoRow('业务数据导出', s.engineer ? '已允许' : '需要工程师或管理员'),
              InfoRow('成员与恢复', s.admin ? '已允许' : '需要管理员'),
            ],
          ),
        ),
      ],
    );
  }
}

class MembersPage extends StatelessWidget {
  const MembersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DetailScaffold(
      title: '成员与权限',
      actions: [
        if (s.admin)
          IconButton(
            tooltip: '添加本机成员',
            onPressed: () => openPage(context, const CreateMemberPage()),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
      ],
      children: [
        const PageHeading(
          eyebrow: 'ACCESS / LOCAL TEAM',
          title: '各司其职，一起协作。',
          subtitle: '本机成员共享业务数据，操作以当前账户记入日志。',
        ),
        const GlassPanel(
          child: Column(
            children: [
              InfoRow('操作员', '查看记录、运行模拟检测、启动或暂停工位'),
              InfoRow('质量工程师', '增加复核、归档、配方管理与导出权限'),
              InfoRow('管理员', '增加成员管理、备份恢复和数据清理权限'),
            ],
          ),
        ),
        const SectionHeading('本机成员'),
        ...s.users.map(
          (u) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassPanel(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: blue.withValues(alpha: .1),
                  child: Text(u.name.characters.first),
                ),
                title: Text('${u.name}${u.id == s.user?.id ? '（我）' : ''}'),
                subtitle: Text(
                  '@${u.username} · ${roleName(u.role)} · ${u.enabled ? '已启用' : '已停用'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: s.admin ? () => showMemberEditor(context, u) : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showMemberEditor(BuildContext context, LocalUser u) async {
  final s = AppScope.of(context);
  String role = u.role;
  bool enabled = u.enabled;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text('管理 ${u.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: role,
              items: ['operator', 'engineer', 'admin']
                  .map(
                    (r) => DropdownMenuItem(value: r, child: Text(roleName(r))),
                  )
                  .toList(),
              onChanged: (v) => setState(() => role = v!),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('账户启用'),
              value: enabled,
              onChanged: (v) => setState(() => enabled = v),
            ),
            if (u.id == s.user?.id)
              const Text('不能停用自己或撤销自己的管理员权限。', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          BusyButton(
            label: '保存',
            icon: Icons.save_outlined,
            onPressed: () async {
              await s.updateUser(u, role, enabled);
              if (c.mounted) Navigator.pop(c);
            },
          ),
        ],
      ),
    ),
  );
}

class CreateMemberPage extends StatefulWidget {
  const CreateMemberPage({super.key});
  @override
  State<CreateMemberPage> createState() => _CreateMemberPageState();
}

class _CreateMemberPageState extends State<CreateMemberPage> {
  final username = TextEditingController(),
      name = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController();
  @override
  void dispose() {
    username.dispose();
    name.dispose();
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return DetailScaffold(
      title: '添加本机成员',
      children: [
        const PageHeading(
          eyebrow: 'ACCESS / NEW MEMBER',
          title: '欢迎新的搭档。',
          subtitle: '新账户默认拥有操作员权限，创建后可在成员列表调整。',
        ),
        GlassPanel(
          child: Column(
            children: [
              TextField(
                controller: username,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  helperText: '3–32 位字母、数字、点、横线或下划线',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: '显示名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '初始密码（至少 8 位）'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: repeat,
                obscureText: true,
                decoration: const InputDecoration(labelText: '再次输入密码'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        BusyButton(
          label: '创建成员',
          icon: Icons.person_add_alt_1,
          onPressed: !s.admin
              ? null
              : () async {
                  if (password.text != repeat.text) {
                    throw StateError('两次密码输入不一致');
                  }
                  final code = await s.register(
                    username.text,
                    name.text,
                    password.text,
                  );
                  if (!context.mounted) return;
                  await showRecoveryCode(context, code);
                  if (context.mounted) Navigator.pop(context);
                },
        ),
      ],
    );
  }
}

class DataPage extends StatelessWidget {
  const DataPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final samples = s.data.inspections.where((r) => r.sample).length;
    return DetailScaffold(
      title: '数据管理',
      children: [
        const PageHeading(
          eyebrow: 'DATA / LOCAL STORAGE',
          title: '数据在手，心中有数。',
          subtitle: '在本机保存和管理你的质量档案。',
        ),
        AdaptiveGrid(
          minWidth: 130,
          children: [
            Metric(
              label: '全部检测记录',
              value: '${s.data.inspections.length}',
              icon: Icons.storage_outlined,
            ),
            Metric(
              label: '已归档记录',
              value: '${s.data.inspections.where((r) => r.archived).length}',
              icon: Icons.archive_outlined,
              color: green,
            ),
          ],
        ),
        const SectionHeading('备份状态'),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    s.lastBackup == null
                        ? Icons.backup_outlined
                        : Icons.task_alt_rounded,
                    color: s.lastBackup == null ? amber : green,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.lastBackup == null ? '还没有本机备份保存记录' : '最近一次备份已保存',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (s.lastBackup != null) ...[
                InfoRow('保存时间', zonedStamp(s.lastBackup!.savedAt)),
                InfoRow('备份记录', '${s.lastBackup!.records} 条'),
                InfoRow('保存人', s.lastBackup!.actor),
                InfoRow('文件格式', s.lastBackup!.format),
                if (s.lastBackup!.bytes != null)
                  InfoRow('文件大小', fileSize(s.lastBackup!.bytes!)),
                if (s.lastBackup!.sha256 != null)
                  const InfoRow('保存校验', '目标文件回读通过'),
              ],
              const Text(
                '备份文件请保存在应用之外。开始备份之后的变更可能尚未备份；此处不会检查外部文件是否仍然存在。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
        const SectionHeading('时间与日期'),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: Text(
              s.timeArchives.isEmpty ? 'UTC 保存 · 本地时间显示' : '旧版时间已转换，原件已保留',
            ),
            subtitle: Text(s.timeArchives.isEmpty ? '查看时间规则' : '查看升级解释并导出旧版原件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPage(context, const TimeStoragePage()),
          ),
        ),
        const SectionHeading('导出与备份'),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '完整备份（LSB）支持最大 256 MB，保留全部记录与日志，并校验文件完整性。兼容 JSON 供旧版应用使用，最大 20 MB。CSV 时间列以 UTC 标注，用于表格分析。',
                style: TextStyle(height: 1.7),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  BusyButton(
                    label: '导出全部 CSV',
                    icon: Icons.table_chart_outlined,
                    onPressed: !s.engineer
                        ? null
                        : () async => openPage(
                            context,
                            CsvExportPage(
                              snapshot: s.captureCsv(s.data.inspections),
                              session: s.session,
                              scope: '全部检测记录',
                              filterSummary: '包含归档和示例记录 · 保持工作区排列顺序',
                            ),
                          ),
                  ),
                  BusyButton(
                    label: '保存完整备份',
                    icon: Icons.save_alt_rounded,
                    onPressed: !s.engineer
                        ? null
                        : () async =>
                              openPage(context, const BackupExportPage()),
                  ),
                ],
              ),
              if (!s.engineer) ...[
                const SizedBox(height: 12),
                const Text('需要工程师或管理员权限才能导出。'),
              ],
            ],
          ),
        ),
        if (s.admin) ...[
          const SectionHeading('异常恢复记录'),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: const Text('查看恢复记录与恢复前原件'),
              subtitle: const Text('管理员专用 · 导出保留的原始存储'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(context, const RecoveryHistoryPage()),
            ),
          ),
          const SectionHeading('恢复业务数据'),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择 LineSight LSB 或 JSON 备份，先校验并查看内容再恢复。恢复会替换当前业务数据，保留本机账户和现有操作日志。',
                  style: TextStyle(height: 1.7),
                ),
                const SizedBox(height: 20),
                BusyButton(
                  label: '选择备份文件',
                  icon: Icons.file_open_outlined,
                  onPressed: () async {
                    final startedSession = s.session;
                    s.requireSession(startedSession, owner: true);
                    final picked = await FilePicker.platform.pickFiles(
                      type: FileType.any,
                      allowMultiple: false,
                      withData: false,
                    );
                    s.requireSession(startedSession, owner: true);
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
                        session: startedSession,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (s.restorePoint == null)
                  const Text(
                    '尚无还原点。成功恢复备份后，会自动保留恢复前的数据。',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  )
                else ...[
                  InfoRow('还原点记录', '${s.restorePoint!.records} 条检测记录'),
                  InfoRow(
                    '创建时间',
                    s.restorePoint!.createdAt == null
                        ? '旧版未记录'
                        : zonedStamp(s.restorePoint!.createdAt!),
                  ),
                  InfoRow('创建人', s.restorePoint!.actor),
                  const SizedBox(height: 12),
                  BusyButton(
                    label: '查看还原点并撤回',
                    icon: Icons.undo_rounded,
                    onPressed: () async {
                      final point = s.restorePoint!;
                      final previous = await s.readRestorePoint(point.id);
                      if (!context.mounted) return;
                      openPage(
                        context,
                        RestorePreviewPage(
                          incoming: previous,
                          fileName: point.createdAt == null
                              ? '本机还原点'
                              : '${stamp(point.createdAt!.toLocal())} 的本机还原点',
                          pointId: point.id,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const SectionHeading('示例数据'),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前有 $samples 条示例 / 模拟记录。',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  '示例用于体验流程。清理时将删除带有示例标记的检测记录，包括在工位生成的模拟记录。',
                  style: TextStyle(height: 1.7),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    BusyButton(
                      label: '添加一组示例',
                      icon: Icons.auto_awesome_outlined,
                      onPressed: () async {
                        await s.loadExamples();
                        if (context.mounted) toast(context, '已添加 96 条示例记录');
                      },
                    ),
                    OutlinedButton.icon(
                      onPressed: samples == 0
                          ? null
                          : () => perform(context, () async {
                              if (await confirm(
                                context,
                                '清理所有示例记录？',
                                '将删除 $samples 条示例 / 模拟检测记录，包含已归档记录。配方、成员和操作日志会保留。',
                                confirmLabel: '清理示例',
                              )) {
                                await s.clearExamples();
                                if (context.mounted) toast(context, '示例记录已清理');
                              }
                            }),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('清理示例'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          '卸载应用会移除本机账户和数据。需要保留业务数据时，请先保存 JSON 备份，并单独妥善保存账户恢复码。',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.7),
        ),
      ],
    );
  }
}

class TimeStoragePage extends StatelessWidget {
  const TimeStoragePage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context), now = DateTime.now();
    return DetailScaffold(
      title: '时间与日期',
      children: [
        const PageHeading(
          eyebrow: 'DATA / TIME',
          title: '同一时刻，清楚记录。',
          subtitle: '记录按 UTC 保存，页面按设备本地时区显示。',
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                '设备当前时区',
                '${now.timeZoneName} · ${utcOffsetLabel(now.timeZoneOffset.inMinutes)}',
              ),
              const InfoRow('JSON / CSV', 'UTC 时间，末尾带 Z 标记'),
              const Text(
                '今天、日期筛选与每日统计使用本地日历边界。设备时区改变后，记录的显示时间和所属日期可能变化，记录代表的时刻保持不变。详情显示该时刻的 UTC 偏移。',
                style: TextStyle(height: 1.7),
              ),
            ],
          ),
        ),
        const SectionHeading('旧版时间兼容'),
        const Text(
          '旧版没有时区标记的时间无法反推出原始时区。导入时需要选择来源时间规则并确认预览。固定偏移不会自动切换夏令时。',
          style: TextStyle(height: 1.7),
        ),
        if (s.timeArchives.isEmpty) ...[
          const SizedBox(height: 12),
          const Text('本机没有需要转换的旧版时间原件。'),
        ],
        for (final archive in s.timeArchives.reversed) ...[
          const SizedBox(height: 18),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow('升级时间', zonedStamp(parseInstant(archive.capturedAt))),
                InfoRow(
                  '升级时设备时区',
                  '${archive.zoneName} · ${utcOffsetLabel(archive.offsetMinutes)}',
                ),
                InfoRow('已解释的旧时间', '${archive.count} 个'),
                const Text(
                  '升级按当时设备的历史时区规则解释旧时间；夏令时跳过的钟表时间沿用系统校正结果。上方偏移仅表示升级时刻；历史时间可能采用不同的夏令时偏移。原始工作区及旧还原点另行保留在本机，恢复操作不会覆盖这些原件。',
                  style: TextStyle(height: 1.7),
                ),
                const SizedBox(height: 12),
                const Text(
                  '如来源时区有误，可导出原件，再从数据管理选择该文件并重新解释时间。原件是升级时的快照，恢复前请先保存当前完整备份。相同 ID 的现有日志仍以本机日志为准。',
                  style: TextStyle(fontSize: 12, height: 1.7),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final key in ['workspace', 'restorePoint'])
                      if (archive.originals.containsKey(key))
                        BusyButton(
                          label: key == 'workspace' ? '导出工作区原件' : '导出旧还原点原件',
                          icon: Icons.save_alt_rounded,
                          onPressed: !s.engineer
                              ? null
                              : () => exportTimeOriginal(context, archive, key),
                        ),
                  ],
                ),
                if (!s.engineer) const Text('需要工程师或管理员权限才能导出。'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext context) => const DetailScaffold(
    title: '使用指南与关于',
    children: [
      BrandMark(size: 64),
      SizedBox(height: 22),
      PageHeading(
        eyebrow: 'LINESIGHT / $appVersion',
        title: '让质量，有迹可循。',
        subtitle: '面向产线检测的本机工作区。',
      ),
      GlassPanel(
        child: Column(
          children: [
            ExpansionTile(
              title: Text('01  开始一次检测'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '在工作台选择工位，确认当前配方，启动工位后点击「模拟检测」。检测结果与配方快照会自动保存。目前所有画面与检测均为模拟。',
                    style: TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text('02  处理异常与复核'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '从异常待办或检测记录打开详情，查看缺陷与置信度。工程师和管理员可填写复核依据并放行或判退。原始结果保留，每次复核变更写入日志。',
                    style: TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text('03  配方与换型'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '在配方中心新增、编辑或复制配方。换型时选择工位、目标配方并填写原因。新配置只影响后续检测，历史快照保持不变。正在使用的配方不能删除。',
                    style: TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text('04  管理数据与备份'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '记录支持搜索、日期范围、工位和判定筛选。已处理的记录可归档并恢复。CSV 可用于分析；JSON 可恢复业务数据。账户不随备份迁移，恢复前自动保留一个还原点。',
                    style: TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text('05  账户与恢复码'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '首个账户为管理员。管理员可添加成员、设置角色或停用账户。登录连续失败会触发短暂锁定。忘记密码时使用创建账户时保存的恢复码。每次冷启动都需登录。',
                    style: TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text('06  本机数据与隐私'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '账户与检测数据保存在应用的本机数据库中，密码经过加盐派生处理。应用没有云账户和同步服务。业务备份为明文 JSON，请选择合适的保存位置。示例记录始终有标记。',
                    style: TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      SizedBox(height: 24),
      Text(
        'LineSight · Production-line inspection workspace\nFlutter / Material 3\nMade for the shop floor.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, height: 1.8, color: Colors.blueGrey),
      ),
    ],
  );
}

import '../l10n.dart';
import '../editions/edition_host.dart';
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
import '../language_selector.dart';
import 'team_workspace.dart';
import 'app_updates.dart';

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
        PageHeading(
          eyebrow: tr(context, "账户设置"),
          title: tr(context, "你的工作区。"),
          subtitle: tr(context, "管理账户、数据，以及适合你的使用方式。"),
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
                    Tag(tr(context, roleName(u.role)), color: green),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr(context, "编辑个人资料"),
                onPressed: () => openPage(context, const AccountPage()),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: SettingsTile(
            key: const ValueKey('language-settings'),
            icon: Icons.language_rounded,
            title: '语言 / Language',
            subtitle: s.languageCode == 'en' ? 'English' : '中文',
            onTap: () => chooseLanguage(context),
          ),
        ),
        SectionHeading(tr(context, "账户与安全")),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: SettingsTile(
            icon: Icons.system_update_outlined,
            title: tr(context, '应用更新'),
            subtitle: tr(context, '自动下载更新，下次启动生效。'),
            onTap: () => openPage(context, const AppUpdatesPage()),
          ),
        ),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingsTile(
                icon: Icons.manage_accounts_outlined,
                title: tr(context, "个人资料与密码"),
                subtitle: tr(context, "修改显示名称、更新本机密码"),
                onTap: () => openPage(context, const AccountPage()),
              ),
              const Divider(),
              if (s.admin) ...[
                SettingsTile(
                  icon: Icons.group_outlined,
                  title: tr(context, "成员与权限"),
                  subtitle: tr(context, "{0} 个本机账户", [s.users.length]),
                  onTap: () => openPage(context, const MembersPage()),
                ),
                const Divider(),
              ],
              SettingsTile(
                icon: Icons.history_rounded,
                title: tr(context, "操作日志"),
                subtitle: tr(context, "查看登录、检测、复核与配置变更"),
                onTap: () => openPage(context, const AuditPage()),
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "工作区管理")),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SettingsTile(
                icon: Icons.groups_outlined,
                title: tr(context, "团队协作"),
                subtitle: tr(context, "连接团队工作区、管理共享任务与成员邀请"),
                onTap: () => openPage(context, const TeamWorkspacePage()),
              ),
              const Divider(),
              SettingsTile(
                icon: Icons.storage_outlined,
                title: tr(context, "数据管理"),
                subtitle: tr(context, "导出、备份、恢复与示例数据"),
                onTap: () => openPage(context, const DataPage()),
              ),
              const Divider(),
              SettingsTile(
                icon: Icons.monitor_heart_outlined,
                title: tr(context, "系统状态"),
                subtitle: tr(context, "检查本机数据库与数据完整性"),
                onTap: () => openPage(
                  context,
                  DetailScaffold(
                    title: tr(context, "系统状态"),
                    children: const [SystemPanel()],
                  ),
                ),
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "外观与交互")),
        const GlassPanel(padding: EdgeInsets.zero, child: EditionSwitch()),
        GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.vibration_rounded, color: blue),
                title: Text(tr(context, "触觉反馈")),
                subtitle: Text(tr(context, "导航与保存时的轻微反馈")),
                value: s.haptics,
                onChanged: (v) =>
                    perform(context, () => s.preference('haptics', v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.animation_rounded, color: blue),
                title: Text(tr(context, "减少动态效果")),
                value: s.reduceMotion,
                onChanged: (v) =>
                    perform(context, () => s.preference('reduceMotion', v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.lock_clock_outlined, color: blue),
                title: Text(tr(context, "离开后自动锁定")),
                subtitle: Text(tr(context, "进入后台超过 30 秒后需重新登录")),
                value: s.autoLock,
                onChanged: (v) =>
                    perform(context, () => s.preference('autoLock', v)),
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "帮助")),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: SettingsTile(
            icon: Icons.help_outline_rounded,
            title: tr(context, "使用说明与应用信息"),
            subtitle: tr(context, "查看工作流程和功能说明"),
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
                label: Text(tr(context, "立即锁定")),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => perform(context, () async {
                  if (await confirm(
                    context,
                    tr(context, "退出本机账户？"),
                    tr(context, "检测数据、配置和操作日志会保留在此设备。"),
                    confirmLabel: tr(context, "退出"),
                  )) {
                    await s.signOut();
                  }
                }),
                icon: const Icon(Icons.logout_rounded),
                label: Text(tr(context, "退出登录")),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Center(
          child: Text(
            tr(context, "LineSight {0} · 质量工作台", [appVersion]),
            style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
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
      title: tr(context, "个人资料与密码"),
      children: [
        GlassPanel(
          child: Column(
            children: [
              InfoRow(tr(context, "用户名"), u.username),
              InfoRow(tr(context, "账户角色"), tr(context, roleName(u.role))),
              InfoRow(tr(context, "显示名称"), u.name),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => perform(context, () async {
                    final value = await inputDialog(
                      context,
                      title: tr(context, "修改显示名称"),
                      initial: u.name,
                      label: tr(context, "名称"),
                      maxLength: 40,
                    );
                    if (value != null) await s.rename(value);
                  }),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(tr(context, "修改名称")),
                ),
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "修改密码")),
        GlassPanel(
          child: AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: old,
                  obscureText: true,
                  decoration: InputDecoration(labelText: tr(context, "当前密码")),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: next,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: tr(context, "新密码（至少 8 位）"),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: repeat,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: tr(context, "再次输入新密码"),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: BusyButton(
                    label: tr(context, "更新密码"),
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
                      toast(context, tr(context, "密码已更新"));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionHeading(tr(context, "我的权限")),
        GlassPanel(
          child: Column(
            children: [
              InfoRow(tr(context, "查看与检测"), tr(context, "已允许")),
              InfoRow(
                tr(context, "复核与配方"),
                s.engineer ? tr(context, "已允许") : tr(context, "需要工程师或管理员"),
              ),
              InfoRow(
                tr(context, "业务数据导出"),
                s.engineer ? tr(context, "已允许") : tr(context, "需要工程师或管理员"),
              ),
              InfoRow(
                tr(context, "成员与恢复"),
                s.admin ? tr(context, "已允许") : tr(context, "需要管理员"),
              ),
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
      title: tr(context, "成员与权限"),
      actions: [
        if (s.admin)
          IconButton(
            tooltip: tr(context, "添加本机成员"),
            onPressed: () => openPage(context, const CreateMemberPage()),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
      ],
      children: [
        PageHeading(
          eyebrow: 'ACCESS / LOCAL TEAM',
          title: tr(context, "各司其职，一起协作。"),
          subtitle: tr(context, "本机成员共享业务数据，操作以当前账户记入日志。"),
        ),
        GlassPanel(
          child: Column(
            children: [
              InfoRow(tr(context, "操作员"), tr(context, "查看记录、运行检测、启动或暂停工位")),
              InfoRow(tr(context, "质量工程师"), tr(context, "增加复核、归档、配方管理与导出权限")),
              InfoRow(tr(context, "管理员"), tr(context, "增加成员管理、备份恢复和数据清理权限")),
            ],
          ),
        ),
        SectionHeading(tr(context, "本机成员")),
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
                title: Text(
                  '${u.name}${u.id == s.user?.id ? tr(context, "（我）") : ''}',
                ),
                subtitle: Text(
                  '@${u.username} · ${tr(context, roleName(u.role))} · ${u.enabled ? tr(context, "已启用") : tr(context, "已停用")}',
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
        title: Text(tr(context, "管理 {0}", [u.name])),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: role,
              items: ['operator', 'engineer', 'admin']
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(tr(context, roleName(r))),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => role = v!),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, "账户启用")),
              value: enabled,
              onChanged: (v) => setState(() => enabled = v),
            ),
            if (u.id == s.user?.id)
              Text(
                tr(context, "不能停用自己或撤销自己的管理员权限。"),
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr(context, "取消")),
          ),
          BusyButton(
            label: tr(context, "保存"),
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
      title: tr(context, "添加本机成员"),
      children: [
        PageHeading(
          eyebrow: 'ACCESS / NEW MEMBER',
          title: tr(context, "欢迎新的搭档。"),
          subtitle: tr(context, "新账户默认拥有操作员权限，创建后可在成员列表调整。"),
        ),
        GlassPanel(
          child: Column(
            children: [
              TextField(
                controller: username,
                decoration: InputDecoration(
                  labelText: tr(context, "用户名"),
                  helperText: tr(context, "3–32 位字母、数字、点、横线或下划线"),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                maxLength: 40,
                decoration: InputDecoration(labelText: tr(context, "显示名称")),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr(context, "初始密码（至少 8 位）"),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: repeat,
                obscureText: true,
                decoration: InputDecoration(labelText: tr(context, "再次输入密码")),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        BusyButton(
          label: tr(context, "创建成员"),
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
      title: tr(context, "数据管理"),
      children: [
        PageHeading(
          eyebrow: 'DATA / LOCAL STORAGE',
          title: tr(context, "数据在手，心中有数。"),
          subtitle: tr(context, "在本机保存和管理你的质量档案。"),
        ),
        AdaptiveGrid(
          minWidth: 130,
          children: [
            Metric(
              label: tr(context, "全部检测记录"),
              value: '${s.data.inspections.length}',
              icon: Icons.storage_outlined,
            ),
            Metric(
              label: tr(context, "已归档记录"),
              value: '${s.data.inspections.where((r) => r.archived).length}',
              icon: Icons.archive_outlined,
              color: green,
            ),
          ],
        ),
        SectionHeading(tr(context, "备份状态")),
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
                      s.lastBackup == null
                          ? tr(context, "还没有本机备份保存记录")
                          : tr(context, "最近一次备份已保存"),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (s.lastBackup != null) ...[
                InfoRow(tr(context, "保存时间"), zonedStamp(s.lastBackup!.savedAt)),
                InfoRow(
                  tr(context, "备份记录"),
                  tr(context, "{0} 条", [s.lastBackup!.records]),
                ),
                InfoRow(tr(context, "保存人"), s.lastBackup!.actor),
                InfoRow(tr(context, "文件格式"), s.lastBackup!.format),
                if (s.lastBackup!.bytes != null)
                  InfoRow(tr(context, "文件大小"), fileSize(s.lastBackup!.bytes!)),
                if (s.lastBackup!.sha256 != null)
                  InfoRow(tr(context, "保存校验"), tr(context, "目标文件回读通过")),
              ],
              Text(
                tr(context, "备份文件请保存在应用之外。开始备份之后的变更可能尚未备份；此处不会检查外部文件是否仍然存在。"),
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "时间与日期")),
        GlassPanel(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: Text(
              s.timeArchives.isEmpty
                  ? tr(context, "UTC 保存 · 本地时间显示")
                  : tr(context, "旧版时间已转换，原件已保留"),
            ),
            subtitle: Text(
              s.timeArchives.isEmpty
                  ? tr(context, "查看时间规则")
                  : tr(context, "查看升级解释并导出旧版原件"),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPage(context, const TimeStoragePage()),
          ),
        ),
        SectionHeading(tr(context, "导出与备份")),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  context,
                  "完整备份（LSB）支持最大 256 MB，保留全部记录与日志，并校验文件完整性。兼容 JSON 供旧版应用使用，最大 20 MB。CSV 时间列以 UTC 标注，用于表格分析。",
                ),
                style: const TextStyle(height: 1.7),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  BusyButton(
                    label: tr(context, "导出全部 CSV"),
                    icon: Icons.table_chart_outlined,
                    onPressed: !s.engineer
                        ? null
                        : () async => openPage(
                            context,
                            CsvExportPage(
                              snapshot: s.captureCsv(s.data.inspections),
                              session: s.session,
                              scope: tr(context, "全部检测记录"),
                              filterSummary: tr(
                                context,
                                "包含归档和示例记录 · 保持工作区排列顺序",
                              ),
                            ),
                          ),
                  ),
                  BusyButton(
                    label: tr(context, "保存完整备份"),
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
                Text(tr(context, "需要工程师或管理员权限才能导出。")),
              ],
            ],
          ),
        ),
        if (s.admin) ...[
          SectionHeading(tr(context, "异常恢复记录")),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: Text(tr(context, "查看恢复记录与恢复前原件")),
              subtitle: Text(tr(context, "管理员专用 · 导出保留的原始存储")),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(context, const RecoveryHistoryPage()),
            ),
          ),
          SectionHeading(tr(context, "恢复业务数据")),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    context,
                    "选择 LineSight LSB 或 JSON 备份，先校验并查看内容再恢复。恢复会替换当前业务数据，保留本机账户和现有操作日志。",
                  ),
                  style: const TextStyle(height: 1.7),
                ),
                const SizedBox(height: 20),
                BusyButton(
                  label: tr(context, "选择备份文件"),
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
                  Text(
                    tr(context, "尚无还原点。成功恢复备份后，会自动保留恢复前的数据。"),
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  )
                else ...[
                  InfoRow(
                    tr(context, "还原点记录"),
                    tr(context, "{0} 条检测记录", [s.restorePoint!.records]),
                  ),
                  InfoRow(
                    tr(context, "创建时间"),
                    s.restorePoint!.createdAt == null
                        ? tr(context, "旧版未记录")
                        : zonedStamp(s.restorePoint!.createdAt!),
                  ),
                  InfoRow(tr(context, "创建人"), s.restorePoint!.actor),
                  const SizedBox(height: 12),
                  BusyButton(
                    label: tr(context, "查看还原点并撤回"),
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
                              ? tr(context, "本机还原点")
                              : tr(context, "{0} 的本机还原点", [
                                  stamp(point.createdAt!.toLocal()),
                                ]),
                          pointId: point.id,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          SectionHeading(tr(context, "示例数据")),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, "当前有 {0} 条示例记录。", [samples]),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  tr(context, "示例记录带有标记。清理时会移除所有标记为示例的检测记录。"),
                  style: const TextStyle(height: 1.7),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    BusyButton(
                      label: tr(context, "添加一组示例"),
                      icon: Icons.auto_awesome_outlined,
                      onPressed: () async {
                        await s.loadExamples();
                        if (context.mounted) {
                          toast(context, tr(context, "已添加 96 条示例记录"));
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      onPressed: samples == 0
                          ? null
                          : () => perform(context, () async {
                              if (await confirm(
                                context,
                                tr(context, "清理所有示例记录？"),
                                tr(
                                  context,
                                  "将删除 {0} 条示例记录，包含已归档记录。配方、成员和操作日志会保留。",
                                  [samples],
                                ),
                                confirmLabel: tr(context, "清理示例"),
                              )) {
                                await s.clearExamples();
                                if (context.mounted) {
                                  toast(context, tr(context, "示例记录已清理"));
                                }
                              }
                            }),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: Text(tr(context, "清理示例")),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          tr(context, "卸载应用会移除本机账户和数据。需要保留业务数据时，请先保存 JSON 备份，并单独妥善保存账户恢复码。"),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.blueGrey,
            height: 1.7,
          ),
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
      title: tr(context, "时间与日期"),
      children: [
        PageHeading(
          eyebrow: 'DATA / TIME',
          title: tr(context, "同一时刻，清楚记录。"),
          subtitle: tr(context, "记录按 UTC 保存，页面按设备本地时区显示。"),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                tr(context, "设备当前时区"),
                '${now.timeZoneName} · ${utcOffsetLabel(now.timeZoneOffset.inMinutes)}',
              ),
              InfoRow('JSON / CSV', tr(context, "UTC 时间，末尾带 Z 标记")),
              Text(
                tr(
                  context,
                  "今天、日期筛选与每日统计使用本地日历边界。设备时区改变后，记录的显示时间和所属日期可能变化，记录代表的时刻保持不变。详情显示该时刻的 UTC 偏移。",
                ),
                style: const TextStyle(height: 1.7),
              ),
            ],
          ),
        ),
        SectionHeading(tr(context, "旧版时间兼容")),
        Text(
          tr(context, "旧版没有时区标记的时间无法反推出原始时区。导入时需要选择来源时间规则并确认预览。固定偏移不会自动切换夏令时。"),
          style: const TextStyle(height: 1.7),
        ),
        if (s.timeArchives.isEmpty) ...[
          const SizedBox(height: 12),
          Text(tr(context, "本机没有需要转换的旧版时间原件。")),
        ],
        for (final archive in s.timeArchives.reversed) ...[
          const SizedBox(height: 18),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                  tr(context, "升级时间"),
                  zonedStamp(parseInstant(archive.capturedAt)),
                ),
                InfoRow(
                  tr(context, "升级时设备时区"),
                  '${archive.zoneName} · ${utcOffsetLabel(archive.offsetMinutes)}',
                ),
                InfoRow(
                  tr(context, "已解释的旧时间"),
                  tr(context, "{0} 个", [archive.count]),
                ),
                Text(
                  tr(
                    context,
                    "升级按当时设备的历史时区规则解释旧时间；夏令时跳过的钟表时间沿用系统校正结果。上方偏移仅表示升级时刻；历史时间可能采用不同的夏令时偏移。原始工作区及旧还原点另行保留在本机，恢复操作不会覆盖这些原件。",
                  ),
                  style: const TextStyle(height: 1.7),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    context,
                    "如来源时区有误，可导出原件，再从数据管理选择该文件并重新解释时间。原件是升级时的快照，恢复前请先保存当前完整备份。相同 ID 的现有日志仍以本机日志为准。",
                  ),
                  style: const TextStyle(fontSize: 12, height: 1.7),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final key in ['workspace', 'restorePoint'])
                      if (archive.originals.containsKey(key))
                        BusyButton(
                          label: key == 'workspace'
                              ? tr(context, "导出工作区原件")
                              : tr(context, "导出旧还原点原件"),
                          icon: Icons.save_alt_rounded,
                          onPressed: !s.engineer
                              ? null
                              : () => exportTimeOriginal(context, archive, key),
                        ),
                  ],
                ),
                if (!s.engineer) Text(tr(context, "需要工程师或管理员权限才能导出。")),
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
  Widget build(BuildContext context) => DetailScaffold(
    title: tr(context, "使用说明与应用信息"),
    children: [
      const Align(alignment: Alignment.centerLeft, child: BrandMark(size: 64)),
      const SizedBox(height: 22),
      PageHeading(
        eyebrow: tr(context, '应用版本 · {0}', [appVersion]),
        title: tr(context, "让质量，有迹可循。"),
        subtitle: tr(context, "记录检测结果、生产任务与质量复核。"),
      ),
      GlassPanel(
        child: Column(
          children: [
            ExpansionTile(
              title: Text(tr(context, "01  任务与检验")),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      context,
                      "在工作台打开生产任务，按状态开始打印或送检。进入任务详情的质检页，填写检查项、数量和备注，添加照片后提交；检验结果与当时的检查标准一同保存。",
                    ),
                    style: const TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text(tr(context, "02  处理异常与复核")),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      context,
                      "从任务详情的异常页查看问题、负责人和照片。填写处理说明并添加整改证据后送复检；复检会新增一轮记录，原检验结论保留。更改负责人时可同时交接未完成异常。",
                    ),
                    style: const TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text(tr(context, "03  配方与换型")),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      context,
                      "在配方中心查看配置与检查模板。创建任务时选择配置和模板；已提交检验保留当时的版本。进入本机工作区后，可管理本机工位、配方和换型记录。",
                    ),
                    style: const TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text(tr(context, "04  管理数据与备份")),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      context,
                      "团队记录可按任务、日期、人员、批次和结论筛选，并从任务详情查看或导出质量报告。本机数据的备份与恢复位于本机工作区的数据管理中，执行前需完成本机认证。",
                    ),
                    style: const TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text(tr(context, "05  登录与团队")),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      context,
                      "普通用户与团队成员使用同一登录入口。登录后在“我的”切换团队、管理成员或绑定NFC卡片；绑定后可在登录页刷卡登录。本机工作区使用独立的本机认证，恢复码仅用于本机账户。",
                    ),
                    style: const TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: Text(tr(context, "06  数据与隐私")),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      context,
                      "团队账户、任务与检验记录由云端服务管理；待提交草稿和待上传照片保存在当前账户的本机空间，可在同步页面查看与重试。本机工作区的数据独立保存，只有主动导入的记录才会上传到所选团队。",
                    ),
                    style: const TextStyle(height: 1.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text(
        tr(context, '围绕生产任务与质量复核，记录每一次关键结果。'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          height: 1.8,
          color: Colors.blueGrey,
        ),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_workbench.dart';
import '../cloud_local_import.dart';
import '../cloud_photo_recovery.dart';
import '../cloud_trace.dart';
import '../l10n.dart';
import '../liquid_glass_bar.dart';
import '../ui.dart';
import '../language_selector.dart';
import 'cloud_tasks.dart';
import 'cloud_business.dart';

class CloudShell extends StatefulWidget {
  const CloudShell({super.key});
  @override
  State<CloudShell> createState() => _CloudShellState();
}

class _CloudShellState extends State<CloudShell> {
  int _tab = 0;
  String? recoveryScope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = CloudScope.of(context),
        next = CloudScope.of(context).draftKey('outbox');
    if (next == recoveryScope) return;
    recoveryScope = next;
    if (next == null) return;
    Future<void>(() async {
      try {
        final count = await CloudPhotoRecovery.instance.onStartup(account);
        if (mounted && account.draftKey('outbox') == next && count > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr(context, '已恢复 {0} 张照片，请在同步页面上传', [count])),
            ),
          );
        }
      } catch (_) {
        /* The sync page offers recovery and retry actions. */
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context), local = AppScope.of(context);
    final labels = [
      tr(context, '工作台'),
      tr(context, '检测记录'),
      tr(context, '配方中心'),
      tr(context, '我的'),
    ];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.fact_check_outlined,
      Icons.layers_outlined,
      Icons.person_outline_rounded,
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = [
      _workbench(context, account),
      const CloudRecordsPage(),
      const CloudTemplatesPage(),
      _profile(context, account),
    ];
    void select(int tab) {
      local.feedback();
      setState(() => _tab = tab);
    }

    return Scaffold(
      extendBody: !wide,
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (wide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                  child: GlassPanel(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: NavigationRail(
                      selectedIndex: _tab,
                      onDestinationSelected: select,
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: Colors.transparent,
                      scrollable: true,
                      leading: const Padding(
                        padding: EdgeInsets.only(bottom: 30),
                        child: BrandMark(size: 44),
                      ),
                      destinations: List.generate(
                        4,
                        (i) => NavigationRailDestination(
                          icon: Icon(icons[i]),
                          label: Text(labels[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    if (account.busy || account.restoring)
                      const LinearProgressIndicator(),
                    if (account.error != null)
                      MaterialBanner(
                        content: Text(trMessage(context, account.error!)),
                        actions: [
                          TextButton(
                            onPressed: account.busy
                                ? null
                                : () => account.signedIn
                                      ? account.reload()
                                      : openPage(
                                          context,
                                          const CloudLoginPage(),
                                        ),
                            child: Text(
                              tr(context, account.signedIn ? '重试' : '登录'),
                            ),
                          ),
                        ],
                      ),
                    Expanded(
                      child: IndexedStack(index: _tab, children: pages),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : LiquidGlassBar(
              labels: labels,
              icons: icons,
              selectedIndex: _tab,
              onSelected: select,
              glass: local.glass,
            ),
    );
  }

  Widget _workspace(BuildContext context, CloudAccount account) => Row(
    children: [
      const BrandMark(size: 38),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.activeWorkspace?['name'] as String? ?? 'LineSight',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -.2,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  tr(context, '生产质量工作台'),
                  style: const TextStyle(fontSize: 10.5, color: muted),
                ),
                if (account.demoAccount) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: amber.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tr(context, '演示数据'),
                      style: const TextStyle(
                        color: amber,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      if (account.signedIn)
        IconButton.filledTonal(
          tooltip: tr(context, '刷新'),
          onPressed: account.busy ? null : account.reload,
          icon: const Icon(Icons.refresh, size: 19),
          style: IconButton.styleFrom(
            minimumSize: const Size(40, 40),
            backgroundColor: Colors.white,
            foregroundColor: ink,
            side: const BorderSide(color: hairline),
          ),
        ),
    ],
  );

  Widget _loginState(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
    child: Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: blue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.shield_outlined, color: blue, size: 29),
        ),
        const SizedBox(height: 14),
        Text(
          tr(context, '登录后查看任务与检验记录'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          tr(context, '与团队同步质检进度、照片证据与质量报告。'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: muted, height: 1.5),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => openPage(context, const CloudLoginPage()),
          icon: const Icon(Icons.login, size: 18),
          label: Text(tr(context, '登录')),
        ),
      ],
    ),
  );

  Widget _noticeRow(
    BuildContext context,
    CloudAccount account,
    Map<String, dynamic> notice,
  ) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: () {
        final matches = account.jobs.where(
          (j) => '${j['id']}' == '${notice['task_id']}',
        );
        if (matches.isNotEmpty) {
          openPage(
            context,
            CloudTaskPage(
              job: matches.first,
              workspaceId: account.activeWorkspace!['id'] as int,
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (notice['reinspection'] == true ? amber : blue)
                    .withValues(alpha: .1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                notice['reinspection'] == true
                    ? Icons.replay_circle_filled_outlined
                    : Icons.notifications_active_outlined,
                size: 17,
                color: notice['reinspection'] == true ? amber : blue,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${notice['part_name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr(
                      context,
                      notice['reinspection'] == true
                          ? '待复检'
                          : taskStatusLabels[notice['status']] ?? '待处理',
                    ),
                    style: const TextStyle(fontSize: 10.5, color: muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA9B8CC)),
          ],
        ),
      ),
    ),
  );

  Widget _workbench(BuildContext context, CloudAccount account) {
    int count(String status) =>
        account.jobs.where((j) => j['status'] == status).length;
    final pending = count('inspection'), issues = count('exception');
    final closed = count('closed');
    return PageBody(
      children: [
        _workspace(context, account),
        const SizedBox(height: 18),
        HeroBanner(
          eyebrow: 'LINESIGHT · QUALITY OPS',
          title: tr(context, '工作台'),
          subtitle: account.signedIn
              ? '${tr(context, '待质检')} $pending · ${tr(context, '异常处理中')} $issues · ${tr(context, '已关闭')} $closed'
              : tr(context, '登录后查看任务与检验记录'),
          trailing: account.demoAccount
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFC55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        tr(context, '演示数据'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          actions: account.signedIn
              ? [
                  HeroAction(
                    label: tr(context, '扫码追溯'),
                    icon: Icons.qr_code_scanner,
                    onPressed: () => openPage(context, const CloudScanPage()),
                  ),
                  HeroAction(
                    label: tr(context, '输入追溯号'),
                    icon: Icons.keyboard,
                    ghost: true,
                    onPressed: () => openCloudTraceInput(context),
                  ),
                  if (account.canEdit)
                    HeroAction(
                      label: tr(context, '新建任务'),
                      icon: Icons.add,
                      ghost: true,
                      onPressed: account.busy
                          ? null
                          : () =>
                                openPage(context, const CloudCreateTaskPage()),
                    ),
                ]
              : [
                  HeroAction(
                    label: tr(context, '登录'),
                    icon: Icons.login,
                    onPressed: () => openPage(context, const CloudLoginPage()),
                  ),
                ],
        ),
        if (!account.signedIn)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: _loginState(context),
          )
        else ...[
          CloudWorkbenchSummary(account: account),
          SectionHeader(
            tr(context, '生产任务'),
            caption: '${account.jobs.length} ${tr(context, '个任务')}',
            icon: Icons.inventory_2_outlined,
            action: TextButton(
              onPressed: () => openPage(context, const CloudTaskListPage()),
              child: Text(tr(context, '查看全部')),
            ),
          ),
          if (account.jobs.isEmpty && !account.busy)
            EmptyState(
              title: tr(context, '暂无生产任务'),
              subtitle: tr(context, '当前工作区还没有生产任务。'),
              action: account.canEdit
                  ? FilledButton.icon(
                      onPressed: () =>
                          openPage(context, const CloudCreateTaskPage()),
                      icon: const Icon(Icons.add),
                      label: Text(tr(context, '新建任务')),
                    )
                  : null,
            ),
          ...account.jobs.take(5).map((job) => CloudTaskTile(job: job)),
          SectionHeader(tr(context, '快捷操作'), icon: Icons.bolt_outlined),
          AdaptiveGrid(
            minWidth: 168,
            children: [
              QuickAction(
                title: tr(context, '质量洞察'),
                caption: tr(context, '通过率与异常趋势'),
                icon: Icons.insights_outlined,
                onPressed: () => openPage(context, const CloudReportPage()),
              ),
              if (account.canEdit)
                QuickAction(
                  title: tr(context, '新建任务'),
                  caption: tr(context, '创建生产质检单'),
                  icon: Icons.add_task,
                  color: green,
                  onPressed: () =>
                      openPage(context, const CloudCreateTaskPage()),
                ),
              QuickAction(
                title: tr(context, '待办与通知'),
                caption:
                    '${account.notifications.length} ${tr(context, '条提醒')}',
                icon: Icons.notifications_active_outlined,
                color: amber,
                onPressed: () =>
                    openPage(context, const CloudNotificationsPage()),
              ),
              QuickAction(
                title: tr(context, '同步与草稿'),
                caption: tr(context, '离线照片与未提交内容'),
                icon: Icons.cloud_sync_outlined,
                color: const Color(0xFF7B61D9),
                onPressed: () => openPage(context, const CloudSyncPage()),
              ),
            ],
          ),
          if (account.notifications.isNotEmpty) ...[
            SectionHeader(
              tr(context, '待办提醒'),
              caption:
                  '${account.notifications.where((n) => n['read'] != true).length} ${tr(context, '条未读')}',
              icon: Icons.notifications_none_rounded,
              action: TextButton(
                onPressed: () =>
                    openPage(context, const CloudNotificationsPage()),
                child: Text(tr(context, '查看全部')),
              ),
            ),
            GlassPanel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (
                    var i = 0;
                    i < account.notifications.take(3).length;
                    i++
                  ) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 58, endIndent: 14),
                    _noticeRow(context, account, account.notifications[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _profile(BuildContext context, CloudAccount account) {
    final role = '${account.activeWorkspace?['role'] ?? ''}';
    final roleLabel = switch (role) {
      'owner' => tr(context, '团队管理员'),
      'operator' => tr(context, '操作成员'),
      'viewer' => tr(context, '只读成员'),
      _ => tr(context, '成员'),
    };
    return PageBody(
      children: [
        _workspace(context, account),
        const SizedBox(height: 18),
        if (!account.signedIn)
          _loginState(context)
        else ...[
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5699FF), Color(0xFF2A63E8)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    account.displayName.isEmpty
                        ? 'L'
                        : account.displayName.characters.first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName.isEmpty
                            ? tr(context, '未命名成员')
                            : account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ink,
                          letterSpacing: -.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '@${account.profile?['username'] ?? ''}',
                        style: const TextStyle(fontSize: 11.5, color: muted),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Tag(roleLabel, color: blue),
                          if (account.demoAccount)
                            Tag(tr(context, '演示数据'), color: amber),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => openPage(context, const CloudProfilePage()),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          SectionHeader(tr(context, '团队与账户'), icon: Icons.groups_2_outlined),
          if (account.workspaces.isNotEmpty)
            GlassPanel(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: DropdownButtonFormField<int>(
                initialValue: account.activeWorkspace?['id'] as int?,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr(context, '工作区'),
                  prefixIcon: const Icon(Icons.domain_outlined, size: 19),
                ),
                items: account.workspaces
                    .map(
                      (w) => DropdownMenuItem(
                        value: w['id'] as int,
                        child: Text(
                          '${w['name']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: account.busy
                    ? null
                    : (id) => account.selectWorkspace(
                        account.workspaces.firstWhere((w) => w['id'] == id),
                      ),
              ),
            ),
          const SizedBox(height: 10),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                MenuTile(
                  title: tr(context, '团队成员'),
                  subtitle: tr(context, '邀请成员与管理权限'),
                  icon: Icons.group_add_outlined,
                  onTap: account.activeWorkspace == null
                      ? null
                      : () => openPage(context, const CloudTeamPage()),
                ),
                const Divider(height: 1, indent: 64, endIndent: 14),
                MenuTile(
                  title: tr(context, '同步与草稿'),
                  subtitle: tr(context, '离线照片与未提交内容'),
                  icon: Icons.cloud_sync_outlined,
                  color: const Color(0xFF7B61D9),
                  onTap: () => openPage(context, const CloudSyncPage()),
                ),
                if (account.canEdit)
                  MenuTile(
                    title: tr(context, '导入本机记录'),
                    subtitle: tr(context, '授权、预览并导入历史记录'),
                    icon: Icons.move_to_inbox_outlined,
                    onTap: () =>
                        openPage(context, const CloudLocalImportPage()),
                  ),
                const Divider(height: 1, indent: 64, endIndent: 14),
                MenuTile(
                  title: tr(context, '待办与通知'),
                  subtitle:
                      '${account.notifications.length} ${tr(context, '条提醒')}',
                  icon: Icons.notifications_active_outlined,
                  color: amber,
                  onTap: () =>
                      openPage(context, const CloudNotificationsPage()),
                ),
              ],
            ),
          ),
          SectionHeader(tr(context, '偏好设置'), icon: Icons.tune),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: MenuTile(
              title: '语言 / Language',
              subtitle: tr(context, '简体中文 / English'),
              icon: Icons.language,
              color: green,
              onTap: () => chooseLanguage(context),
            ),
          ),
          const SizedBox(height: 10),
          GlassPanel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: MenuTile(
              title: tr(context, '质量洞察与报告'),
              subtitle: tr(context, '团队质量趋势与导出'),
              icon: Icons.insights_outlined,
              onTap: () => openPage(context, const CloudReportPage()),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'LineSight $appVersion · ${tr(context, '本地优先的质量追溯')}',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF9AA9BD)),
            ),
          ),
          if (account.signedIn)
            Center(
              child: TextButton(
                onPressed: account.busy
                    ? null
                    : () async {
                        final yes = await confirm(
                          context,
                          tr(context, '退出登录？'),
                          tr(context, '确认退出当前账号？'),
                        );
                        if (yes) await account.signOut();
                      },
                child: Text(
                  tr(context, '退出登录'),
                  style: const TextStyle(color: red),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class CloudLoginPage extends StatelessWidget {
  const CloudLoginPage({super.key});
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    Future<void> login(bool demo) async {
      await account.signIn(demo: demo);
      if (context.mounted && account.signedIn && account.profile != null) {
        Navigator.pop(context);
      }
    }

    return DetailScaffold(
      title: tr(context, '登录'),
      children: [
        const SizedBox(height: 8),
        HeroBanner(
          eyebrow: 'LINESIGHT · TEAM CLOUD',
          title: tr(context, '登录团队工作区'),
          subtitle: tr(context, '同步生产任务、检验记录与质量报告，离线操作也会安全保留。'),
          trailing: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Colors.white,
              size: 21,
            ),
          ),
        ),
        const SizedBox(height: 18),
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(context, '使用团队账号继续'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                tr(context, '登录后将自动载入当前工作区的任务与通知。'),
                style: const TextStyle(
                  fontSize: 11.5,
                  color: muted,
                  height: 1.5,
                ),
              ),
              if (account.busy) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ],
              if (account.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    trMessage(context, account.error!),
                    style: const TextStyle(color: red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: account.busy ? null : () => login(false),
                icon: const Icon(Icons.login, size: 19),
                label: Text(tr(context, '登录')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: account.busy ? null : () => login(true),
                icon: const Icon(Icons.explore_outlined, size: 19),
                label: Text(tr(context, '进入演示团队')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              MenuTile(
                title: tr(context, '任务与检验同步'),
                subtitle: tr(context, '状态、轮次和逐件 SN 实时更新'),
                icon: Icons.sync_alt,
                trailing: const Icon(
                  Icons.check_circle,
                  color: green,
                  size: 18,
                ),
              ),
              const Divider(height: 1, indent: 62, endIndent: 4),
              MenuTile(
                title: tr(context, '照片证据留存'),
                subtitle: tr(context, '原图与边缘参考双重归档'),
                icon: Icons.photo_library_outlined,
                color: const Color(0xFF7B61D9),
                trailing: const Icon(
                  Icons.check_circle,
                  color: green,
                  size: 18,
                ),
              ),
              const Divider(height: 1, indent: 62, endIndent: 4),
              MenuTile(
                title: tr(context, '团队权限隔离'),
                subtitle: tr(context, '按工作区隔离数据与操作权限'),
                icon: Icons.verified_user_outlined,
                color: green,
                trailing: const Icon(
                  Icons.check_circle,
                  color: green,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'LineSight $appVersion',
            style: TextStyle(fontSize: 10.5, color: Color(0xFF9AA9BD)),
          ),
        ),
      ],
    );
  }
}

class CloudProfilePage extends StatefulWidget {
  const CloudProfilePage({super.key});
  @override
  State<CloudProfilePage> createState() => _CloudProfilePageState();
}

class _CloudProfilePageState extends State<CloudProfilePage> {
  final _name = TextEditingController();
  bool _initialized = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!_initialized) {
      _name.text = account.displayName;
      _initialized = true;
    }
    return DetailScaffold(
      title: tr(context, '账户与安全'),
      children: [
        if (!account.signedIn)
          EmptyState(
            icon: Icons.lock_outline,
            title: tr(context, '需要登录'),
            subtitle: tr(context, '登录后管理账户信息与密码。'),
            action: FilledButton(
              onPressed: () => openPage(context, const CloudLoginPage()),
              child: Text(tr(context, '登录')),
            ),
          )
        else ...[
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF5699FF), Color(0xFF2A63E8)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    account.displayName.isEmpty
                        ? 'L'
                        : account.displayName.characters.first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '@${account.profile?['username'] ?? ''}',
                        style: const TextStyle(fontSize: 11.5, color: muted),
                      ),
                    ],
                  ),
                ),
                if (account.demoAccount) Tag(tr(context, '演示数据'), color: amber),
              ],
            ),
          ),
          SectionHeader(tr(context, '账户信息'), icon: Icons.badge_outlined),
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  enabled: !account.demoAccount && !account.busy,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: tr(context, '显示名称'),
                    prefixIcon: const Icon(Icons.person_outline, size: 19),
                  ),
                ),
                if (!account.demoAccount)
                  FilledButton(
                    onPressed: account.busy
                        ? null
                        : () => account.updateDisplayName(_name.text.trim()),
                    child: Text(tr(context, '保存')),
                  ),
                if (account.demoAccount)
                  Text(
                    tr(context, '演示账号不支持修改账户信息。'),
                    style: const TextStyle(fontSize: 11.5, color: muted),
                  ),
              ],
            ),
          ),
          if (!account.demoAccount) ...[
            SectionHeader(tr(context, '登录安全'), icon: Icons.key_outlined),
            GlassPanel(
              padding: EdgeInsets.zero,
              child: MenuTile(
                title: tr(context, '修改密码'),
                subtitle: tr(context, '通过团队身份服务更新登录凭据'),
                icon: Icons.lock_reset,
                color: green,
                onTap: account.busy
                    ? null
                    : () => account.signIn(changePassword: true),
              ),
            ),
          ],
          if (account.busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (account.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                trMessage(context, account.error!),
                style: const TextStyle(color: red, fontSize: 12),
              ),
            ),
        ],
      ],
    );
  }
}

class CloudMembersPage extends StatefulWidget {
  const CloudMembersPage({super.key});
  @override
  State<CloudMembersPage> createState() => _CloudMembersPageState();
}

class _CloudMembersPageState extends State<CloudMembersPage> {
  List<Map<String, dynamic>>? _members;
  String? _error;
  bool _loading = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_members == null && _error == null && !_loading) _load();
  }

  Future<void> _load() async {
    final account = CloudScope.of(context),
        workspace = CloudScope.of(context).activeWorkspace;
    if (workspace == null) return;
    _loading = true;
    _error = null;
    try {
      final rows =
          (await account.request(
                    'GET',
                    'workspaces/${workspace['id']}/members/',
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _members = rows);
    } catch (_) {
      if (mounted) setState(() => _error = '无法加载成员，请重试');
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) => !CloudScope.of(context).signedIn
      ? cloudAccessRequired(context)
      : DetailScaffold(
          title: tr(context, '团队成员'),
          children: [
            if (_error != null) Text(trMessage(context, _error!)),
            if (_members == null && _error == null)
              const LinearProgressIndicator(),
            ...?_members?.map(
              (member) => GlassPanel(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    '${member['display_name'] ?? member['username']}',
                  ),
                  subtitle: Text(
                    tr(context, switch (member['role']) {
                      'owner' => '团队管理员',
                      'operator' => '操作成员',
                      _ => '只读成员',
                    }),
                  ),
                ),
              ),
            ),
            if (_error != null)
              TextButton(onPressed: _load, child: Text(tr(context, '重试'))),
          ],
        );
}

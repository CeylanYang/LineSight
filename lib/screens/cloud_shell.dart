import '../editions/special/special_vip.dart';
import '../editions/special/special_workbench.dart';
import '../editions/special/special_content.dart';
import '../cloud_avatar.dart';
import '../cloud_layout.dart';
import 'cloud_inspection_hub.dart';
import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_notifications.dart';
import '../cloud_navigation.dart';
import '../cloud_workbench.dart';
import '../cloud_local_import.dart';
import '../cloud_photo_recovery.dart';
import '../cloud_trace.dart';
import '../cloud_vision.dart';
import '../l10n.dart';
import '../liquid_glass_bar.dart';
import '../ui.dart';
import '../language_selector.dart';
import 'cloud_tasks.dart';
import 'cloud_profiles.dart';
import 'cloud_business.dart';
import 'cloud_nfc.dart';
import 'cloud_sessions.dart';
import 'settings.dart' show HelpPage;
import 'app_updates.dart';
import '../nfc_reader.dart';
import '../editions/edition_host.dart';
import '../official_website.dart';
import '../editions/special/special_media.dart' show SpecialWebPage;

class CloudShell extends StatefulWidget {
  const CloudShell({super.key});
  @override
  State<CloudShell> createState() => _CloudShellState();
}

class _CloudShellState extends State<CloudShell> {
  int _tab = 0;
  int _configurationTab = 0;
  int _inspectionTab = 0;
  final _visited = <int>{0};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _selectTab(int tab) {
    AppScope.of(context).feedback();
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    CloudNavigationScope.maybeOf(context)?.value = tab;
  }

  void _openConfiguration(int tab) {
    setState(() => _configurationTab = tab);
    _selectTab(3);
  }

  void _openInspection(int tab) {
    setState(() => _inspectionTab = tab);
    _selectTab(2);
  }

  Future<void> _chooseWorkspace(CloudAccount account) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                tr(context, '切换工作区'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final workspace in account.workspaces)
              ListTile(
                title: Text('${workspace['name']}'),
                trailing: account.activeWorkspace?['id'] == workspace['id']
                    ? const Icon(Icons.check, color: blue)
                    : null,
                onTap: () => Navigator.pop(context, workspace),
              ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: Text(tr(context, '团队成员')),
              onTap: () {
                Navigator.pop(context);
                openPage(this.context, const CloudTeamPage());
              },
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted && !account.busy) {
      await account.selectWorkspace(picked);
    }
  }

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
      tr(context, '生产'),
      tr(context, '质检'),
      tr(context, '配置'),
      tr(context, '我的'),
    ];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.precision_manufacturing_outlined,
      Icons.fact_check_outlined,
      Icons.layers_outlined,
      Icons.person_outline_rounded,
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final navigation = CloudNavigationScope.maybeOf(context);
    final selectedTab = navigation?.value ?? _tab;
    _visited.add(selectedTab);
    Widget protected(Widget Function() page) => account.signedIn
        ? page()
        : PageBody(
            children: [
              _workspace(context, account),
              const SizedBox(height: 18),
              _loginState(context),
            ],
          );
    final pages = [
      _workbench(context, account),
      if (_visited.contains(1))
        protected(
          () => CloudTaskListPage(
            key: ValueKey('production/${account.accessScope}'),
            embedded: true,
          ),
        )
      else
        const SizedBox.shrink(),
      if (_visited.contains(2))
        protected(
          () => CloudInspectionHub(
            key: ValueKey('inspection/${account.accessScope}'),
            initialTab: _inspectionTab,
            onTabChanged: (tab) => _inspectionTab = tab,
          ),
        )
      else
        const SizedBox.shrink(),
      if (_visited.contains(3))
        protected(
          () => CloudConfigurationPage(
            key: ValueKey('configuration/${account.accessScope}'),
            initialTab: _configurationTab,
            onTabChanged: (tab) => _configurationTab = tab,
          ),
        )
      else
        const SizedBox.shrink(),
      if (_visited.contains(4))
        _profile(context, account)
      else
        const SizedBox.shrink(),
    ];
    void select(int tab) => _selectTab(tab);

    return PopScope(
      canPop: selectedTab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedTab != 0) select(0);
      },
      child: Scaffold(
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
                        selectedIndex: selectedTab,
                        onDestinationSelected: select,
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: Colors.transparent,
                        scrollable: true,
                        leading: const Padding(
                          padding: EdgeInsets.only(bottom: 30),
                          child: BrandMark(size: 44),
                        ),
                        destinations: List.generate(
                          labels.length,
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
                      if (account.signedIn &&
                          account.error != null &&
                          account.workspaceFailure == null)
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
                        child: IndexedStack(
                          index: selectedTab,
                          children: [
                            for (var i = 0; i < pages.length; i++)
                              SpecialSectionScope(
                                title: labels[i],
                                child: pages[i],
                              ),
                          ],
                        ),
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
                iconBuilder: local.specialEdition ? specialTabIcon : null,
                selectedIndex: selectedTab,
                onSelected: select,
                glass: local.glass,
              ),
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
                Flexible(
                  child: Text(
                    tr(context, '生产质量工作台'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: muted),
                  ),
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
      if (account.signedIn) ...[
        IconButton(
          tooltip: tr(context, '切换工作区'),
          onPressed: account.busy ? null : () => _chooseWorkspace(account),
          icon: const Icon(Icons.expand_more),
        ),
        IconButton(
          tooltip: tr(context, '待办与通知'),
          onPressed: () => openPage(context, const CloudNotificationsPage()),
          icon: Badge(
            isLabelVisible:
                account.workspaceDataReady &&
                account.notifications.any((n) => n['read'] != true),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
      ],
    ],
  );

  Widget _loginState(BuildContext context) => const CloudLoginPanel();

  Widget _noticeRow(
    BuildContext context,
    CloudAccount account,
    Map<String, dynamic> notice,
  ) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: () => openCloudNotification(context, notice),
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
                          : (notice['bulletin'] == true
                                    ? (notice['kind'] == 'task'
                                          ? '生产安排'
                                          : notice['kind'] == 'template'
                                          ? '模板更新'
                                          : '通知预告')
                                    : taskStatusLabels[notice['status']]) ??
                                '待处理',
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
    if (!account.signedIn) {
      return PageBody(
        children: [
          _workspace(context, account),
          const SizedBox(height: 28),
          const CloudLoginPanel(),
        ],
      );
    }
    if (AppScope.of(context).specialEdition) {
      return SpecialWorkbenchPage(
        workspaceUpdates: account.notifications.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: Column(
                    children: [
                      for (final notice in account.notifications.take(2))
                        _noticeRow(context, account, notice),
                    ],
                  ),
                ),
              ),
        onRecords: () => _openInspection(1),
        onTemplates: () => _openConfiguration(1),
        counts: {
          'jobs': account.jobs.length,
          'alerts': account.jobs
              .where((j) => j['status'] == 'exception')
              .length,
          'records': account.records.length,
          'templates': account.templates.length,
        },
        actions: {
          '搜索': () => openPage(context, const CloudTaskListPage()),
          '在线质检': () => openPage(context, const CloudLiveInspectionPage()),
          '扫码追溯': () => openPage(context, const CloudScanPage()),
          '新建任务': () => account.canEdit
              ? openPage(context, const CloudCreateTaskPage())
              : _selectTab(1),
          '质量报告': () => _openInspection(2),
          '待检任务': () => _openInspection(0),
          '异常处理': () =>
              openPage(context, const CloudTaskListPage(status: 'exception')),
          '检测记录': () => _openInspection(1),
          '打印配置': () => _openConfiguration(0),
          '检查模板': () => _openConfiguration(1),
        },
      );
    }
    final notices = account.notifications
        .where(
          (n) =>
              n['bulletin'] == true ||
              n['status'] == 'inspection' ||
              n['status'] == 'exception',
        )
        .take(2)
        .toList();
    void search() {
      final query = _search.text.trim();
      if (query.isNotEmpty) {
        openPage(context, CloudTaskListPage(filters: {'q': query}));
      }
    }

    return PageBody(
      children: [
        _workspace(context, account),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => search(),
          decoration: InputDecoration(
            hintText: tr(context, '任务号、批次或名称'),
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: IconButton(
              tooltip: tr(context, '搜索'),
              onPressed: search,
              icon: const Icon(Icons.arrow_forward, size: 20),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
        const SizedBox(height: 10),
        GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: CloudShortcutGrid(
            primary: true,
            entries: [
              CloudShortcut(
                '在线质检',
                Icons.videocam_outlined,
                () => openPage(context, const CloudLiveInspectionPage()),
              ),
              CloudShortcut(
                '扫码追溯',
                Icons.qr_code_scanner,
                () => openPage(context, const CloudScanPage()),
              ),
              if (account.canEdit)
                CloudShortcut(
                  '新建任务',
                  Icons.add_task,
                  () => openPage(context, const CloudCreateTaskPage()),
                  color: green,
                )
              else
                CloudShortcut(
                  '生产任务',
                  Icons.precision_manufacturing_outlined,
                  () => _selectTab(1),
                  color: green,
                ),
              CloudShortcut(
                '质量报告',
                Icons.analytics_outlined,
                () => _openInspection(2),
                color: const Color(0xFF7359CB),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: CloudShortcutGrid(
            entries: [
              CloudShortcut(
                '待检任务',
                Icons.fact_check_outlined,
                () => _openInspection(0),
                color: amber,
              ),
              CloudShortcut(
                '异常处理',
                Icons.build_circle_outlined,
                () => openPage(
                  context,
                  const CloudTaskListPage(status: 'exception'),
                ),
                color: red,
              ),
              CloudShortcut(
                '检测记录',
                Icons.receipt_long_outlined,
                () => _openInspection(1),
              ),
              CloudShortcut(
                '打印配置',
                Icons.print_outlined,
                () => _openConfiguration(0),
              ),
              CloudShortcut(
                '检查模板',
                Icons.checklist_rounded,
                () => _openConfiguration(1),
                color: green,
              ),
              CloudShortcut(
                '团队成员',
                Icons.groups_outlined,
                () => openPage(context, const CloudTeamPage()),
                color: const Color(0xFF7359CB),
              ),
              CloudShortcut(
                '我的卡片',
                Icons.nfc,
                () => openPage(context, const CloudNfcCardsPage()),
              ),
              CloudShortcut(
                '同步与草稿',
                Icons.cloud_sync_outlined,
                () => openPage(context, const CloudSyncPage()),
                color: green,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GlassPanel(
          key: const ValueKey('workbench-stocks-strip'),
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () => openPage(context, const SpecialWebPage()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7359CB).withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.candlestick_chart,
                      color: Color(0xFF7359CB),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tr(context, '在线股票'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: muted, size: 22),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        CloudWorkbenchSummary(account: account),
        if (account.workspaceDataReady) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, '我的待办'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    openPage(context, const CloudNotificationsPage()),
                child: Text(tr(context, '查看全部')),
              ),
            ],
          ),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: notices.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      tr(context, '暂无待办'),
                      style: const TextStyle(color: muted),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < notices.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 58, endIndent: 14),
                        _noticeRow(context, account, notices[i]),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _profile(BuildContext context, CloudAccount account) {
    final role = '${account.activeWorkspace?['role'] ?? ''}';
    final roleLabel = switch (role) {
      'owner' => tr(context, '团队管理员'),
      'manager' => tr(context, '团队主管'),
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
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => openPage(context, const CloudProfilePage()),
              child: Semantics(
                button: true,
                label: tr(context, '账户信息'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SpecialVipAvatar(
                        child: CloudAvatar(
                          data: account.profile?['avatar_data'],
                          size: 56,
                          fallback: Container(
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
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: muted,
                              ),
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
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                MenuTile(
                  title: tr(context, '我的卡片'),
                  subtitle: tr(context, '绑定卡片与刷卡登录'),
                  icon: Icons.nfc,
                  onTap: () => openPage(context, const CloudNfcCardsPage()),
                ),
                const Divider(height: 1, indent: 64, endIndent: 14),
                MenuTile(
                  title: tr(context, '账户与安全'),
                  subtitle: tr(context, '密码与登录设备'),
                  icon: Icons.security_outlined,
                  onTap: () => openPage(context, const CloudProfilePage()),
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
                  subtitle: account.workspaceDataReady
                      ? '${account.notifications.length} ${tr(context, '条提醒')}'
                      : tr(context, '待办与通知'),
                  icon: Icons.notifications_active_outlined,
                  color: amber,
                  onTap: () =>
                      openPage(context, const CloudNotificationsPage()),
                ),
              ],
            ),
          ),
          SectionHeader(tr(context, '偏好设置'), icon: Icons.tune),
          const GlassPanel(padding: EdgeInsets.zero, child: EditionSwitch()),
          const SizedBox(height: 10),
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
            child: Column(
              children: [
                MenuTile(
                  title: tr(context, '使用说明与应用信息'),
                  subtitle: tr(context, '记录检测结果、生产任务与质量复核。'),
                  icon: Icons.help_outline,
                  onTap: () => openPage(context, const HelpPage()),
                ),
                const Divider(height: 1, indent: 64, endIndent: 14),
                MenuTile(
                  title: tr(context, '应用更新'),
                  subtitle: tr(context, '自动下载更新，下次启动生效。'),
                  icon: Icons.system_update_outlined,
                  onTap: () => openPage(context, const AppUpdatesPage()),
                ),
                const Divider(height: 1, indent: 64, endIndent: 14),
                MenuTile(
                  title: tr(context, 'LineSight 官网'),
                  subtitle: '99ai.pronhubcn.com',
                  icon: Icons.language_outlined,
                  onTap: () => openOfficialWebsite(context),
                ),
                const Divider(height: 1, indent: 64, endIndent: 14),
                MenuTile(
                  title: tr(context, '本机配方与工位'),
                  subtitle: tr(context, '配方、换型与系统 · 本机'),
                  icon: Icons.settings_input_component_outlined,
                  onTap: () =>
                      openPage(context, const LocalConfigurationGate()),
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

Future<bool> cloudReauthenticate(BuildContext context) async {
  var accepted = false;
  await Navigator.of(context).push(
    appPageRoute<void>(
      context,
      CloudLoginPage(onAuthenticated: () => accepted = true),
    ),
  );
  return accepted;
}

class CloudLoginPage extends StatelessWidget {
  final VoidCallback? onAuthenticated;
  const CloudLoginPage({super.key, this.onAuthenticated});
  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: tr(context, '登录'),
    children: [
      CloudLoginPanel(
        onAuthenticated: () {
          onAuthenticated?.call();
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        },
      ),
    ],
  );
}

class CloudLoginPanel extends StatelessWidget {
  final VoidCallback? onAuthenticated;
  const CloudLoginPanel({super.key, this.onAuthenticated});
  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    void accepted() {
      if (context.mounted &&
          account.signedIn &&
          account.profile != null &&
          account.error == null) {
        onAuthenticated?.call();
      }
    }

    Future<void> login(bool demo) async {
      await account.signIn(demo: demo);
      accepted();
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(context, '登录工作区'),
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, '生产任务、质检与团队协作'),
              style: const TextStyle(fontSize: 14, color: muted),
            ),
            const SizedBox(height: 26),
            GlassPanel(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (account.busy) const LinearProgressIndicator(),
                  if (account.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        trMessage(context, account.error!),
                        style: const TextStyle(color: red),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: account.busy ? null : () => login(false),
                    icon: const Icon(Icons.login),
                    label: Text(tr(context, '登录')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: account.busy
                        ? null
                        : () async {
                            final card = await Navigator.of(context)
                                .push<NfcCardRead>(
                                  appPageRoute<NfcCardRead>(
                                    context,
                                    const CloudNfcScanPage(),
                                  ),
                                );
                            if (card == null || !context.mounted) return;
                            await account.signInNfc(card.code);
                            accepted();
                          },
                    icon: const Icon(Icons.nfc),
                    label: Text(tr(context, '刷卡登录')),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: account.busy ? null : () => login(true),
                    icon: const Icon(Icons.explore_outlined),
                    label: Text(tr(context, '进入演示团队')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
  String? _identityBinding;
  bool _initialized = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!_initialized || _identityBinding != account.identityScope) {
      _identityBinding = account.identityScope;
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
                CloudAvatar(
                  data: account.profile?['avatar_data'],
                  size: 48,
                  fallback: Container(
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
                if ('${account.profile?['job_title'] ?? ''}'.isNotEmpty)
                  InfoRow(
                    tr(context, '岗位'),
                    '${account.profile!['job_title']}',
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
            GlassPanel(
              padding: EdgeInsets.zero,
              child: MenuTile(
                title: tr(context, '登录会话'),
                subtitle: tr(context, '管理当前账户的登录设备'),
                icon: Icons.devices,
                color: blue,
                onTap: () => openPage(context, const CloudSessionsPage()),
              ),
            ),
            SectionHeader(tr(context, '登录安全'), icon: Icons.key_outlined),
            GlassPanel(
              padding: EdgeInsets.zero,
              child: MenuTile(
                title: tr(context, '修改密码'),
                subtitle: tr(context, '更新当前账户的登录密码'),
                icon: Icons.lock_reset,
                color: green,
                onTap: account.busy
                    ? null
                    : () => account.signIn(changePassword: true),
              ),
            ),
          ],
          const SizedBox(height: 12),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: MenuTile(
              title: tr(context, '我的卡片'),
              subtitle: tr(context, '绑定卡片与刷卡登录'),
              icon: Icons.nfc,
              color: blue,
              onTap: () => openPage(context, const CloudNfcCardsPage()),
            ),
          ),
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
  String? _error, _scope;
  bool _loading = false;
  int _generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CloudScope.of(context).accessScope;
    if (next != _scope) {
      _scope = next;
      _members = null;
      _error = null;
      _loading = false;
      _generation++;
      if (next != null) _load();
    }
  }

  Future<void> _load() async {
    final account = CloudScope.of(context),
        captured = _scope,
        ticket = ++_generation;
    if (captured == null) return;
    _loading = true;
    _error = null;
    try {
      final rows =
          (await account.request(
                    'GET',
                    'workspaces/${account.activeWorkspace!['id']}/members/',
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      if (mounted && ticket == _generation && account.retainsAccess(captured)) {
        setState(() => _members = rows);
      }
    } catch (_) {
      if (mounted && ticket == _generation && account.retainsAccess(captured)) {
        setState(() => _error = '无法加载成员，请重试');
      }
    } finally {
      if (mounted && ticket == _generation && account.retainsAccess(captured)) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => !CloudScope.of(context).signedIn
      ? cloudAccessRequired(context)
      : DetailScaffold(
          title: tr(context, '团队成员'),
          children: [
            if (_error != null) Text(trMessage(context, _error!)),
            if (_loading) const LinearProgressIndicator(),
            ...?_members?.map(
              (member) => GlassPanel(
                child: ListTile(
                  leading: CloudAvatar(
                    data: member['avatar_data'],
                    size: 38,
                    fallback: const Icon(Icons.person_outline),
                  ),
                  title: Text(
                    '${member['display_name'] ?? member['username']}',
                  ),
                  subtitle: Text(
                    tr(context, switch (member['role']) {
                      'owner' => '团队管理员',
                      'manager' => '团队主管',
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

import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../l10n.dart';
import '../liquid_glass_bar.dart';
import '../ui.dart';
import '../language_selector.dart';
import 'cloud_tasks.dart';

class CloudShell extends StatefulWidget {
  const CloudShell({super.key});
  @override
  State<CloudShell> createState() => _CloudShellState();
}

class _CloudShellState extends State<CloudShell> {
  int _tab = 0;
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
      _records(context, account),
      _templates(context, account),
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
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: select,
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(
                    4,
                    (i) => NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(labels[i]),
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
      const BrandMark(size: 34),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          account.activeWorkspace?['name'] as String? ?? 'LineSight',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      if (account.demoAccount) Tag(tr(context, '演示数据'), color: amber),
      if (account.signedIn)
        IconButton(
          tooltip: tr(context, '刷新'),
          onPressed: account.busy ? null : account.reload,
          icon: const Icon(Icons.refresh),
        ),
    ],
  );

  Widget _loginState(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        const Icon(Icons.account_circle_outlined, color: blue, size: 54),
        const SizedBox(height: 16),
        Text(tr(context, '登录后查看任务与检验记录'), textAlign: TextAlign.center),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => openPage(context, const CloudLoginPage()),
          icon: const Icon(Icons.login),
          label: Text(tr(context, '登录')),
        ),
      ],
    ),
  );

  Widget _workbench(BuildContext context, CloudAccount account) => PageBody(
    children: [
      _workspace(context, account),
      const SizedBox(height: 24),
      Text(
        tr(context, '工作台'),
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 16),
      if (!account.signedIn)
        _loginState(context)
      else ...[
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in {
              'inspection': '待质检',
              'exception': '异常处理中',
              'closed': '已关闭',
            }.entries)
              SizedBox(
                width: 150,
                child: GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, entry.value)),
                      const SizedBox(height: 8),
                      Text(
                        '${account.jobs.where((j) => j['status'] == entry.key).length}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: SectionHeading(tr(context, '生产任务'))),
            TextButton(
              onPressed: () => openPage(context, const CloudTaskListPage()),
              child: Text(tr(context, '查看全部')),
            ),
          ],
        ),
        if (account.canEdit)
          FilledButton.icon(
            onPressed: account.busy
                ? null
                : () => openPage(context, const CloudCreateTaskPage()),
            icon: const Icon(Icons.add),
            label: Text(tr(context, '新建任务')),
          ),
        if (account.jobs.isEmpty && !account.busy)
          EmptyState(
            title: tr(context, '暂无生产任务'),
            subtitle: tr(context, '当前工作区还没有生产任务。'),
          ),
        ...account.jobs.take(8).map((job) => CloudTaskTile(job: job)),
      ],
    ],
  );

  Widget _records(BuildContext context, CloudAccount account) {
    final records = [
      for (final job in account.jobs)
        for (final record in (job['inspections'] as List? ?? []))
          {
            ...Map<String, dynamic>.from(record as Map),
            'part_name': job['part_name'],
          },
    ];
    records.sort(
      (a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'),
    );
    return PageBody(
      children: [
        _workspace(context, account),
        const SizedBox(height: 24),
        Text(
          tr(context, '检测记录'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
        if (!account.signedIn)
          _loginState(context)
        else if (records.isEmpty)
          EmptyState(
            title: tr(context, '暂无检验记录'),
            subtitle: tr(context, '完成检验后可在这里查看记录。'),
          ),
        ...records.map(
          (r) => GlassPanel(
            child: ListTile(
              title: Text('${r['part_name']}'),
              subtitle: Text(
                '${cloudTimestamp(r['created_at'])}\n${r['note']}',
              ),
              leading: Icon(
                r['verdict'] == 'pass'
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: r['verdict'] == 'pass' ? green : red,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _templates(BuildContext context, CloudAccount account) => PageBody(
    children: [
      _workspace(context, account),
      const SizedBox(height: 24),
      Text(
        tr(context, '配方中心'),
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 16),
      if (!account.signedIn)
        _loginState(context)
      else
        EmptyState(
          title: tr(context, '暂无检查模板'),
          subtitle: tr(context, '当前工作区还没有检查模板。'),
        ),
    ],
  );

  Widget _profile(BuildContext context, CloudAccount account) => PageBody(
    children: [
      Text(tr(context, '我的'), style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 16),
      if (!account.signedIn)
        _loginState(context)
      else ...[
        GlassPanel(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                account.displayName.isEmpty
                    ? 'L'
                    : account.displayName.characters.first,
              ),
            ),
            title: Text(account.displayName),
            subtitle: Text('@${account.profile?['username'] ?? ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openPage(context, const CloudProfilePage()),
          ),
        ),
        if (account.workspaces.isNotEmpty)
          GlassPanel(
            child: DropdownButtonFormField<int>(
              initialValue: account.activeWorkspace?['id'] as int?,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(context, '工作区')),
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
        GlassPanel(
          child: ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(tr(context, '团队成员')),
            trailing: const Icon(Icons.chevron_right),
            onTap: account.activeWorkspace == null
                ? null
                : () => openPage(context, const CloudMembersPage()),
          ),
        ),
      ],
      GlassPanel(
        child: ListTile(
          leading: const Icon(Icons.language),
          title: const Text('语言 / Language'),
          onTap: () => chooseLanguage(context),
        ),
      ),
      if (account.signedIn)
        TextButton(
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
          child: Text(tr(context, '退出登录')),
        ),
    ],
  );
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
        const SizedBox(height: 28),
        const Center(child: BrandMark(size: 72)),
        const SizedBox(height: 28),
        Text(
          'LineSight',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 28),
        if (account.busy) const LinearProgressIndicator(),
        if (account.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
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
          onPressed: account.busy ? null : () => login(true),
          icon: const Icon(Icons.explore_outlined),
          label: Text(tr(context, '进入演示团队')),
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
          Center(
            child: FilledButton(
              onPressed: () => openPage(context, const CloudLoginPage()),
              child: Text(tr(context, '登录')),
            ),
          )
        else ...[
          Text('@${account.profile?['username'] ?? ''}'),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            enabled: !account.demoAccount && !account.busy,
            maxLength: 100,
            decoration: InputDecoration(labelText: tr(context, '显示名称')),
          ),
          if (!account.demoAccount) ...[
            FilledButton(
              onPressed: account.busy
                  ? null
                  : () => account.updateDisplayName(_name.text.trim()),
              child: Text(tr(context, '保存')),
            ),
            TextButton(
              onPressed: account.busy
                  ? null
                  : () => account.signIn(changePassword: true),
              child: Text(tr(context, '修改密码')),
            ),
          ],
          if (account.busy) const LinearProgressIndicator(),
          if (account.error != null)
            Text(
              trMessage(context, account.error!),
              style: const TextStyle(color: red),
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

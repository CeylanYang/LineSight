import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_layout.dart';
import '../cloud_feedback.dart';
import '../l10n.dart';
import '../ui.dart';
import 'cloud_business.dart';
import 'cloud_tasks.dart';
import 'cloud_profile_editor.dart';
import 'auth.dart';
import 'modules.dart';

class CloudConfigurationPage extends StatefulWidget {
  final int initialTab;
  final ValueChanged<int>? onTabChanged;
  const CloudConfigurationPage({
    super.key,
    this.initialTab = 0,
    this.onTabChanged,
  });
  @override
  State<CloudConfigurationPage> createState() => _CloudConfigurationState();
}

class _CloudConfigurationState extends State<CloudConfigurationPage> {
  late int tab = widget.initialTab;
  late final visited = <int>{tab};
  @override
  void didUpdateWidget(CloudConfigurationPage oldWidget) {
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
          labels: const ['打印配置', '检查模板'],
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
                CloudProfilesPage(
                  key: ValueKey(account.accessScope),
                  embedded: true,
                )
              else
                const SizedBox.shrink(),
              if (visited.contains(1))
                const CloudTemplatesPage(compact: true)
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

class CloudProfilesPage extends StatefulWidget {
  final bool picking, embedded;
  const CloudProfilesPage({
    super.key,
    this.picking = false,
    this.embedded = false,
  });
  @override
  State<CloudProfilesPage> createState() => _ProfilesState();
}

class _ProfilesState extends State<CloudProfilesPage> {
  String? binding;
  bool bound = false, loading = true;
  Object? failure;
  List<Map<String, dynamic>> profiles = [];
  final acknowledged = <String, Map<String, dynamic>>{};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      bound = true;
      binding = CloudScope.of(context).accessScope;
      load();
    }
  }

  Future<void> load() async {
    final account = CloudScope.of(context);
    if (!account.retainsAccess(binding)) return;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final result = await account.request(
        'GET',
        'workspaces/${account.activeWorkspace!['id']}/printer-profiles/',
      );
      account.requireAccess(binding);
      final rows = (result as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      if (mounted) {
        final merged = <String, Map<String, dynamic>>{
          for (final row in rows) '${row['id']}': row,
        };
        for (final entry in acknowledged.entries) {
          final remote = merged[entry.key];
          if (remote == null ||
              (entry.value['revision'] as int? ?? 0) >
                  (remote['revision'] as int? ?? 0)) {
            merged[entry.key] = entry.value;
          }
        }
        setState(
          () =>
              profiles = merged.values.toList()
                ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}')),
        );
      }
    } catch (error) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() => failure = error);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void accepted(Map<String, dynamic> result) {
    if (!mounted || !CloudScope.of(context).retainsAccess(binding)) return;
    acknowledged['${result['id']}'] = result;
    setState(() {
      profiles = [...profiles.where((p) => p['id'] != result['id']), result]
        ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    return DetailScaffold(
      embedded: widget.embedded,
      title: tr(context, widget.picking ? '选择打印配置' : '打印配置'),
      actions: [
        if (account.canManageProduction)
          IconButton(
            tooltip: tr(context, '创建打印配置'),
            icon: const Icon(Icons.add),
            onPressed: () {
              if (account.retainsAccess(binding)) {
                openPage(context, CloudProfileEditor(onSaved: accepted));
              }
            },
          ),
      ],
      children: [
        if (loading)
          const CloudLoadingPanel()
        else if (failure != null)
          CloudFailurePanel(failure: failure!, onRetry: load)
        else if (profiles.isEmpty)
          EmptyState(
            title: tr(context, '暂无打印配置'),
            subtitle: tr(context, '新建任务时也可手动填写设备。'),
          )
        else
          ...profiles.map(
            (profile) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassPanel(
                child: ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: Text('${profile['name']}'),
                  subtitle: Text(
                    '${profile['version']} · ${tr(context, profile['override'] == true ? '团队配置' : '内置配置')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (!account.retainsAccess(binding)) return;
                    final selected = await Navigator.of(context)
                        .push<Map<String, dynamic>>(
                          MaterialPageRoute(
                            builder: (_) => CloudProfileDetailPage(
                              profile: profile,
                              picking: widget.picking,
                              onSaved: accepted,
                            ),
                          ),
                        );
                    if (mounted &&
                        selected != null &&
                        account.retainsAccess(binding) &&
                        context.mounted) {
                      Navigator.pop(context, selected);
                    }
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CloudProfileDetailPage extends StatefulWidget {
  final Map<String, dynamic> profile;
  final bool picking;
  final ValueChanged<Map<String, dynamic>>? onSaved;
  const CloudProfileDetailPage({
    super.key,
    required this.profile,
    this.picking = false,
    this.onSaved,
  });
  @override
  State<CloudProfileDetailPage> createState() => _ProfileDetailState();
}

class _ProfileDetailState extends State<CloudProfileDetailPage> {
  late Map<String, dynamic> selected = widget.profile;
  void accepted(Map<String, dynamic> result) {
    if (!mounted || !CloudScope.of(context).retainsAccess(binding)) return;
    setState(() => selected = result);
    widget.onSaved?.call(result);
  }

  String? binding;
  bool bound = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!bound) {
      bound = true;
      binding = CloudScope.of(context).accessScope;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context), profile = selected;
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    return DetailScaffold(
      bottomBar: account.canEdit
          ? FilledButton.icon(
              onPressed: () {
                if (!account.retainsAccess(binding)) return;
                if (widget.picking) {
                  Navigator.pop(context, profile);
                } else {
                  openPage(
                    context,
                    CloudCreateTaskPage(initialProfile: profile),
                  );
                }
              },
              icon: const Icon(Icons.add_task),
              label: Text(tr(context, widget.picking ? '使用此配置' : '使用此配置创建任务')),
            )
          : null,
      title: '${profile['name']}',
      children: [
        HeroBanner(
          eyebrow: 'CONFIGURATION / MODULES',
          title: '${profile['name']}',
          subtitle:
              '${tr(context, profile['override'] == true ? '团队配置' : '内置配置')} · ${profile['version']}',
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, '配置来源'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SelectableText('${profile['source']}'),
              if ('${profile['note'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('${profile['note']}'),
              ],
            ],
          ),
        ),
        if (profile['default_template'] is Map)
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(tr(context, '默认检查模板')),
            subtitle: Text(
              '${profile['default_template']['name']} · v${profile['default_template']['version']}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              if (account.retainsAccess(binding)) {
                openPage(
                  context,
                  CloudTemplateDetailPage(
                    template: Map<String, dynamic>.from(
                      profile['default_template'] as Map,
                    ),
                  ),
                );
              }
            },
          ),
        if (account.canManageProduction)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (profile['override'] == true)
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(tr(context, '编辑打印配置')),
                  onPressed: () {
                    if (account.retainsAccess(binding)) {
                      openPage(
                        context,
                        CloudProfileEditor(profile: profile, onSaved: accepted),
                      );
                    }
                  },
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined),
                label: Text(tr(context, '复制打印配置')),
                onPressed: () {
                  if (account.retainsAccess(binding)) {
                    openPage(
                      context,
                      CloudProfileEditor(
                        profile: profile,
                        copy: true,
                        onSaved: accepted,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
      ],
    );
  }
}

/// Keep every descendant route inside the current local authorization boundary.
class LocalConfigurationGate extends StatefulWidget {
  const LocalConfigurationGate({super.key});
  @override
  State<LocalConfigurationGate> createState() => _LocalConfigurationState();
}

class _LocalConfigurationState extends State<LocalConfigurationGate> {
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  String? binding;
  @override
  Widget build(BuildContext context) {
    final local = AppScope.of(context);
    if (local.user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, '本机配方与工位'))),
        body: const AuthPage(),
      );
    }
    final next = '${local.session}/${local.user!.id}';
    if (binding != next) {
      binding = next;
      navigatorKey = GlobalKey<NavigatorState>();
    }
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (result) => navigatorKey.currentState?.pop(result),
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(tr(context, '本机配方与工位')),
              leading: BackButton(onPressed: () => Navigator.of(context).pop()),
            ),
            body: const Backdrop(child: ModulesPage()),
          ),
        ),
      ),
    );
  }
}

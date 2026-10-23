import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_feedback.dart';
import '../l10n.dart';
import '../ui.dart';
import 'cloud_business.dart';
import 'cloud_tasks.dart';
import 'auth.dart';
import 'modules.dart';

class CloudConfigurationPage extends StatelessWidget {
  const CloudConfigurationPage({super.key});
  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      PageHeading(
        eyebrow: 'CONFIGURATION / MODULES',
        title: tr(context, '配方中心'),
        subtitle: tr(context, '选择打印配置与检查模板，创建标准化生产任务。'),
      ),
      GlassPanel(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: Text(tr(context, '打印配置')),
              subtitle: Text(tr(context, '查看设备、配置版本与来源')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(context, const CloudProfilesPage()),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_input_component_outlined),
              title: Text(tr(context, '本机配方与工位')),
              subtitle: Text(tr(context, '配方、换型与系统 · 本机')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(context, const LocalConfigurationGate()),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(tr(context, '检查模板')),
              subtitle: Text(tr(context, '管理检查项与模板版本')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openPage(
                context,
                Scaffold(
                  appBar: AppBar(title: Text(tr(context, '检查模板'))),
                  body: const Backdrop(child: CloudTemplatesPage()),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class CloudProfilesPage extends StatefulWidget {
  final bool picking;
  const CloudProfilesPage({super.key, this.picking = false});
  @override
  State<CloudProfilesPage> createState() => _ProfilesState();
}

class _ProfilesState extends State<CloudProfilesPage> {
  String? binding;
  bool bound = false, loading = true;
  Object? failure;
  List<Map<String, dynamic>> profiles = [];
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
      if (mounted) setState(() => profiles = rows);
    } catch (error) {
      if (mounted && account.retainsAccess(binding)) {
        setState(() => failure = error);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    return DetailScaffold(
      title: tr(context, widget.picking ? '选择打印配置' : '打印配置'),
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
  const CloudProfileDetailPage({
    super.key,
    required this.profile,
    this.picking = false,
  });
  @override
  State<CloudProfileDetailPage> createState() => _ProfileDetailState();
}

class _ProfileDetailState extends State<CloudProfileDetailPage> {
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
    final account = CloudScope.of(context), profile = widget.profile;
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!account.retainsAccess(binding)) return cloudScopeChanged(context);
    return DetailScaffold(
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
        if (account.canEdit)
          FilledButton.icon(
            onPressed: () {
              if (!account.retainsAccess(binding)) return;
              if (widget.picking) {
                Navigator.pop(context, profile);
              } else {
                openPage(context, CloudCreateTaskPage(initialProfile: profile));
              }
            },
            icon: const Icon(Icons.add_task),
            label: Text(tr(context, widget.picking ? '使用此配置' : '使用此配置创建任务')),
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

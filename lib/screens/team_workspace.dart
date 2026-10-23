import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../models.dart';
import '../ui.dart';

const _dialogTransitionDelay = Duration(milliseconds: 300);

class TeamWorkspacePage extends StatefulWidget {
  const TeamWorkspacePage({super.key});
  @override
  State<TeamWorkspacePage> createState() => _TeamWorkspacePageState();
}

class _TeamWorkspacePageState extends State<TeamWorkspacePage> {
  late final String _serviceUrl;
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _workspaceName = TextEditingController();
  final _inviteCode = TextEditingController();
  String? _token;
  List<Map<String, dynamic>> _workspaces = [];
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _profiles = [];
  int _legacyCount = 0;
  Map<String, dynamic>? _pendingJobDraft;
  String? _pendingJobRequestId;
  int? _pendingJobWorkspaceId;
  List<Map<String, dynamic>> _legacyRecords = [];
  final Map<String, PlatformFile> _pendingUploads = {};
  Map<String, dynamic>? _active;
  bool _registering = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _token = CollaborationSession.token;
    _serviceUrl = kReleaseMode
        ? defaultCollaborationApi
        : CollaborationSession.serviceUrl ?? defaultCollaborationApi;
    if (_token != null) Future.microtask(() => _run(_loadWorkspaces));
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _workspaceName.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  CollaborationApi get _api => CollaborationApi(_serviceUrl, token: _token);

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } on CollaborationApiException catch (e) {
      if (mounted) {
        setState(() {
          if (e.status == 401) {
            _token = null;
            _active = null;
            _workspaces = [];
            _jobs = [];
            CollaborationSession.clear();
          }
          _error = e.status == 401
              ? tr(context, '团队登录已过期，请重新登录。')
              : trMessage(context, e.message);
        });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = trMessage(context, e.message));
    } catch (_) {
      if (mounted) setState(() => _error = tr(context, '操作未完成，请重试。'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authenticate() => _run(() async {
    final api = CollaborationApi(_serviceUrl);
    if (_registering) await api.register(_username.text.trim(), _password.text);
    final token = await api.login(_username.text.trim(), _password.text);
    _token = token;
    CollaborationSession.token = token;
    CollaborationSession.serviceUrl = _serviceUrl;
    await _loadWorkspaces();
  });

  Future<void> _loadWorkspaces() async {
    final rows = await _api.workspaces();
    if (!mounted) return;
    setState(() {
      _workspaces = rows;
      _active = null;
      _jobs = [];
    });
  }

  String _roleLabel(String role) => switch (role) {
    'owner' => tr(context, '团队管理员'),
    'operator' => tr(context, '操作成员'),
    'viewer' => tr(context, '只读成员'),
    _ => role,
  };

  String _displayTimestamp(Object? raw) {
    final value = DateTime.tryParse('${raw ?? ''}');
    return value == null ? '${raw ?? ''}' : stamp(value.toLocal());
  }

  void _signOut() => setState(() {
    _token = null;
    _workspaces = [];
    _active = null;
    _jobs = [];
    _members = [];
    _profiles = [];
    CollaborationSession.clear();
  });

  Future<void> _select(Map<String, dynamic> workspace) async {
    if (_pendingJobDraft != null && workspace['id'] != _pendingJobWorkspaceId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr(context, '先重试待提交任务，再切换团队。'))));
      return;
    }
    await _run(() async {
      final jobs = await _api.jobs(workspace['id'] as int);
      final members = await _api.members(workspace['id'] as int);
      final profiles = await _api.printerProfiles(workspace['id'] as int);
      final legacy = await _api.legacyInspectionStats(workspace['id'] as int);
      if (mounted) {
        setState(() {
          _active = workspace;
          _jobs = jobs;
          _members = members;
          _profiles = profiles;
          _legacyCount = legacy['count'] as int;
          _legacyRecords = (legacy['records'] as List)
              .cast<Map<String, dynamic>>();
        });
      }
    });
  }

  Future<void> _refreshJobs() async {
    final active = _active;
    if (active == null) return;
    final rows = await _api.jobs(active['id'] as int);
    if (mounted) setState(() => _jobs = rows);
  }

  Future<String?> _ask(
    String title, {
    String label = '名称',
    String initial = '',
    int max = 100,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, title)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: max,
          decoration: InputDecoration(labelText: tr(context, label)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(tr(context, '确认')),
          ),
        ],
      ),
    );
    await Future<void>.delayed(_dialogTransitionDelay);
    controller.dispose();
    return value;
  }

  Future<void> _createWorkspace() async {
    final name = _workspaceName.text.trim();
    if (name.isEmpty) return;
    await _run(() async {
      await _api.createWorkspace(name);
      await _loadWorkspaces();
    });
    if (_error == null) _workspaceName.clear();
  }

  Future<void> _redeem() async {
    final code = _inviteCode.text.trim();
    if (code.isEmpty) return;
    await _run(() async {
      await _api.redeem(code);
      _inviteCode.clear();
      await _loadWorkspaces();
    });
  }

  Future<void> _invite() async {
    final active = _active;
    if (active == null) return;
    var role = 'operator';
    final code = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(tr(context, '邀请团队成员')),
          content: DropdownButtonFormField<String>(
            initialValue: role,
            decoration: InputDecoration(labelText: tr(context, '成员权限')),
            items: [
              DropdownMenuItem(
                value: 'operator',
                child: Text(tr(context, '可编辑')),
              ),
              DropdownMenuItem(
                value: 'viewer',
                child: Text(tr(context, '仅查看')),
              ),
            ],
            onChanged: (value) => setDialog(() => role = value ?? 'operator'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, '取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, role),
              child: Text(tr(context, '生成邀请')),
            ),
          ],
        ),
      ),
    );
    if (code == null) return;
    await _run(() async {
      final invite = await _api.invite(active['id'] as int, code);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr(context, '邀请已生成')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(invite),
              const SizedBox(height: 12),
              Text(tr(context, '邀请仅可使用一次，并在 48 小时后失效。')),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: invite)),
              icon: const Icon(Icons.copy),
              label: Text(tr(context, '复制代码')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, '完成')),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _addProfile() async {
    final name = TextEditingController();
    final version = TextEditingController(text: '1');
    final source = TextEditingController();
    final note = TextEditingController();
    final active = _active;
    if (active == null) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, '添加团队配置')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: tr(context, '设备名称')),
              ),
              TextField(
                controller: version,
                decoration: InputDecoration(labelText: tr(context, '配置版本')),
              ),
              TextField(
                controller: source,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: tr(context, '配置来源 HTTPS 地址'),
                ),
              ),
              TextField(
                controller: note,
                maxLength: 300,
                decoration: InputDecoration(labelText: tr(context, '配置备注')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, '保存配置')),
          ),
        ],
      ),
    );
    await Future<void>.delayed(_dialogTransitionDelay);
    if (save == true) {
      await _run(() async {
        await _api.savePrinterProfile(active['id'] as int, {
          'name': name.text.trim(),
          'version': version.text.trim(),
          'source': source.text.trim(),
          'note': note.text.trim(),
        });
        final wsId = active['id'] as int;
        final jobs = await _api.jobs(wsId);
        final members = await _api.members(wsId);
        final profiles = await _api.printerProfiles(wsId);
        final legacy = await _api.legacyInspectionStats(wsId);
        if (mounted) {
          setState(() {
            _jobs = jobs;
            _members = members;
            _profiles = profiles;
            _legacyCount = legacy['count'] as int;
            _legacyRecords = (legacy['records'] as List)
                .cast<Map<String, dynamic>>();
          });
        }
      });
    }
    name.dispose();
    version.dispose();
    source.dispose();
    note.dispose();
  }

  Future<void> _createJob() async {
    final active = _active;
    if (active == null) return;
    final part = TextEditingController();
    final qty = TextEditingController(text: '1');
    final note = TextEditingController();
    var profileId = '${_profiles.first['id']}';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(tr(context, '新建生产任务')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: part,
                  decoration: InputDecoration(labelText: tr(context, '零件名称')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: profileId,
                  decoration: InputDecoration(labelText: tr(context, '打印机配置')),
                  items: _profiles
                      .map(
                        (p) => DropdownMenuItem(
                          value: '${p['id']}',
                          child: Text('${p['name']} · ${p['version']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialog(() => profileId = v ?? profileId),
                ),
                if (_profiles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${tr(context, '配置来源')}: ${_profiles.firstWhere((p) => '${p['id']}' == profileId)['source']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr(context, '数量')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLength: 500,
                  decoration: InputDecoration(labelText: tr(context, '交接备注')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(context, '取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(context, '创建任务')),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(_dialogTransitionDelay);
    if (result == true &&
        part.text.trim().isNotEmpty &&
        (int.tryParse(qty.text) ?? 0) > 0) {
      setState(() {
        _pendingJobDraft = {
          'part_name': part.text.trim(),
          'printer':
              '${_profiles.firstWhere((p) => '${p['id']}' == profileId)['name']}',
          'profile_id': profileId,
          'quantity': int.parse(qty.text),
          'note': note.text.trim(),
        };
        _pendingJobRequestId = '${uid()}${uid()}';
        _pendingJobWorkspaceId = active['id'] as int;
      });
      await _submitPendingJob();
    }
    part.dispose();
    qty.dispose();
    note.dispose();
  }

  Future<void> _submitPendingJob() async {
    final draft = _pendingJobDraft;
    final requestId = _pendingJobRequestId;
    final active = _active;
    if (draft == null || requestId == null || active == null) return;
    await _run(() async {
      await _api.createJob(active['id'] as int, draft, requestId);
      if (mounted) {
        setState(() {
          _pendingJobDraft = null;
          _pendingJobRequestId = null;
          _pendingJobWorkspaceId = null;
        });
      }
      await _refreshJobs();
    });
  }

  Future<void> _transition(Map<String, dynamic> job, String next) async {
    final active = _active!;
    if (next == 'exception') {
      final result = await _issueDialog();
      if (result == null || result.$1.isEmpty) return;
      await _run(() async {
        await _api.qualityDecision(
          active['id'] as int,
          job['id'] as String,
          verdict: 'fail',
          note: result.$1,
          assignee: result.$2,
        );
        await _refreshJobs();
      });
    } else if (next == 'closed' && job['status'] == 'inspection') {
      await _run(() async {
        await _api.qualityDecision(
          active['id'] as int,
          job['id'] as String,
          verdict: 'pass',
        );
        await _refreshJobs();
      });
    } else {
      await _run(() async {
        await _api.updateJob(active['id'] as int, job['id'] as String, next);
        await _refreshJobs();
      });
    }
  }

  Future<(String, String)?> _issueDialog() async {
    final note = TextEditingController();
    String assignee = '';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(tr(context, '记录质检异常')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: note,
                maxLength: 500,
                decoration: InputDecoration(labelText: tr(context, '问题说明')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: assignee,
                decoration: InputDecoration(labelText: tr(context, '指派给')),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr(context, '暂不指派'))),
                  ..._members.map(
                    (m) => DropdownMenuItem(
                      value: '${m['username']}',
                      child: Text(
                        '${m['username']} · ${_roleLabel('${m['role']}')}',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setDialog(() => assignee = value ?? ''),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr(context, '取消')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (note.text.trim(), assignee)),
              child: Text(tr(context, '提交异常')),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(_dialogTransitionDelay);
    note.dispose();
    return result;
  }

  Future<void> _resolve(
    Map<String, dynamic> job,
    Map<String, dynamic> issue,
    String next,
  ) async {
    final resolution = await _ask('处理结果', label: '处理说明', max: 500);
    if (resolution == null || resolution.isEmpty) return;
    await _run(() async {
      await _api.resolveException(
        _active!['id'] as int,
        issue['id'] as int,
        resolution,
        next,
      );
      await _refreshJobs();
    });
  }

  Future<void> _upload(Map<String, dynamic> job) async {
    final jobId = job['id'] as String;
    var file = _pendingUploads[jobId];
    if (file == null) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return;
      file = result.files.single;
      _pendingUploads[jobId] = file;
    }
    if (file.bytes!.length > 10 * 1024 * 1024) {
      _pendingUploads.remove(jobId);
      if (mounted) {
        setState(() => _error = tr(context, '图片需为 PNG/JPEG，且不超过 10 MB、16 MP。'));
      }
      return;
    }
    final active = _active!;
    final selected = file;
    await _run(() async {
      await _api.uploadImage(
        active['id'] as int,
        jobId,
        selected.name,
        selected.bytes!,
      );
      _pendingUploads.remove(jobId);
      await _refreshJobs();
    });
  }

  Future<void> _showPreview(Map<String, dynamic> job, int evidenceId) async {
    final original = await _api.original(
      _active!['id'] as int,
      job['id'] as String,
      evidenceId,
    );
    final bytes = await _api.preview(
      _active!['id'] as int,
      job['id'] as String,
      evidenceId,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(tr(context, '边缘辅助预览')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(context, '原始照片'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Image.memory(
                Uint8List.fromList(original),
                fit: BoxFit.contain,
                height: 220,
              ),
              const SizedBox(height: 16),
              Text(
                tr(context, '边缘参考'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Image.memory(
                Uint8List.fromList(bytes),
                fit: BoxFit.contain,
                height: 220,
              ),
              const SizedBox(height: 12),
              Text(tr(context, '预览用于辅助观察，质检结果由你确认。')),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, '完成')),
          ),
        ],
      ),
    );
  }

  Future<void> _previewLegacyImport() async {
    final store = AppScope.of(context);
    if (!store.engineer || store.user?.enabled != true) {
      setState(() => _error = tr(context, '请先登录本机工程师或管理员账户，再导入。'));
      return;
    }
    late final List<Inspection> local;
    try {
      local = store.captureTeamImport();
    } on StateError catch (e) {
      setState(() => _error = trMessage(context, e.message));
      return;
    }
    final localSession = store.session;
    var includeSamples = false;
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          if (store.session != localSession ||
              !store.engineer ||
              store.user?.enabled != true) {
            return AlertDialog(
              title: Text(tr(context, '本机授权已失效')),
              content: Text(tr(context, '请先登录本机工程师或管理员账户，再导入。')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr(context, '取消')),
                ),
              ],
            );
          }
          return StatefulBuilder(
            builder: (context, setDialog) {
              final selected =
                  local.where((x) => includeSamples || !x.sample).toList()
                    ..sort((a, b) => a.at.compareTo(b.at));
              final passed = selected.where((x) => x.finalPassed).length;
              return AlertDialog(
                title: Text(tr(context, '导入本机质检记录？')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, '将创建团队记录副本，本机记录保持不变。')),
                    const SizedBox(height: 12),
                    Text(tr(context, '记录数：{0}', [selected.length])),
                    Text(
                      tr(context, '合格：{0} · 异常：{1}', [
                        passed,
                        selected.length - passed,
                      ]),
                    ),
                    if (selected.isNotEmpty)
                      Text(
                        '${stamp(selected.last.at).split(' ').first} — ${stamp(selected.first.at).split(' ').first}',
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: includeSamples,
                      onChanged: (value) =>
                          setDialog(() => includeSamples = value ?? false),
                      title: Text(tr(context, '包含示例记录')),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr(context, '取消')),
                  ),
                  FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, true),
                    child: Text(tr(context, '导入记录')),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
    if (choice != true) return;
    final records = local
        .where((x) => includeSamples || !x.sample)
        .map((x) => x.toJson())
        .toList();
    await _run(() async {
      final wsId = _active!['id'] as int;
      store.requireSession(localSession, elevated: true);
      final result = await _api.importLegacyInspections(
        wsId,
        records,
        includeSamples: includeSamples,
        authorizeLocal: () =>
            store.requireSession(localSession, elevated: true),
      );
      final stats = await _api.legacyInspectionStats(wsId);
      if (mounted) {
        setState(() {
          _legacyCount = stats['count'] as int;
          _legacyRecords = (stats['records'] as List)
              .cast<Map<String, dynamic>>();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(context, '已导入 {0} 条，跳过 {1} 条', [
                result['imported'],
                result['skipped'],
              ]),
            ),
          ),
        );
      }
    });
  }

  Future<void> _manageMember(Map<String, dynamic> member, String action) async {
    final active = _active;
    if (active == null) return;
    final username = '${member['username']}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, action == 'remove' ? '移除成员？' : '修改成员权限？')),
        content: Text(
          action == 'remove'
              ? tr(context, '移除 {0} 后，该成员将立即失去本团队的访问权限。', [username])
              : tr(context, '将 {0} 的权限改为 {1}，立即生效。', [
                  username,
                  _roleLabel(action),
                ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, '确认')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final id = active['id'] as int;
      if (action == 'remove') {
        await _api.removeMember(id, username);
      } else {
        await _api.changeMemberRole(id, username, action);
      }
      final rows = await _api.members(id);
      if (mounted && _active?['id'] == id) setState(() => _members = rows);
    });
  }

  Future<void> _leaveWorkspace() async {
    final active = _active;
    if (active == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, '离开团队？')),
        content: Text(tr(context, '离开后将失去本团队数据的访问权限，需要新的邀请才能重新加入。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, '离开团队')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _api.leaveWorkspace(active['id'] as int);
      if (!mounted) return;
      setState(() {
        _active = null;
        _jobs = [];
        _members = [];
        _profiles = [];
        _legacyRecords = [];
        _legacyCount = 0;
      });
      await _loadWorkspaces();
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return DetailScaffold(
      title: tr(context, '团队协作'),
      children: [
        Text(
          tr(context, '创建或加入团队，共同跟进生产任务与质检异常。'),
          style: const TextStyle(height: 1.5),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          GlassPanel(
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: red),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!)),
                IconButton(
                  onPressed: () => setState(() => _error = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_token == null) ..._authForm(),
        if (_token != null && active == null) ..._workspacePicker(),
        if (active != null) ..._workspaceJobs(active),
      ],
    );
  }

  List<Widget> _authForm() => [
    const SizedBox(height: 16),
    GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(context, '连接团队工作区'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: InputDecoration(labelText: tr(context, '用户名')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: tr(context, '密码（至少 12 位）')),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _registering = !_registering),
              child: Text(tr(context, _registering ? '已有团队账户？登录' : '创建团队账户')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _authenticate,
              icon: Icon(_registering ? Icons.person_add_alt_1 : Icons.login),
              label: Text(tr(context, _registering ? '创建并登录' : '登录团队账户')),
            ),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _workspacePicker() => [
    const SizedBox(height: 18),
    GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, '你的团队'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => _run(_loadWorkspaces),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_workspaces.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(tr(context, '你还没有加入团队。创建工作区，或输入邀请代码加入。')),
            ),
          ..._workspaces.map(
            (ws) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.groups_outlined, color: blue),
              title: Text('${ws['name']}'),
              subtitle: Text(
                tr(context, '团队权限：{0}', [_roleLabel('${ws['role']}')]),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _select(ws),
            ),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _workspaceName,
                  decoration: InputDecoration(labelText: tr(context, '新团队名称')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _busy ? null : _createWorkspace,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _inviteCode,
            decoration: InputDecoration(
              labelText: tr(context, '邀请代码'),
              suffixIcon: IconButton(
                onPressed: _busy ? null : _redeem,
                icon: const Icon(Icons.login),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _signOut,
              child: Text(tr(context, '退出团队账户')),
            ),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _workspaceJobs(Map<String, dynamic> active) {
    final role = '${active['role']}';
    final canEdit = role != 'viewer';
    return [
      const SizedBox(height: 16),
      GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _pendingJobDraft != null
                      ? null
                      : () => setState(() {
                          _active = null;
                          _jobs = [];
                        }),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    '${active['name']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Tag(_roleLabel(role), color: green),
                IconButton(
                  onPressed: _busy ? null : () => _run(_refreshJobs),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Text(tr(context, '团队任务与质检记录只对本工作区成员开放。')),
            if (role == 'owner')
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _invite,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(tr(context, '邀请成员')),
                ),
              ),
            if (role == 'owner')
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _addProfile,
                  icon: const Icon(Icons.tune),
                  label: Text(tr(context, '添加团队配置')),
                ),
              ),
            if (canEdit)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _previewLegacyImport,
                  icon: const Icon(Icons.move_to_inbox_outlined),
                  label: Text(
                    tr(context, '导入本机质检记录 · 团队已有 {0} 条', [_legacyCount]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (_legacyRecords.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: GlassPanel(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    title: Text(tr(context, '已导入的质检记录（{0}）', [_legacyCount])),
                    children: _legacyRecords
                        .map(
                          (record) => ListTile(
                            leading: Icon(
                              record['passed'] == true
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_rounded,
                              color: record['passed'] == true ? green : red,
                            ),
                            title: Text(
                              '${record['recipe'].toString().isEmpty ? tr(context, '质检记录') : record['recipe']}',
                            ),
                            subtitle: Text(
                              '${record['serial']} · ${record['at']}',
                            ),
                            trailing: record['sample'] == true
                                ? Tag(tr(context, '示例记录'))
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (_members.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, '团队成员'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                ..._members.map(
                  (member) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.person_outline, color: blue),
                    title: Text('${member['username']}'),
                    subtitle: Text(_roleLabel('${member['role']}')),
                    trailing: role != 'owner'
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: tr(context, '管理成员'),
                            enabled: !_busy,
                            onSelected: (action) =>
                                _manageMember(member, action),
                            itemBuilder: (context) => [
                              for (final value in [
                                'owner',
                                'operator',
                                'viewer',
                              ])
                                PopupMenuItem(
                                  value: value,
                                  child: Text(_roleLabel(value)),
                                ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text(tr(context, '移除成员')),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _busy || _pendingJobDraft != null ? null : _leaveWorkspace,
          icon: const Icon(Icons.logout),
          label: Text(tr(context, '离开团队')),
        ),
      ),
      const SizedBox(height: 12),
      if (canEdit)
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy || _profiles.isEmpty
                ? null
                : _pendingJobDraft == null
                ? _createJob
                : _submitPendingJob,
            icon: Icon(_pendingJobDraft == null ? Icons.add : Icons.refresh),
            label: Text(
              tr(context, _pendingJobDraft == null ? '新建团队任务' : '重试创建任务'),
            ),
          ),
        ),
      if (_jobs.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: EmptyState(
            title: tr(context, '暂无团队任务'),
            subtitle: tr(context, '创建一项任务，团队成员即可共同跟进。'),
          ),
        ),
      ..._jobs.map(
        (job) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _jobCard(job, canEdit),
        ),
      ),
    ];
  }

  Widget _jobCard(Map<String, dynamic> job, bool canEdit) {
    final status = '${job['status']}';
    final statusLabel = switch (status) {
      'queued' => '待打印',
      'printing' => '打印中',
      'inspection' => '待质检',
      'exception' => '异常处理中',
      _ => '已关闭',
    };
    final actions = <Widget>[];
    void action(String next, String label, IconData icon) => actions.add(
      OutlinedButton.icon(
        onPressed: _busy || !canEdit ? null : () => _transition(job, next),
        icon: Icon(icon, size: 18),
        label: Text(tr(context, label)),
      ),
    );
    if (canEdit) {
      switch (status) {
        case 'queued':
          action('printing', '开始打印', Icons.play_arrow);
          break;
        case 'printing':
          action('inspection', '打印完成，送检', Icons.fact_check_outlined);
          break;
        case 'inspection':
          actions.add(
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr(context, '图片需为 PNG/JPEG，且不超过 10 MB、16 MP。'),
                style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
            ),
          );
          final pendingUpload = _pendingUploads.containsKey(job['id']);
          actions.add(
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _upload(job),
              icon: Icon(
                pendingUpload ? Icons.refresh : Icons.add_a_photo_outlined,
                size: 18,
              ),
              label: Text(tr(context, pendingUpload ? '重试上传' : '添加质检图片')),
            ),
          );
          action('closed', '质检通过并关闭', Icons.check_circle_outline);
          action('exception', '发现异常', Icons.report_gmailerrorred_outlined);
          break;
        case 'exception':
          final issues = (job['exceptions'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
          final open = issues.where((x) => x['status'] == 'open').toList();
          if (open.isNotEmpty) {
            actions.add(
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _resolve(job, open.first, 'inspection'),
                icon: const Icon(Icons.replay, size: 18),
                label: Text(tr(context, '处理后重新送检')),
              ),
            );
            actions.add(
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _resolve(job, open.first, 'closed'),
                icon: const Icon(Icons.task_alt, size: 18),
                label: Text(tr(context, '处理并关闭')),
              ),
            );
          }
          break;
      }
    }
    final evidence = (job['evidence'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final issues = (job['exceptions'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final inspections = (job['inspections'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${job['part_name']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Tag(
                tr(context, statusLabel),
                color: status == 'exception'
                    ? red
                    : status == 'closed'
                    ? green
                    : blue,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${job['printer']} · ${tr(context, '{0} 件', [job['quantity']])}',
          ),
          if ('${job['profile_version']}'.isNotEmpty)
            Text(
              '${tr(context, '配置版本')}: ${job['profile_version']} · ${tr(context, '配置来源')}: ${job['profile_source']}',
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          if ('${job['note']}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${job['note']}'),
            ),
          ...inspections.map(
            (x) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${tr(context, '质检结果')}: ${tr(context, x['verdict'] == 'pass' ? '合格' : '异常')} · ${_displayTimestamp(x['created_at'])}${'${x['note']}'.isEmpty ? '' : ' · ${x['note']}'}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
          ),
          ...issues.map(
            (x) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${tr(context, '异常')}: ${x['note']}${'${x['assignee']}'.isEmpty ? '' : ' · ${tr(context, '指派给')}: ${x['assignee']}'}${'${x['resolution']}'.isEmpty ? '' : ' · ${x['resolution']}'}',
              ),
            ),
          ),
          if (evidence.isNotEmpty)
            Wrap(
              spacing: 8,
              children: evidence
                  .map(
                    (x) => TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() => _showPreview(job, x['id'] as int)),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(tr(context, '查看照片与边缘参考 #{0}', [x['id']])),
                    ),
                  )
                  .toList(),
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

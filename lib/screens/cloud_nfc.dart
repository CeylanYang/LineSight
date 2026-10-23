import 'package:flutter/material.dart';
import '../cloud_account.dart';
import '../cloud_feedback.dart';
import '../collaboration_api.dart';
import '../l10n.dart';
import '../nfc_client.dart';
import '../nfc_reader.dart';
import '../ui.dart';
import 'cloud_tasks.dart';
import 'cloud_shell.dart';

class CloudNfcScanPage extends StatefulWidget {
  final bool binding;
  final NfcCardReader? reader;
  const CloudNfcScanPage({super.key, this.binding = false, this.reader});
  @override
  State<CloudNfcScanPage> createState() => _CloudNfcScanPageState();
}

class _CloudNfcScanPageState extends State<CloudNfcScanPage>
    with WidgetsBindingObserver {
  late final reader = widget.reader ?? NfcCardReader();
  bool busy = false, initialize = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.binding) scan();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      generation++;
      reader.stop();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    reader.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> scan() async {
    if (busy) return;
    final ticket = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final card = await reader.scan(initializeEmptyCard: initialize);
      if (mounted && ticket == generation && card != null) {
        Navigator.pop(context, card);
      }
    } on CollaborationApiException catch (failure) {
      if (mounted && ticket == generation) {
        setState(() => error = failure.message);
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() => error = '无法读取此卡片，请重试');
      }
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DetailScaffold(
    title: tr(context, widget.binding ? '绑定卡片' : '刷卡登录'),
    children: [
      const SizedBox(height: 24),
      const Icon(Icons.nfc_rounded, size: 96, color: blue),
      const SizedBox(height: 24),
      Text(
        tr(context, '将卡片靠近手机背面'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 12),
      Text(
        tr(context, widget.binding ? '读取卡片后，将与当前账户绑定。' : '读取已绑定的卡片，登录你的工作区。'),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            trMessage(context, error!),
            textAlign: TextAlign.center,
            style: const TextStyle(color: red),
          ),
        ),
      if (widget.binding)
        CheckboxListTile(
          value: initialize,
          onChanged: busy
              ? null
              : (value) => setState(() => initialize = value ?? false),
          title: Text(tr(context, '初始化空白NDEF卡')),
          subtitle: Text(tr(context, '仅写入空白卡片，保留已有卡片内容。')),
        ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: busy ? null : scan,
        icon: const Icon(Icons.nfc),
        label: Text(tr(context, busy ? '正在读卡' : '开始读卡')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, '取消')),
      ),
    ],
  );
}

class CloudNfcCardsPage extends StatefulWidget {
  final NfcClient? client;
  const CloudNfcCardsPage({super.key, this.client});
  @override
  State<CloudNfcCardsPage> createState() => _CloudNfcCardsPageState();
}

class _CloudNfcCardsPageState extends State<CloudNfcCardsPage> {
  List<Map<String, dynamic>> rows = [];
  bool busy = false, initialized = false;
  String? binding;
  Object? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      binding = CloudScope.of(context).identityScope;
      if (binding != null) load();
    }
  }

  bool current(CloudAccount account) =>
      binding != null && binding == account.identityScope;
  Future<void> load() async {
    final account = CloudScope.of(context);
    if (!current(account)) return;
    setState(() {
      busy = true;
      error = null;
      rows = [];
    });
    try {
      final result =
          (await account.request('GET', 'auth/nfc/credentials/') as List)
              .cast<Map<String, dynamic>>();
      if (mounted && current(account)) setState(() => rows = result);
    } catch (failure) {
      if (mounted && current(account)) setState(() => error = failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> bind() async {
    final account = CloudScope.of(context);
    final card = await Navigator.of(context).push<NfcCardRead>(
      MaterialPageRoute(builder: (_) => const CloudNfcScanPage(binding: true)),
    );
    if (!mounted || card == null || !current(account)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await (widget.client ?? NfcClient(apiUrl: account.apiUrl)).bind(
        (method, path, {body}) => account.request(method, path, body: body),
        cardCode: card.code,
        technology: card.technology,
        label: 'NFC ${rows.length + 1}',
      );
      if (mounted && current(account)) await load();
    } catch (failure) {
      if (mounted && current(account)) setState(() => error = failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(Map<String, dynamic> row) async {
    final account = CloudScope.of(context);
    if (!await confirm(
          context,
          tr(context, '解除卡片绑定？'),
          tr(context, '此卡片的刷卡登录和会话将失效。'),
        ) ||
        !mounted ||
        !current(account)) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await account.request('DELETE', 'auth/nfc/credentials/${row['id']}/');
      if (mounted && current(account)) await load();
    } catch (failure) {
      if (mounted && current(account)) setState(() => error = failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = CloudScope.of(context);
    if (!account.signedIn) return cloudAccessRequired(context);
    if (!current(account)) return cloudScopeChanged(context);
    return DetailScaffold(
      title: tr(context, '我的卡片'),
      children: [
        HeroBanner(
          eyebrow: 'NFC · QUICK ACCESS',
          title: tr(context, '刷卡进入工作区'),
          subtitle: tr(context, '绑定后，可在本机使用卡片登录。'),
          trailing: const Icon(Icons.nfc, size: 40, color: Colors.white),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : bind,
          icon: const Icon(Icons.add_card),
          label: Text(tr(context, '绑定卡片')),
        ),
        const SizedBox(height: 16),
        if (busy) const CloudLoadingPanel(),
        if (error != null) ...[
          CloudFailurePanel(failure: error!, onRetry: load),
          if (error is CollaborationApiException &&
              (error as CollaborationApiException).status == 403)
            TextButton(
              onPressed: () => openPage(context, const CloudLoginPage()),
              child: Text(tr(context, '使用账户重新登录')),
            ),
        ],
        if (!busy && error == null && rows.isEmpty)
          EmptyState(
            icon: Icons.nfc,
            title: tr(context, '还没有绑定卡片'),
            subtitle: tr(context, '绑定一张卡片，快速登录当前账户。'),
          ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassPanel(
              child: ListTile(
                leading: const Icon(Icons.nfc, color: blue),
                title: Text('${row['label']}'),
                subtitle: Text(tr(context, '已绑定此账户')),
                trailing: IconButton(
                  onPressed: busy ? null : () => revoke(row),
                  tooltip: tr(context, '解除绑定'),
                  icon: const Icon(Icons.link_off),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

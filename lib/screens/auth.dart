import '../l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui.dart';
import '../language_selector.dart';
import 'team_workspace.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final username = TextEditingController(),
      name = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController(),
      code = TextEditingController();
  bool hidden = true, examples = true, recovery = false, created = false;
  bool? initialSetup;
  @override
  void dispose() {
    for (final c in [username, name, password, repeat, code]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final first = (initialSetup ??= s.users.isEmpty) && !created;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: LayoutBuilder(
                builder: (context, c) => Row(
                  children: [
                    if (c.maxWidth > 780)
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const BrandMark(size: 66),
                              const SizedBox(height: 32),
                              Text(
                                tr(context, '每一处细节，尽在眼前。'),
                                style: const TextStyle(
                                  fontSize: 54,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                  letterSpacing: -2,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                tr(context, "让每一次检测，都有迹可循。"),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 40),
                              const PartPreview(height: 260),
                              const SizedBox(height: 24),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  Tag(tr(context, "本地保存"), color: green),
                                  Tag(tr(context, "质量工作台")),
                                  Tag(tr(context, "角色权限")),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Align(
                                alignment: Alignment.centerRight,
                                child: LanguageSelector(),
                              ),
                              if (c.maxWidth <= 780) ...[
                                const BrandMark(size: 56),
                                const SizedBox(height: 28),
                              ],
                              Text(
                                tr(context, 'LineSight · 质量工作区'),
                                style: const TextStyle(
                                  color: blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                recovery
                                    ? tr(context, "找回本机账户")
                                    : first
                                    ? tr(context, "准备好，看见细节。")
                                    : tr(context, "欢迎回到工作台"),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                recovery
                                    ? tr(context, "使用创建账户时保存的恢复码，设置新密码。")
                                    : first
                                    ? tr(context, "创建此设备的管理员账户，开始管理你的产线。")
                                    : tr(context, "登录本机账户，继续你的质量工作。"),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 30),
                              if (!first && s.lockReason != null) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: GlassPanel(
                                    child: Text(
                                      trMessage(context, s.lockReason!),
                                      style: const TextStyle(height: 1.6),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                              TextField(
                                controller: username,
                                autofillHints: const [AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: tr(context, "用户名"),
                                  prefixIcon: const Icon(Icons.person_outline),
                                  helperText: tr(
                                    context,
                                    "3–32 位字母、数字、点、横线或下划线",
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (first) ...[
                                TextField(
                                  controller: name,
                                  maxLength: 40,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: tr(context, "显示名称"),
                                    prefixIcon: const Icon(
                                      Icons.badge_outlined,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (recovery) ...[
                                TextField(
                                  controller: code,
                                  decoration: InputDecoration(
                                    labelText: tr(context, "账户恢复码"),
                                    prefixIcon: const Icon(Icons.key_outlined),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextField(
                                controller: password,
                                obscureText: hidden,
                                autofillHints: first || recovery
                                    ? const [AutofillHints.newPassword]
                                    : const [AutofillHints.password],
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: first || recovery
                                      ? tr(context, "设置密码（至少 8 位）")
                                      : tr(context, "密码"),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: hidden
                                        ? tr(context, "显示密码")
                                        : tr(context, "隐藏密码"),
                                    onPressed: () =>
                                        setState(() => hidden = !hidden),
                                    icon: Icon(
                                      hidden
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (first || recovery) ...[
                                TextField(
                                  controller: repeat,
                                  obscureText: true,
                                  decoration: InputDecoration(
                                    labelText: tr(context, "再次输入密码"),
                                    prefixIcon: const Icon(Icons.lock_reset),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (first)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: examples,
                                  onChanged: (v) =>
                                      setState(() => examples = v!),
                                  title: Text(tr(context, "加入示例检测数据")),
                                  subtitle: Text(
                                    tr(context, "为工作区加入示例记录，可随时清理"),
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: BusyButton(
                                  label: recovery
                                      ? tr(context, "重设密码")
                                      : first
                                      ? tr(context, "创建本地工作区")
                                      : tr(context, "登录工作台"),
                                  icon: Icons.arrow_forward_rounded,
                                  onPressed: () async {
                                    if ((first || recovery) &&
                                        password.text != repeat.text) {
                                      throw StateError('两次密码输入不一致');
                                    }
                                    if (recovery) {
                                      await s.recover(
                                        username.text,
                                        code.text,
                                        password.text,
                                      );
                                      if (context.mounted) {
                                        setState(() => recovery = false);
                                        password.clear();
                                        repeat.clear();
                                        toast(
                                          context,
                                          tr(context, "密码已更新，请重新登录"),
                                        );
                                      }
                                    } else if (first) {
                                      final recoveryCode = await s.register(
                                        username.text,
                                        name.text,
                                        password.text,
                                        examples: examples,
                                      );
                                      if (!context.mounted) {
                                        return;
                                      }
                                      await showRecoveryCode(
                                        context,
                                        recoveryCode,
                                      );
                                      if (context.mounted) {
                                        try {
                                          await s.login(
                                            username.text,
                                            password.text,
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => created = true);
                                          }
                                        }
                                      }
                                    } else {
                                      await s.login(
                                        username.text,
                                        password.text,
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: () => openPage(context, const TeamWorkspacePage()),
                                icon: const Icon(Icons.groups_outlined),
                                label: Text(tr(context, '登录或加入团队工作区')),
                              ),
                              if (!first)
                                Align(
                                  alignment: Alignment.center,
                                  child: TextButton(
                                    onPressed: () =>
                                        setState(() => recovery = !recovery),
                                    child: Text(
                                      recovery
                                          ? tr(context, "返回登录")
                                          : tr(context, "忘记密码？使用恢复码"),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 22),
                              GlassPanel(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.verified_user_outlined,
                                      color: green,
                                      size: 21,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        tr(
                                          context,
                                          "账户与业务数据保存在此设备。首次创建者为管理员，后续成员由管理员添加。",
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          height: 1.7,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: Text(
                                  'LineSight $appVersion  ·  ${tr(context, "为现场质量团队而设")}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showRecoveryCode(BuildContext context, String code) async {
  bool saved = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(tr(context, "保存账户恢复码")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, "这是密码丢失后恢复账户的凭据，仅在此显示一次。请存放在安全位置。")),
              const SizedBox(height: 20),
              SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (c.mounted) toast(c, tr(context, "恢复码已复制"));
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(tr(context, "复制恢复码")),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: saved,
                onChanged: (v) => setState(() => saved = v!),
                title: Text(tr(context, "我已保存恢复码")),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: saved ? () => Navigator.pop(c) : null,
              child: Text(tr(context, "继续")),
            ),
          ],
        ),
      ),
    ),
  );
}

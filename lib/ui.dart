import 'l10n.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'store.dart';

const appVersion = '1.1.25';

const blue = Color(0xFF3478F6),
    green = Color(0xFF139D83),
    red = Color(0xFFDD566C),
    amber = Color(0xFFD49022);

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child})
    : super(notifier: store);
  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

ThemeData appTheme(bool dark) {
  final scheme = ColorScheme.fromSeed(
    seedColor: blue,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(primary: dark ? const Color(0xFF8EB8FF) : blue, secondary: green);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF0D1524)
        : const Color(0xFFF3F6FC),
  );
  return base.copyWith(
    textTheme: base.textTheme
        .apply(fontFamily: 'sans-serif')
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.3,
            color: scheme.onSurface,
          ),
          headlineSmall: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
            color: scheme.onSurface,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: base.scaffoldBackgroundColor,
      foregroundColor: scheme.onSurface,
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : scheme.onSurface,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: blue.withValues(alpha: .12),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .4),
      space: 1,
    ),
  );
}

class Backdrop extends StatelessWidget {
  final Widget child;
  const Backdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF5F8FF), Color(0xFFFBFCFE), Color(0xFFF3FAF8)],
      ),
    ),
    child: child,
  );
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
  });
  @override
  Widget build(BuildContext context) {
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFDBE5F2)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: panel);
  }
}

class PageBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const PageBody({super.key, required this.children, this.maxWidth = 1100});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          22,
          24,
          22,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: children,
      ),
    ),
  );
}

class DetailScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children, actions;
  const DetailScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: Backdrop(child: PageBody(maxWidth: 1000, children: children)),
  );
}

class PageHeading extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final Widget? trailing;
  const PageHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  String _localizedEyebrow(BuildContext context) {
    if (Localizations.localeOf(context).languageCode == 'en') return eyebrow;
    const labels = {
      'TRACEABILITY / AUDIT': '质量追溯 · 操作日志',
      'AUDIT / EVENT': '日志详情',
      'CONFIGURATION / MODULES': '配置管理 · 配方与工位',
      'CHANGEOVER / SETUP': '工位换型',
      'STATION / CONFIGURATION': '工位配置',
      'QUALITY / INBOX': '质量复核 · 待办',
      'TRACEABILITY / RECORDS': '质量追溯 · 检测记录',
      'INSPECTION / EVIDENCE': '检测记录 · 证据详情',
      'ACCESS / LOCAL TEAM': '账户权限 · 成员管理',
      'ACCESS / NEW MEMBER': '账户权限 · 添加成员',
      'DATA / LOCAL STORAGE': '数据管理 · 存储',
      'DATA / TIME': '数据管理 · 时间范围',
      'LOCAL / RECOVERY': '数据恢复',
      'RECOVERY / BACKUP': '数据恢复 · 备份',
      'RECOVERY / CONFIRM': '数据恢复 · 确认',
      'RECOVERY / HISTORY': '数据恢复 · 历史记录',
      'RECOVERY / ORIGINAL': '数据恢复 · 原始文件',
      'ANALYTICS / QUALITY': '质量统计 · 分析',
      'DATA / CSV': '数据导出 · CSV',
      'DATA / BACKUP': '数据管理 · 备份',
      'DATA / VERIFY': '数据校验',
    };
    final mapped = labels[eyebrow];
    if (mapped != null) return mapped;
    if (eyebrow.startsWith('RECIPE / ')) return '配方 · ${eyebrow.substring(9)}';
    if (eyebrow.endsWith(' / INSPECTION')) {
      return '${eyebrow.substring(0, eyebrow.length - 13)} · 检测';
    }
    if (eyebrow.startsWith('LINESIGHT / ')) {
      return 'LineSight · ${eyebrow.substring(12)}';
    }
    return eyebrow;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localizedEyebrow(context),
          style:
              const TextStyle(
                color: blue,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ).copyWith(
                letterSpacing:
                    Localizations.localeOf(context).languageCode == 'en'
                    ? 2.5
                    : 1.2,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeading(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        );
        if (action != null && constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 8), action!],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            if (action != null) action!,
          ],
        );
      },
    ),
  );
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, this.color = blue});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).brightness == Brightness.dark
            ? Color.lerp(color, Colors.white, .35)
            : color,
      ),
    ),
  );
}

class Metric extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const Metric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = blue,
  });
  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  const AdaptiveGrid({super.key, required this.children, this.minWidth = 290});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final count = (c.maxWidth / (minWidth + 12)).floor().clamp(1, 4);
      final width = (c.maxWidth - (count - 1) * 12) / count;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((w) => SizedBox(width: width, child: w))
            .toList(),
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  @override
  Widget build(BuildContext context) => GlassPanel(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(icon, size: 48, color: blue.withValues(alpha: .6)),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    ),
  );
}

class InfoRow extends StatelessWidget {
  final String label, value;
  const InfoRow(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class BusyButton extends StatefulWidget {
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  const BusyButton({super.key, required this.label, this.onPressed, this.icon});
  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy || widget.onPressed == null
        ? null
        : () async {
            setState(() => busy = true);
            await perform(context, widget.onPressed!);
            if (mounted) setState(() => busy = false);
          },
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon ?? Icons.arrow_forward_rounded, size: 18),
    label: Text(busy ? tr(context, "处理中…") : widget.label),
  );
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) toast(context, success);
    return true;
  } catch (e) {
    if (context.mounted) {
      toast(
        context,
        e is StateError
            ? e.message.toString()
            : e is FormatException
            ? e.message
            : tr(context, "操作未完成，请检查文件或存储空间后重试"),
      );
    }
    return false;
  }
}

void toast(BuildContext context, String text) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(trMessage(context, text))));
void openPage(BuildContext context, Widget page) {
  final s = AppScope.of(context);
  s.feedback();
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  final reduced = s.reduceMotion || MediaQuery.of(context).disableAnimations;
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      pageBuilder: (_, animation, secondaryAnimation) => page,
      transitionDuration: Duration(milliseconds: reduced ? 0 : 240),
      reverseTransitionDuration: Duration(milliseconds: reduced ? 0 : 180),
      transitionsBuilder: (_, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(.025, .015),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String confirmLabel = '确认',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr(context, "取消")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(trMessage(c, confirmLabel)),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> inputDialog(
  BuildContext context, {
  required String title,
  String label = '内容',
  String initial = '',
  bool secret = false,
  int maxLength = 500,
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: secret,
        maxLength: maxLength,
        minLines: secret ? 1 : 2,
        maxLines: secret ? 1 : 4,
        decoration: InputDecoration(labelText: trMessage(c, label)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(tr(context, "取消")),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, controller.text),
          child: Text(tr(context, "保存")),
        ),
      ],
    ),
  );
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return value;
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 48});
  @override
  Widget build(BuildContext context) => Semantics(
    label: tr(context, "LineSight 标志"),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5699FF), Color(0xFF2862E6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * .29),
        boxShadow: [
          BoxShadow(
            color: blue.withValues(alpha: .24),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: CustomPaint(painter: _BrandPainter()),
    ),
  );
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * .055
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(s.width * .38, s.height * .26)
      ..lineTo(s.width * .25, s.height * .26)
      ..lineTo(s.width * .25, s.height * .4)
      ..moveTo(s.width * .62, s.height * .26)
      ..lineTo(s.width * .75, s.height * .26)
      ..lineTo(s.width * .75, s.height * .4)
      ..moveTo(s.width * .25, s.height * .62)
      ..lineTo(s.width * .25, s.height * .75)
      ..lineTo(s.width * .38, s.height * .75)
      ..moveTo(s.width * .62, s.height * .75)
      ..lineTo(s.width * .75, s.height * .75)
      ..lineTo(s.width * .75, s.height * .62);
    canvas.drawPath(path, p);
    canvas.drawCircle(Offset(s.width * .5, s.height * .5), s.width * .12, p);
    canvas.drawLine(
      Offset(s.width * .17, s.height * .5),
      Offset(s.width * .83, s.height * .5),
      p..strokeWidth = s.width * .025,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PartPreview extends StatelessWidget {
  final bool defect;
  final double height;
  const PartPreview({super.key, this.defect = false, this.height = 220});
  @override
  Widget build(BuildContext context) => Semantics(
    label: defect ? tr(context, "工件预览，右上方标记缺陷区域") : tr(context, "工件表面预览"),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _PartPainter(defect),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tag(tr(context, "缺陷图示")),
                const Spacer(),
                OverflowBar(
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 12,
                  overflowSpacing: 8,
                  children: [
                    Tag(
                      defect ? tr(context, "检测到缺陷") : tr(context, "表面完整"),
                      color: defect ? red : green,
                    ),
                    const Text(
                      'CAM 01 / TOP',
                      style: TextStyle(
                        color: Color(0xFF98AECA),
                        fontSize: 10,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PartPainter extends CustomPainter {
  final bool defect;
  _PartPainter(this.defect);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF13253D), Color(0xFF0B1727)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & s),
    );
    final grid = Paint()
      ..color = const Color(0xFF7196C2).withValues(alpha: .1)
      ..strokeWidth = 1;
    for (double x = 0; x < s.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    for (double y = 0; y < s.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    canvas.save();
    canvas.translate(s.width / 2, s.height / 2);
    final scale = min(s.width / 300, s.height / 200);
    canvas.scale(scale);
    canvas.rotate(-.2);
    final part = Path()
      ..moveTo(-78, -42)
      ..lineTo(36, -42)
      ..lineTo(79, -8)
      ..lineTo(79, 42)
      ..lineTo(-78, 42)
      ..close();
    canvas.drawShadow(part, Colors.black, 14, true);
    canvas.drawPath(
      part,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE0E9F0), Color(0xFF70879D), Color(0xFFAFC2D3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(const Rect.fromLTWH(-80, -45, 160, 90)),
    );
    canvas.drawPath(
      part,
      Paint()
        ..color = const Color(0xFFDDE8F1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final x in [-49.0, 42.0]) {
      canvas.drawCircle(
        Offset(x, 6),
        13,
        Paint()..color = const Color(0xFF27394C),
      );
      canvas.drawCircle(
        Offset(x, 6),
        15,
        Paint()
          ..color = const Color(0xFFEBF2F7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (defect) {
      canvas.drawLine(
        const Offset(10, -30),
        const Offset(37, -14),
        Paint()
          ..color = const Color(0xFF572832)
          ..strokeWidth = 3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, -40, 49, 41),
          const Radius.circular(5),
        ),
        Paint()
          ..color = red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PartPainter old) => old.defect != defect;
}

import 'l10n.dart';
import 'package:flutter/material.dart';
import 'store.dart';

const appVersion = '1.1.58';

const blue = Color(0xFF3478F6),
    green = Color(0xFF139D83),
    red = Color(0xFFDD566C),
    amber = Color(0xFFD49022);

const ink = Color(0xFF122036),
    muted = Color(0xFF6A7B93),
    hairline = Color(0xFFE4ECF7),
    panelShadow = Color(0x14132E55);

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
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -.3,
        color: ink,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: const BorderSide(color: hairline),
      ),
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      selectedColor: blue.withValues(alpha: .12),
      checkmarkColor: blue,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: hairline)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
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
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF4F8FF), Color(0xFFFBFCFE), Color(0xFFF2FAF7)],
          ),
        ),
      ),
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1.05, -1.1),
              radius: 1.15,
              colors: [Color(0x223478F6), Color(0x003478F6)],
            ),
          ),
        ),
      ),
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.15, 1.25),
              radius: 1.1,
              colors: [Color(0x1813B39A), Color(0x0013B39A)],
            ),
          ),
        ),
      ),
      child,
    ],
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
        border: Border.all(color: hairline),
        boxShadow: const [
          BoxShadow(color: panelShadow, blurRadius: 26, offset: Offset(0, 10)),
        ],
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
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            narrow ? 18 : 22,
            narrow ? 18 : 24,
            narrow ? 18 : 22,
            (narrow ? 108 : 32) + MediaQuery.paddingOf(context).bottom,
          ),
          children: children,
        ),
      ),
    );
  }
}

class DetailScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children, actions;
  final bool embedded;
  final Widget? bottomBar;
  const DetailScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.embedded = false,
    this.bottomBar,
  });
  @override
  Widget build(BuildContext context) {
    final body = Backdrop(child: PageBody(maxWidth: 1000, children: children));
    if (embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: body,
      bottomNavigationBar: bottomBar == null
          ? null
          : Material(
              color: Colors.white,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  child: bottomBar!,
                ),
              ),
            ),
    );
  }
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: MediaQuery.sizeOf(context).width < 420 ? 30 : null,
                  height: 1.12,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(color: muted, height: 1.55, fontSize: 13.5),
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

class SectionHeader extends StatelessWidget {
  final String title;
  final String? caption;
  final IconData? icon;
  final Widget? action;
  const SectionHeader(
    this.title, {
    super.key,
    this.caption,
    this.icon,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: blue.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: blue),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  letterSpacing: -.2,
                ),
              ),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    caption!,
                    style: const TextStyle(fontSize: 11.5, color: muted),
                  ),
                ),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class HeroBanner extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final List<Widget> actions;
  final Widget? trailing;
  const HeroBanner({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B4FC4), Color(0xFF3F7EF2), Color(0xFF5B97FF)],
        stops: [0, .58, 1],
      ),
      boxShadow: [
        BoxShadow(
          color: blue.withValues(alpha: .28),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Stack(
        children: [
          Positioned(
            right: -46,
            top: -70,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .09),
              ),
            ),
          ),
          Positioned(
            right: 54,
            bottom: -74,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        eyebrow,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .76),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .82),
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 17),
                  Wrap(spacing: 9, runSpacing: 9, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class HeroAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool ghost;
  const HeroAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.ghost = false,
  });
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 17),
    label: Text(label),
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      backgroundColor: ghost
          ? Colors.white.withValues(alpha: .16)
          : Colors.white,
      foregroundColor: ghost ? Colors.white : const Color(0xFF1B4FC4),
      side: ghost
          ? BorderSide(color: Colors.white.withValues(alpha: .26))
          : BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: TextStyle(
        fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = blue,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hairline),
        boxShadow: const [
          BoxShadow(color: panelShadow, blurRadius: 22, offset: Offset(0, 8)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 13, 11, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 31,
                  height: 31,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: color),
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 27,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return onTap == null ? card : Semantics(button: true, child: card);
  }
}

class QuickAction extends StatelessWidget {
  final String title;
  final String caption;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  const QuickAction({
    super.key,
    required this.title,
    required this.caption,
    required this.icon,
    required this.onPressed,
    this.color = blue,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: hairline),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: muted),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFFA9B8CC),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class MenuTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;
  const MenuTile({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.color = blue,
    this.onTap,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ),
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right,
                  size: 19,
                  color: Color(0xFFA9B8CC),
                ),
          ],
        ),
      ),
    ),
  );
}

class InfoGrid extends StatelessWidget {
  final Map<String, String> items;
  const InfoGrid({super.key, required this.items});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 720 ? 3 : 2;
      final width = (c.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items.entries
            .map(
              (e) => SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FAFF),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFEDF3FB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: muted),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        e.value.isEmpty ? '—' : e.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
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
    if (context.mounted && success != null) {
      AppScope.of(context).feedback(kind: AppFeedback.success);
      toast(context, success);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      AppScope.of(context).feedback(kind: AppFeedback.warning);
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
  Navigator.of(context).push(appPageRoute<void>(context, page));
}

PageRoute<T> appPageRoute<T>(BuildContext context, Widget page) {
  final s = AppScope.of(context);
  final reduced = s.reduceMotion || MediaQuery.of(context).disableAnimations;
  return PageRouteBuilder<T>(
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

const partArtKeys = [
  'mount',
  'cover',
  'clip',
  'gear',
  'knob',
  'jig',
  'hinge',
  'pulley',
  'spacer',
  'clamp',
  'housing',
  'adapter',
];

String partArtKey(String name) {
  final n = name.toLowerCase();
  for (final rule in const <(List<String>, String)>[
    (['gear', '齿轮'], 'gear'),
    (['knob', '旋钮', '手柄', '拨盘'], 'knob'),
    (['jig', 'fixture', '治具', '检具', '夹具', '工装'], 'jig'),
    (['hinge', '铰链', '合页'], 'hinge'),
    (['pulley', '滑轮', '带轮', '同步轮'], 'pulley'),
    (['spacer', 'standoff', '垫块', '隔套', '支柱'], 'spacer'),
    (['clamp', '线夹', '管夹', '夹箍', '卡箍'], 'clamp'),
    (['housing', '箱体', '机壳', '壳体'], 'housing'),
    (['adapter', 'flange', '转接', '法兰', '接头'], 'adapter'),
    (['cover', 'lid', '外壳', '盖', '罩', '面板'], 'cover'),
    (['clip', '卡扣', '卡子', '夹'], 'clip'),
    (['mount', 'bracket', '支架', '底座', '安装'], 'mount'),
  ]) {
    if (rule.$1.any(n.contains)) return rule.$2;
  }
  final sum = name.codeUnits.fold<int>(0, (a, b) => a + b);
  return partArtKeys[sum % partArtKeys.length];
}

String partArtAsset(String name, {bool wide = false, bool edge = false}) =>
    'assets/parts/part-${partArtKey(name)}${edge ? '-edge' : ''}${wide ? '-wide' : ''}.webp';

class PartThumb extends StatelessWidget {
  final String partName;
  final double size;
  final bool defect;
  final double radius;
  const PartThumb({
    super.key,
    required this.partName,
    this.size = 60,
    this.defect = false,
    this.radius = 15,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: tr(context, '工件照片'),
    child: SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              partArtAsset(partName),
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xFFEAF1FA),
                child: Icon(Icons.view_in_ar_outlined, color: blue),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: const Color(0x1A122036)),
              ),
            ),
            if (defect)
              const Positioned(
                right: 5,
                top: 5,
                child: _Dot(color: red, size: 8),
              ),
          ],
        ),
      ),
    ),
  );
}

class PartArt extends StatelessWidget {
  final String partName;
  final bool defect;
  final bool wide;
  final bool showTags;
  final double? height;
  final double radius;
  final String? caption;
  const PartArt({
    super.key,
    required this.partName,
    this.defect = false,
    this.wide = false,
    this.showTags = true,
    this.height,
    this.radius = 20,
    this.caption,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: defect ? tr(context, '工件实拍，标记缺陷区域') : tr(context, '工件实拍'),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              partArtAsset(partName, wide: wide),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF13253D), Color(0xFF0B1727)],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.view_in_ar_outlined,
                    color: Colors.white54,
                    size: 44,
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x59071018),
                      Color(0x00071018),
                      Color(0x00071018),
                      Color(0x66101828),
                    ],
                    stops: [0, .3, .62, 1],
                  ),
                ),
              ),
            ),
            if (defect)
              Positioned.fill(
                child: CustomPaint(
                  painter: _DefectMarker(partArtKey(partName)),
                ),
              ),
            if (showTags)
              Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _GlassTag(
                            text: tr(context, '工件预览'),
                            icon: Icons.center_focus_strong,
                          ),
                          if (caption != null) ...[
                            const SizedBox(width: 8),
                            _GlassTag(text: caption!),
                          ],
                        ],
                      ),
                    ),
                    const Spacer(),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SolidTag(
                            text: tr(context, defect ? '边缘参考' : '外观参考'),
                            color: defect ? red : green,
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
  );
}

class PartPreview extends StatelessWidget {
  final bool defect;
  final double height;
  final String part;
  const PartPreview({
    super.key,
    this.defect = false,
    this.height = 220,
    this.part = 'mount',
  });
  @override
  Widget build(BuildContext context) =>
      PartArt(partName: part, defect: defect, height: height);
}

class _GlassTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  const _GlassTag({required this.text, this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: .5)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: ink),
          const SizedBox(width: 5),
        ],
        Text(
          text,
          style: const TextStyle(
            color: ink,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .3,
          ),
        ),
      ],
    ),
  );
}

class _SolidTag extends StatelessWidget {
  final String text;
  final Color color;
  const _SolidTag({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .35),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;
  const _Dot({required this.color, this.size = 10});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
    ),
  );
}

class _DefectMarker extends CustomPainter {
  final String art;
  _DefectMarker(this.art);
  static const _boxes = {
    'mount': Rect.fromLTWH(.40, .36, .22, .26),
    'cover': Rect.fromLTWH(.42, .42, .22, .18),
    'clip': Rect.fromLTWH(.36, .40, .24, .26),
    'gear': Rect.fromLTWH(.40, .38, .21, .25),
    'knob': Rect.fromLTWH(.40, .36, .21, .26),
    'jig': Rect.fromLTWH(.36, .39, .26, .22),
    'hinge': Rect.fromLTWH(.44, .40, .16, .26),
    'pulley': Rect.fromLTWH(.40, .36, .22, .26),
    'spacer': Rect.fromLTWH(.42, .34, .18, .32),
    'clamp': Rect.fromLTWH(.38, .38, .23, .25),
    'housing': Rect.fromLTWH(.40, .38, .23, .24),
    'adapter': Rect.fromLTWH(.40, .38, .22, .26),
  };
  @override
  void paint(Canvas canvas, Size s) {
    final box = _boxes[art] ?? _boxes['mount']!;
    final rect = Rect.fromLTWH(
      box.left * s.width,
      box.top * s.height,
      box.width * s.width,
      box.height * s.height,
    );
    final line = Paint()
      ..color = red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      halo,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      line,
    );
    final label = TextPainter(
      text: const TextSpan(
        text: ' DEFECT 0.82 mm ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = Offset(
      (rect.right - label.width).clamp(0, s.width - label.width),
      (rect.top - label.height - 6).clamp(0, s.height - label.height),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(origin & label.size, const Radius.circular(5)),
      Paint()..color = red,
    );
    label.paint(canvas, origin + const Offset(0, 0));
  }

  @override
  bool shouldRepaint(_DefectMarker old) => old.art != art;
}

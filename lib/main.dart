import 'liquid_glass_bar.dart';
import 'l10n.dart';
import 'dart:ui' show FrameTiming;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'store.dart';
import 'ui.dart';
import 'screens/auth.dart';
import 'screens/dashboard.dart';
import 'screens/records.dart';
import 'screens/modules.dart';
import 'screens/settings.dart';
import 'screens/storage_recovery.dart';
import 'screens/startup.dart';
import 'startup_trace.dart';

Future<void> main() async {
  final trace = startupTraceEnabled ? StartupTrace() : null;
  trace?.mark('dart-main');
  WidgetsFlutterBinding.ensureInitialized();
  trace?.mark('binding-ready');
  if (trace != null) {
    var recordedFrames = 0;
    void recordFrames(List<FrameTiming> timings) {
      for (final timing in timings) {
        if (recordedFrames == 3) break;
        trace.frame(timing);
        recordedFrames++;
      }
      if (recordedFrames == 3) {
        WidgetsBinding.instance.removeTimingsCallback(recordFrames);
      }
    }

    WidgetsBinding.instance.addTimingsCallback(recordFrames);
  }
  final store = AppStore();
  void traceState() => trace?.mark(
    'store-state',
    stage: store.startupStage,
    ready: store.ready,
    failed: store.startupError != null,
  );
  if (trace != null) store.addListener(traceState);
  runApp(
    LineSightApp(
      store: store,
      showBrandReveal: true,
      revealStartAfter: WidgetsBinding.instance.waitUntilFirstFrameRasterized,
    ),
  );
  trace?.mark('run-app');
  if (trace != null) {
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
      (_) => trace.mark('first-frame-rasterized'),
    );
  }
  try {
    await store.init();
  } finally {
    if (trace != null) store.removeListener(traceState);
    trace?.mark(
      'store-init-finished',
      ready: store.ready,
      failed: store.startupError != null,
    );
  }
}

class LineSightApp extends StatefulWidget {
  final AppStore store;
  final bool? showBrandReveal;
  final Future<void>? revealStartAfter;
  const LineSightApp({
    super.key,
    required this.store,
    this.showBrandReveal,
    this.revealStartAfter,
  });
  @override
  State<LineSightApp> createState() => _LineSightAppState();
}

class _LineSightAppState extends State<LineSightApp>
    with WidgetsBindingObserver {
  // Both themes depend only on fixed design tokens. Reuse them across store
  // progress, data updates and navigator resets; theme mode still follows state.
  late final ThemeData _lightTheme = appTheme(false);
  late final ThemeData _darkTheme = appTheme(true);
  late bool _revealFinished;

  @override
  void initState() {
    super.initState();
    // Preinitialized test/embedded workspaces do not replay the cold-start brand.
    _revealFinished = !(widget.showBrandReveal ?? !widget.store.ready);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.store.backgrounded();
    }
    if (state == AppLifecycleState.resumed) widget.store.resumed();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    store: widget.store,
    child: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final s = widget.store;
        return MaterialApp(
          key: ValueKey(s.session),
          title: 'LineSight',
          debugShowCheckedModeBanner: false,
          locale: s.languageCode == 'en'
              ? const Locale('en')
              : const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations:
                  s.reduceMotion || MediaQuery.of(context).disableAnimations,
            ),
            child: child!,
          ),
          home: s.startupError != null
              ? s.recoveryUser == null
                    ? const StorageFailurePage()
                    : const StorageRecoveryPage()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    // Build/layout the next screen while the reveal owns visibility.
                    if (s.ready)
                      Offstage(
                        offstage: !_revealFinished,
                        child: TickerMode(
                          enabled: _revealFinished,
                          child: ExcludeFocus(
                            excluding: !_revealFinished,
                            child: s.user == null
                                ? const AuthPage()
                                : const AppShell(),
                          ),
                        ),
                      ),
                    if (!_revealFinished || !s.ready)
                      StartupPage(
                        key: const ValueKey('cold-start-reveal'),
                        animate: !_revealFinished,
                        startAfter: widget.revealStartAfter,
                        onRevealComplete: () {
                          if (mounted && !_revealFinished) {
                            setState(() => _revealFinished = true);
                          }
                        },
                      ),
                  ],
                ),
        );
      },
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final labels = [
      tr(context, "工作台"),
      tr(context, "检测记录"),
      tr(context, "配方中心"),
      tr(context, "我的"),
    ];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.fact_check_outlined,
      Icons.layers_outlined,
      Icons.person_outline_rounded,
    ];
    final pages = [
      DashboardPage(onRecords: () => setState(() => tab = 1)),
      const RecordsPage(),
      const ModulesPage(),
      const SettingsPage(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    void select(int i) {
      s.feedback();
      setState(() => tab = i);
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
                      scrollable: true,
                      backgroundColor: Colors.transparent,
                      selectedIndex: tab,
                      onDestinationSelected: select,
                      labelType: NavigationRailLabelType.all,
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
                child: IndexedStack(index: tab, children: pages),
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
              selectedIndex: tab,
              onSelected: select,
              glass: s.glass,
            ),
    );
  }
}

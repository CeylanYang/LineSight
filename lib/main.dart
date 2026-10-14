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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  runApp(LineSightApp(store: store));
  await store.init();
}

class LineSightApp extends StatefulWidget {
  final AppStore store;
  const LineSightApp({super.key, required this.store});
  @override
  State<LineSightApp> createState() => _LineSightAppState();
}

class _LineSightAppState extends State<LineSightApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
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
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: appTheme(false),
          darkTheme: appTheme(true),
          themeMode: s.dark ? ThemeMode.dark : ThemeMode.light,
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
              : !s.ready
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : s.user == null
              ? const AuthPage()
              : const AppShell(),
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
    const labels = ['工作台', '检测记录', '配方中心', '我的'];
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
          : GlassPanel(
              radius: 0,
              padding: EdgeInsets.zero,
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                height: 72,
                selectedIndex: tab,
                onDestinationSelected: select,
                destinations: List.generate(
                  4,
                  (i) => NavigationDestination(
                    icon: Icon(icons[i]),
                    label: labels[i],
                  ),
                ),
              ),
            ),
    );
  }
}

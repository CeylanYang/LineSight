import 'dart:async';
import 'presentation/aurora_input.dart';
import 'package:flutter/foundation.dart';
import 'presentation/presentation_config.dart';
import 'presentation/presentation_controller.dart';
import 'presentation/presentation_layer.dart';
import 'editions/special/special_content.dart';
import 'editions/special/special_interaction.dart';
import 'editions/special/special_theme.dart';
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
import 'screens/production.dart';
import 'editions/special/special_workbench.dart';
import 'screens/storage_recovery.dart';
import 'screens/startup.dart';
import 'startup_trace.dart';
import 'cloud_account.dart';
import 'cloud_navigation.dart';
import 'cloud_trace.dart';
import 'screens/cloud_shell.dart';
import 'ota_update.dart';
import 'runtime_errors.dart';
import 'runtime_content.dart';
import 'editions/edition_host.dart';

Future<void> main() async {
  installRuntimeErrorPrivacy();
  final trace = startupTraceEnabled ? StartupTrace() : null;
  trace?.mark('dart-main');
  WidgetsFlutterBinding.ensureInitialized();
  await OtaUpdates.instance.initialize();
  await RuntimeContent.instance.initialize();
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
  final cloud = CloudAccount();
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
      cloud: cloud,
      showBrandReveal: true,
      revealStartAfter: WidgetsBinding.instance.waitUntilFirstFrameRasterized,
    ),
  );
  trace?.mark('run-app');
  // Download alongside startup work; activation requires a later cold start.
  OtaUpdates.instance.check();
  RuntimeContent.instance.refresh();
  if (trace != null) {
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
      (_) => trace.mark('first-frame-rasterized'),
    );
  }
  try {
    await Future.wait([store.init(), cloud.restore()]);
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
  final CloudAccount? cloud;
  final bool? showBrandReveal;
  final Future<void>? revealStartAfter;
  final PresentationController? presentationController;
  const LineSightApp({
    super.key,
    required this.store,
    this.cloud,
    this.showBrandReveal,
    this.revealStartAfter,
    this.presentationController,
  });
  @override
  State<LineSightApp> createState() => _LineSightAppState();
}

class _LineSightAppState extends State<LineSightApp>
    with WidgetsBindingObserver {
  // Both themes depend only on fixed design tokens. Reuse them across store
  // progress, data updates and navigator resets; theme mode still follows state.
  late final ThemeData _lightTheme = appTheme(false);
  late final _specialTheme = specialTheme(_lightTheme);
  final _specialInteraction = SpecialInteractionController();
  late final _presentation =
      widget.presentationController ?? PresentationController();
  late final AuroraInputBridge _auroraInput;

  void _syncPresentation() => _presentation.update(
    settings: PresentationConfig.fromRuntime(RuntimeContent.instance.data),
    ready:
        _revealFinished &&
        widget.store.ready &&
        widget.store.startupError == null,
    special: widget.store.specialEdition,
    signedIn: widget.cloud?.signedIn ?? (widget.store.user != null),
    interactiveLoginRevision: widget.cloud?.interactiveLoginRevision,
  );

  @override
  Future<bool> didPopRoute() async {
    if (!_presentation.auroraVisible && !_presentation.adVisible) return false;
    _specialInteraction.suppressFor(const Duration(milliseconds: 700));
    _presentation.dismissAurora();
    _presentation.skipAd();
    return true;
  }

  late final _specialObserver = SpecialNavigationObserver(_specialInteraction);
  late final ThemeData _darkTheme = appTheme(true);
  late bool _revealFinished;
  final _cloudNavigator = GlobalKey<NavigatorState>();
  final _cloudTabs = ValueNotifier<int>(0);
  String? _pendingTrace;

  void _openPendingTrace() {
    if (_pendingTrace == null ||
        !_revealFinished ||
        !widget.store.ready ||
        widget.cloud == null ||
        widget.store.startupError != null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _pendingTrace == null ||
          _cloudNavigator.currentState == null) {
        return;
      }
      final link = _pendingTrace!;
      _pendingTrace = null;
      _cloudNavigator.currentState!.push(
        appPageRoute<void>(
          _cloudNavigator.currentContext!,
          BatchTrace.parse(link) != null
              ? CloudBatchTracePage(trace: BatchTrace.parse(link)!)
              : CloudTracePage(link: link),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final link = routeInformation.uri.toString();
    if (widget.cloud == null ||
        (!TaskTrace.isLink(link) && !BatchTrace.isLink(link))) {
      return false;
    }
    _pendingTrace = link;
    _openPendingTrace();
    return true;
  }

  @override
  Future<bool> didPushRoute(String route) =>
      didPushRouteInformation(RouteInformation(uri: Uri.parse(route)));

  Timer? _workspaceSyncTimer;
  bool _syncForeground = true;

  @override
  void initState() {
    super.initState();
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks(
        ['Aurora (Flutter adaptation)'],
        'Aurora by tornikegomareli. MIT License, as declared in the upstream README.\n'
        'https://github.com/tornikegomareli/Aurora\n'
        'Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the Software), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n'
        'The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n'
        'THE SOFTWARE IS PROVIDED AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.',
      );
    });
    // Preinitialized test/embedded workspaces do not replay the cold-start brand.
    _revealFinished = !(widget.showBrandReveal ?? !widget.store.ready);
    final initialLink =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (TaskTrace.isLink(initialLink) || BatchTrace.isLink(initialLink)) {
      _pendingTrace = initialLink;
    }
    WidgetsBinding.instance.addObserver(this);
    widget.store.addListener(_syncPresentation);
    widget.cloud?.addListener(_syncPresentation);
    _workspaceSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_syncForeground) widget.cloud?.syncWorkspace();
    });
    RuntimeContent.instance.addListener(_syncPresentation);
    _syncPresentation();
    _auroraInput = AuroraInputBridge(
      _presentation,
      onDismissInteraction: () =>
          _specialInteraction.suppressFor(const Duration(milliseconds: 700)),
    );
  }

  @override
  void dispose() {
    _workspaceSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.store.removeListener(_syncPresentation);
    widget.cloud?.removeListener(_syncPresentation);
    RuntimeContent.instance.removeListener(_syncPresentation);
    _auroraInput.dispose();
    if (widget.presentationController == null) {
      _presentation.dispose();
    }
    _cloudTabs.dispose();
    _specialInteraction.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncForeground = state == AppLifecycleState.resumed;
    if (_syncForeground) widget.cloud?.syncWorkspace();
    _presentation.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.store.backgrounded();
    }
    if (state == AppLifecycleState.resumed) {
      widget.store.resumed();
      RuntimeContent.instance.refresh();
    }
  }

  @override
  Widget build(BuildContext context) => AppScope(
    store: widget.store,
    child: ListenableBuilder(
      listenable: Listenable.merge([widget.store, RuntimeContent.instance]),
      builder: (context, _) {
        final s = widget.store;
        _specialInteraction.configure(s.specialEdition);
        _openPendingTrace();
        final app = MaterialApp(
          key: ValueKey(widget.cloud == null ? s.session : 'cloud'),
          title: 'LineSight',
          navigatorKey: widget.cloud == null ? null : _cloudNavigator,
          initialRoute: '/',
          debugShowCheckedModeBanner: false,
          locale: s.languageCode == 'en'
              ? const Locale('en')
              : const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: s.specialEdition ? _specialTheme : _lightTheme,
          navigatorObservers: [_specialObserver],
          darkTheme: _darkTheme,
          themeMode: ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations:
                  s.reduceMotion || MediaQuery.of(context).disableAnimations,
            ),
            child: PresentationLayer(
              controller: _presentation,
              reduceMotion:
                  s.reduceMotion || MediaQuery.of(context).disableAnimations,
              onPassThroughInteraction: () => _specialInteraction.suppressFor(
                const Duration(milliseconds: 700),
              ),
              child: SpecialInteractionLayer(
                controller: _specialInteraction,
                child: child!,
              ),
            ),
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
                            child: widget.cloud != null
                                ? const EditionHost(child: CloudShell())
                                : s.user == null
                                ? const AuthPage()
                                : const EditionHost(child: AppShell()),
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
                            _syncPresentation();
                          }
                        },
                      ),
                  ],
                ),
        );
        return widget.cloud == null
            ? app
            : CloudNavigationScope(
                controller: _cloudTabs,
                child: CloudScope(account: widget.cloud!, child: app),
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
  bool? _previousSpecial;
  int tab = 0;
  static const _specialTabs = <String>['工作台', '生产', '质检', '配置', '我的'];
  static const _specialTabAssets = <String>[
    'workbench',
    'production',
    'inspect',
    'config',
    'me',
  ];

  Widget _specialTabIcon(int i, bool selected) => Image.asset(
    'assets/checkcheck/icons/tab_${_specialTabAssets[i]}'
    '${selected ? '_active' : ''}.png',
    width: 26,
    height: 26,
    filterQuality: FilterQuality.high,
  );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final special = s.specialEdition;
    if (_previousSpecial != null && _previousSpecial != special) {
      tab = special ? [0, 2, 3, 4][tab] : [0, 0, 1, 2, 3][tab];
    }
    _previousSpecial = special;
    final labels = special
        ? _specialTabs.map((x) => tr(context, x)).toList()
        : [
            tr(context, "工作台"),
            tr(context, "检测记录"),
            tr(context, "配方中心"),
            tr(context, "我的"),
          ];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.factory_outlined,
      Icons.fact_check_outlined,
      Icons.tune_rounded,
      Icons.person_outline_rounded,
    ];
    const sharedIcons = [
      Icons.space_dashboard_outlined,
      Icons.fact_check_outlined,
      Icons.layers_outlined,
      Icons.person_outline_rounded,
    ];
    final pages = special
        ? [
            SpecialWorkbenchPage(
              onRecords: () => setState(() => tab = 2),
              onTemplates: () => setState(() => tab = 3),
            ),
            const ProductionPage(),
            const RecordsPage(key: ValueKey('shared-records')),
            const ModulesPage(key: ValueKey('shared-modules')),
            const SettingsPage(key: ValueKey('shared-settings')),
          ]
        : [
            DashboardPage(onRecords: () => setState(() => tab = 1)),
            const RecordsPage(key: ValueKey('shared-records')),
            const ModulesPage(key: ValueKey('shared-modules')),
            const SettingsPage(key: ValueKey('shared-settings')),
          ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    void select(int i) {
      s.feedback();
      setState(() => tab = i);
    }

    return Scaffold(
      extendBody: !wide,
      backgroundColor: const Color(0xFFF4F8FF),
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
                        labels.length,
                        (i) => NavigationRailDestination(
                          icon: special
                              ? _specialTabIcon(i, false)
                              : Icon(sharedIcons[i]),
                          selectedIcon: special
                              ? _specialTabIcon(i, true)
                              : Icon(sharedIcons[i]),
                          label: Text(labels[i]),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: tab,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      SpecialSectionScope(
                        key: pages[i].key,
                        title: labels[i],
                        child: pages[i],
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
              icons: special ? icons.sublist(0, 5) : sharedIcons,
              iconBuilder: special ? _specialTabIcon : null,
              selectedIndex: tab,
              onSelected: select,
              glass: s.glass,
            ),
    );
  }
}

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../brand_reveal.dart';
import '../l10n.dart';
import '../ui.dart';

class StartupPage extends StatefulWidget {
  final VoidCallback? onRevealComplete;
  final bool animate;
  final Future<void>? startAfter;
  const StartupPage({
    super.key,
    this.onRevealComplete,
    this.animate = true,
    this.startAfter,
  });
  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _haptics = MethodChannel('linesight/brand-haptics');
  late final AnimationController _timeline = AnimationController(
    vsync: this,
    duration: brandRevealDuration,
    animationBehavior: AnimationBehavior.preserve,
  )..addStatusListener(_status);
  ui.Image? _logo;
  bool _started = false, _completed = false, _hapticsStarted = false;
  bool _reduced = false, _paused = false;
  bool _surfaceReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadLogo());
  }

  Future<void> _loadLogo() async {
    final bytes = await rootBundle.load('assets/brand/reveal_logo.png');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() => _logo = frame.image);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _reduced = s.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (_reduced || !widget.animate) {
      _cancelHaptics();
      _timeline.value = 1;
      _finish();
    } else if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_beginReveal());
      });
    }
    // Never vibrate before knowing the saved preference. Skip elapsed cues.
    if (s.ready && !s.haptics) _cancelHaptics();
    if (_started && s.ready && !_hapticsStarted && !_paused) _playHaptics();
  }

  Future<void> _beginReveal() async {
    // A post-frame callback only means layout/paint were submitted. Cold GPU
    // setup can still be pending; never consume the reveal behind the OS splash.
    await widget.startAfter;
    // Android can rasterize an engine frame before its Activity surface shows it.
    // Wait for FlutterActivity's actual first-display callback as well.
    await _invoke('awaitVisible');
    if (!mounted || _completed) return;
    _surfaceReady = true;
    if (!_paused) {
      _timeline.forward();
      _playHaptics();
    }
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      final reply = _haptics.invokeMethod<void>(method, arguments);
      if (method == 'awaitVisible') {
        // The first Flutter frame has already rasterized. A missing Android
        // visibility acknowledgement must not leave that frame on screen forever.
        await reply.timeout(const Duration(seconds: 2));
      } else {
        await reply;
      }
    } on TimeoutException {
      /* Continue after a lost native visibility acknowledgement. */
    } on MissingPluginException {
      /* Other platforms have a silent reveal. */
    } on PlatformException {
      /* Unsupported hardware must not delay startup. */
    }
  }

  void _playHaptics() {
    final s = AppScope.of(context);
    if (_reduced ||
        _paused ||
        _completed ||
        !s.ready ||
        !s.haptics ||
        _hapticsStarted ||
        !_timeline.isAnimating) {
      return;
    }
    _hapticsStarted = true;
    unawaited(_invoke('play', {'elapsedMs': (_timeline.value * 2800).round()}));
  }

  void _cancelHaptics() {
    unawaited(_invoke('cancel'));
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish() {
    if (_completed) return;
    _completed = true;
    _cancelHaptics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRevealComplete?.call();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _paused = true;
      _timeline.stop();
      _cancelHaptics();
      _hapticsStarted = false;
    } else {
      _paused = false;
      if (!_completed && !_reduced && _surfaceReady) {
        _timeline.forward();
        _playHaptics();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelHaptics();
    _timeline.dispose();
    _logo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: brandBlue,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: brandBlue,
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                key: const ValueKey('brand-reveal-canvas'),
                painter: BrandRevealPainter(
                  timeline: _timeline,
                  logo: _logo,
                  reduced: _reduced,
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 78 + MediaQuery.viewPaddingOf(context).bottom,
              child: AnimatedBuilder(
                animation: _timeline,
                builder: (context, _) {
                  final t = _reduced
                      ? 1.0
                      : ((_timeline.value * 2800 - 2440) / 220).clamp(0.0, 1.0);
                  final eased = Curves.easeOut.transform(t);
                  return Opacity(
                    opacity: eased,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - eased)),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          children: [
                            Text(
                              'LineSight',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 4,
                              ),
                            ),
                            SizedBox(height: 7),
                            Text(
                              'PRECISION LOCKED IN FOCUS',
                              style: TextStyle(
                                color: Color(0xCCEEF5FF),
                                fontSize: 9,
                                letterSpacing: 2.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Announce progress throughout; show it only if real work exceeds 2.8 s.
            AnimatedBuilder(
              animation: _timeline,
              builder: (context, _) {
                final waiting = _timeline.isCompleted && !s.ready;
                final label = trMessage(context, s.startupStage);
                return Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
                  child: Semantics(
                    liveRegion: true,
                    label: label,
                    child: ExcludeSemantics(
                      child: waiting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: _reduced
                                      ? const Icon(
                                          Icons.hourglass_top_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        )
                                      : const CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: Colors.white,
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    label,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

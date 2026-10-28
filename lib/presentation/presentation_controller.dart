import 'dart:async';
import 'package:flutter/foundation.dart';
import 'presentation_config.dart';

enum AuroraTrigger { volumeDoublePress, appInterface }

/// Visual presentation API only. No AI request, microphone, or account action.
class PresentationController extends ChangeNotifier {
  final int Function()? elapsedMilliseconds;
  PresentationController({this.elapsedMilliseconds});
  int get _nowMs => elapsedMilliseconds?.call() ?? _clock.elapsedMilliseconds;
  PresentationConfig config = const PresentationConfig();
  bool auroraVisible = false, adVisible = false;
  bool _ready = false, _foreground = true, _special = false;
  bool _initialized = false, _signedIn = false, _pendingAd = false;
  int _loginRevision = 0;
  Timer? _adTimer;
  final _clock = Stopwatch();
  int _adStartedMs = 0, _adDurationMs = 5000, _lastAdRemaining = 0;
  int get adRemaining => !adVisible
      ? 0
      : ((_adDurationMs - (_nowMs - _adStartedMs)) / 1000).ceil().clamp(0, 5);
  bool get canTriggerAurora =>
      _ready && _foreground && config.auroraEnabled && !adVisible;
  AuroraTrigger? lastTrigger;

  void update({
    required PresentationConfig settings,
    required bool ready,
    required bool special,
    required bool signedIn,
    int? interactiveLoginRevision,
  }) {
    final login =
        _initialized &&
        signedIn &&
        (interactiveLoginRevision == null
            ? !_signedIn
            : interactiveLoginRevision != _loginRevision);
    _initialized = true;
    _signedIn = signedIn;
    _loginRevision = interactiveLoginRevision ?? 0;
    _special = special;
    _ready = ready;
    config = settings;
    if (login && special && settings.loginAdEnabled) _pendingAd = true;
    if (!signedIn || !special || !settings.loginAdEnabled) {
      _pendingAd = false;
      _closeAd();
    }
    if (!ready || !settings.auroraEnabled || !_foreground) {
      auroraVisible = false;
    }
    if (_pendingAd && ready && _foreground) {
      _pendingAd = false;
      _startAd();
    }
    notifyListeners();
  }

  bool showAurora({AuroraTrigger trigger = AuroraTrigger.appInterface}) {
    if (!canTriggerAurora) return false;
    lastTrigger = trigger;
    auroraVisible = true;
    notifyListeners();
    return true;
  }

  void dismissAurora() {
    if (!auroraVisible) return;
    auroraVisible = false;
    notifyListeners();
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value) auroraVisible = false;
    if (value && _pendingAd && _ready && _special && _signedIn) {
      _pendingAd = false;
      _startAd();
    }
    _tickAd();
    notifyListeners();
  }

  void _startAd() {
    _closeAd();
    auroraVisible = false;
    adVisible = true;
    if (!_clock.isRunning) _clock.start();
    _adStartedMs = _nowMs;
    _adDurationMs = config.adSeconds * 1000;
    _lastAdRemaining = config.adSeconds;
    _adTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _tickAd(),
    );
  }

  void _tickAd() {
    if (!adVisible) return;
    // Stopwatch also expires across app backgrounding; never replay on resume.
    final remaining = adRemaining;
    if (remaining == _lastAdRemaining) return;
    _lastAdRemaining = remaining;
    if (remaining <= 0) {
      _closeAd();
    }
    notifyListeners();
  }

  void skipAd() {
    if (!adVisible) return;
    _closeAd();
    notifyListeners();
  }

  void _closeAd() {
    _adTimer?.cancel();
    _adTimer = null;
    adVisible = false;
  }

  @override
  void dispose() {
    _adTimer?.cancel();
    _clock.stop();
    super.dispose();
  }
}

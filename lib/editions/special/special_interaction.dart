import 'dart:async';
import 'package:flutter/material.dart';

/// Presentation-only feedback. Never controls network work or business results.
class SpecialInteractionController extends ChangeNotifier {
  static const duration = Duration(milliseconds: 620);
  bool enabled = false;
  bool _disposed = false;
  int percent = 0;
  DateTime? _suppressedUntil;
  void suppressFor(Duration duration) {
    _suppressedUntil = DateTime.now().add(duration);
    _cancel();
    if (percent != 0) {
      percent = 0;
      notifyListeners();
    }
  }

  final _timers = <Timer>[];
  void configure(bool value) {
    enabled = value;
    if (!value) {
      _cancel();
      percent = 0;
    }
  }

  void start() {
    if (_disposed ||
        !enabled ||
        percent != 0 ||
        (_suppressedUntil != null &&
            DateTime.now().isBefore(_suppressedUntil!))) {
      return;
    }
    _cancel();
    percent = 1;
    notifyListeners();
    for (final step in [(180, 3), (430, 15), (540, 99), (580, 100), (620, 0)]) {
      _timers.add(
        Timer(Duration(milliseconds: step.$1), () {
          if (!enabled) return;
          percent = step.$2;
          notifyListeners();
        }),
      );
    }
  }

  void _cancel() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    super.dispose();
  }
}

class SpecialNavigationObserver extends NavigatorObserver {
  final SpecialInteractionController controller;
  SpecialNavigationObserver(this.controller);
  void _show() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (navigator != null) controller.start();
  });
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _show();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _show();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _show();
}

class SpecialInteractionLayer extends StatefulWidget {
  final SpecialInteractionController controller;
  final Widget child;
  const SpecialInteractionLayer({
    super.key,
    required this.controller,
    required this.child,
  });
  @override
  State<SpecialInteractionLayer> createState() =>
      _SpecialInteractionLayerState();
}

class _SpecialInteractionLayerState extends State<SpecialInteractionLayer> {
  final _down = <int, Offset>{};
  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (event) => _down[event.pointer] = event.position,
    onPointerCancel: (event) => _down.remove(event.pointer),
    onPointerUp: (event) {
      final start = _down.remove(event.pointer);
      if (start != null && (start - event.position).distance < 10) {
        widget.controller.start();
      }
    },
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Stack(
        children: [
          widget.child,
          if (widget.controller.enabled && widget.controller.percent != 0)
            Positioned.fill(
              child: BlockSemantics(
                child: Stack(
                  key: const ValueKey('special-loading-overlay'),
                  children: [
                    const ModalBarrier(
                      dismissible: false,
                      color: Color(0xF5F4F8FF),
                    ),
                    Center(
                      child: Material(
                        color: Colors.transparent,
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 94,
                                height: 94,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox.expand(
                                      child: CircularProgressIndicator(
                                        value: widget.controller.percent / 100,
                                        strokeWidth: 5,
                                        backgroundColor: const Color(
                                          0xFFE0EAFF,
                                        ),
                                        color: const Color(0xFF497BFF),
                                      ),
                                    ),
                                    Text(
                                      '${widget.controller.percent}%',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF3478F6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                '精彩马上呈现',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF5B6E93),
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
        ],
      ),
    ),
  );
}

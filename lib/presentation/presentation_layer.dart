import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'aurora_glow.dart';
import 'presentation_controller.dart';

class PresentationScope extends InheritedNotifier<PresentationController> {
  const PresentationScope({
    super.key,
    required PresentationController controller,
    required super.child,
  }) : super(notifier: controller);
  static PresentationController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PresentationScope>()!
      .notifier!;
}

class PresentationLayer extends StatefulWidget {
  final PresentationController controller;
  final VoidCallback onPassThroughInteraction;
  final Widget child;
  final bool reduceMotion;
  const PresentationLayer({
    super.key,
    required this.controller,
    required this.child,
    required this.onPassThroughInteraction,
    this.reduceMotion = false,
  });
  @override
  State<PresentationLayer> createState() => _PresentationLayerState();
}

class _PresentationLayerState extends State<PresentationLayer> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  bool _key(KeyEvent event) {
    // Android volume events have already been classified by MainActivity.
    if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown ||
        event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
      return false;
    }
    if (event is KeyDownEvent && widget.controller.auroraVisible) _dismiss();
    return false;
  }

  void _dismiss() {
    if (!widget.controller.auroraVisible) return;
    widget.onPassThroughInteraction();
    widget.controller.dismissAurora();
  }

  @override
  Widget build(BuildContext context) => PresentationScope(
    controller: widget.controller,
    child: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Listener(
        behavior: HitTestBehavior.translucent,
        // Listener never wins the gesture arena. The same gesture reaches the page.
        onPointerDown: (_) => _dismiss(),
        onPointerSignal: (_) => _dismiss(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (widget.controller.auroraVisible)
              Positioned.fill(
                child: AuroraGlow(
                  config: widget.controller.config,
                  reduceMotion: widget.reduceMotion,
                ),
              ),
            if (widget.controller.adVisible)
              Positioned.fill(
                child: BlockSemantics(
                  child: _LoginAdvertisement(controller: widget.controller),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }
}

class _LoginAdvertisement extends StatelessWidget {
  final PresentationController controller;
  const _LoginAdvertisement({required this.controller});
  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('special-login-ad'),
    color: const Color(0xFFE1EFFF),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/checkcheck/backgrounds/ad_ai_assistant.png',
          fit: BoxFit.contain,
          semanticLabel: 'AI 质检助手',
          gaplessPlayback: true,
        ),
        Positioned(
          top: 12 + MediaQuery.paddingOf(context).top,
          right: 14,
          child: Opacity(
            opacity: 0.45,
            child: Semantics(
              button: true,
              label: '跳过广告，剩余 ${controller.adRemaining} 秒',
              child: Material(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('skip-login-ad'),
                  onTap: controller.skipAd,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 98,
                      minHeight: 48,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '跳过 ${controller.adRemaining}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

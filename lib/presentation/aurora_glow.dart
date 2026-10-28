import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'presentation_config.dart';

/// Android/Flutter adapter for Aurora's MIT-licensed Metal glow algorithm.
/// Source revision and original implementation are retained in third_party/aurora.
class AuroraGlow extends StatefulWidget {
  final PresentationConfig config;
  final bool reduceMotion;
  const AuroraGlow({
    super.key,
    required this.config,
    this.reduceMotion = false,
  });
  @override
  State<AuroraGlow> createState() => _AuroraGlowState();
}

class _AuroraGlowState extends State<AuroraGlow>
    with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _program;
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );
  ui.FragmentShader? _shader;
  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _animation.repeat();
    (_program ??= ui.FragmentProgram.fromAsset('shaders/aurora_glow.frag'))
        .then((program) {
          if (mounted) setState(() => _shader = program.fragmentShader());
        })
        .catchError((Object _) {
          /* Canvas glow remains available on older GPUs. */
        });
  }

  @override
  void didUpdateWidget(AuroraGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      if (widget.reduceMotion) {
        _animation.stop();
      } else {
        _animation.repeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('aurora-glow'),
          painter: _GlowPainter(
            shader: _shader,
            config: widget.config,
            animation: _animation,
            reduceMotion: widget.reduceMotion,
          ),
          size: Size.infinite,
        ),
      ),
    ),
  );
  @override
  void dispose() {
    _animation.dispose();
    _shader?.dispose();
    super.dispose();
  }
}

class _GlowPainter extends CustomPainter {
  final ui.FragmentShader? shader;
  final PresentationConfig config;
  final AnimationController animation;
  final bool reduceMotion;
  _GlowPainter({
    required this.shader,
    required this.config,
    required this.animation,
    required this.reduceMotion,
  }) : super(repaint: animation);
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final time = reduceMotion
        ? 4.0
        : (animation.lastElapsedDuration?.inMicroseconds ?? 0) / 1000000;
    if (shader != null) {
      final values = [
        size.width,
        size.height,
        time,
        config.speed,
        config.borderWidth,
        config.glowSize,
        config.intensity,
        ['intelligence', 'ocean', 'sunset'].indexOf(config.palette).toDouble(),
        ['subtle', 'standard', 'dramatic'].indexOf(config.style).toDouble(),
      ];
      for (var i = 0; i < values.length; i++) {
        shader!.setFloat(i, values[i]);
      }
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }
    // Fallback keeps the same transparent-centre, hit-test-free contract.
    final rect = (Offset.zero & size).deflate(2);
    final palette = config.palette == 'ocean'
        ? const [
            Color(0xFF33CCE6),
            Color(0xFF2680D9),
            Color(0xFF4DE6D9),
            Color(0xFF33CCE6),
          ]
        : config.palette == 'sunset'
        ? const [
            Color(0xFFFF7326),
            Color(0xFFD9338C),
            Color(0xFFFFB34D),
            Color(0xFFFF7326),
          ]
        : const [
            Color(0xFF0096FF),
            Color(0xFFFB64FF),
            Color(0xFFFF2555),
            Color(0xFFFF9300),
            Color(0xFF0096FF),
          ];
    final gradient = SweepGradient(
      colors: palette,
      transform: GradientRotation(time * config.speed * math.pi),
    );
    for (final width in [
      config.glowSize,
      config.borderWidth * 3,
      config.borderWidth,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(28)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = gradient.createShader(rect)
          ..color = Colors.white.withValues(alpha: config.intensity)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            width > config.borderWidth ? width / 2 : 0.5,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      shader != old.shader ||
      config != old.config ||
      reduceMotion != old.reduceMotion;
}

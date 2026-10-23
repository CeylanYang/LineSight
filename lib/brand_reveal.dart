import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'brand_particles.dart';

const brandRevealDuration = Duration(milliseconds: 2800);
const brandBlue = Color(0xFF3478F6);

double _clamp(double t) => t.clamp(0.0, 1.0);
double _smooth(double t) {
  t = _clamp(t);
  return t * t * (3 - 2 * t);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _out(double t) => 1 - math.pow(1 - _clamp(t), 3).toDouble();
double _quint(double t) {
  t = _clamp(t);
  return t < .5 ? 16 * t * t * t * t * t : 1 - math.pow(-2 * t + 2, 5) / 2;
}

double _progress(double ms, String group) => group.startsWith('corner')
    ? _out((ms - 170) / 760)
    : group == 'ring'
    ? _quint((ms - 1040) / 990)
    : _out((ms - 1140) / 890);

// Absolute cue positions also used by the Android envelope, in milliseconds.
const brandCues = <(double, double, double)>[
  (70, 12, 42),
  (470, 16, 55),
  (840, 18, 70),
  (1180, 20, 92),
  (1460, 22, 119),
  (1740, 25, 150),
  (2010, 28, 178),
  (2410, 16, 255),
];

double _pulse(double ms) {
  var result = 0.0;
  for (final (time, duration, amplitude) in brandCues) {
    final d = (ms - time - duration / 2) / math.max(28, duration * 1.1);
    result += math.exp(-d * d) * amplitude / 255;
  }
  return math.min(1, result);
}

/// Native Canvas port of V4.2. The two diagonal reflection stripes are omitted.
/// Immutable imported coordinates avoid decoding, sorting or randomness per frame.
class BrandRevealPainter extends CustomPainter {
  final Animation<double> timeline;
  final ui.Image? logo;
  final bool reduced;
  BrandRevealPainter({required this.timeline, this.logo, this.reduced = false})
    : super(repaint: timeline);

  @override
  void paint(Canvas canvas, Size size) {
    final ms = reduced ? 2800.0 : timeline.value * 2800;
    final cx = size.width / 2, cy = size.height * .45;
    final scale = math.min(
      math.min(size.width * .41 / 468, 188 / 468),
      size.height * .32 / 394,
    );
    final center = Offset(cx, cy);
    final pulse = reduced ? 0.0 : _pulse(ms);
    final paint = Paint();
    canvas.drawColor(brandBlue, BlendMode.src);
    final radius = math.min(size.width, size.height) * .6;
    paint.shader = ui.Gradient.radial(center, radius, [
      Colors.white.withValues(alpha: .03 + .06 * pulse),
      Colors.white.withValues(alpha: 0),
    ]);
    canvas.drawRect(Offset.zero & size, paint);
    paint.shader = null;
    if (!reduced) {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 1;
      for (var i = 0; i < 18; i++) {
        paint.color = Colors.white.withValues(
          alpha: (1 - i / 18) * (.012 + .03 * math.max(0, pulse - .2)),
        );
        canvas.drawCircle(
          center,
          50 + i * 14 + _smooth((ms - 1650) / 900) * 16,
          paint,
        );
      }
      paint.style = PaintingStyle.fill;
    }
    // Settled blueprint points behind the moving particles.
    for (final p in brandParticles) {
      var gp = _progress(ms, p.$1);
      if (ms > 2360) gp = math.min(1, gp + .35 * _smooth((ms - 2360) / 160));
      if (gp < .03) continue;
      paint.color = Colors.white.withValues(
        alpha: (p.$1.startsWith('corner') ? .08 : .09) * .35 * gp,
      );
      canvas.drawRect(
        Rect.fromLTWH(cx + p.$2 * scale, cy + p.$3 * scale, 1.15, 1.15),
        paint,
      );
    }
    void drawLogo(double alpha) {
      if (logo == null || alpha <= .001) return;
      paint.color = Colors.white.withValues(alpha: _clamp(alpha));
      paint.filterQuality = FilterQuality.medium;
      canvas.drawImageRect(
        logo!,
        Rect.fromLTWH(0, 0, logo!.width.toDouble(), logo!.height.toDouble()),
        Rect.fromCenter(
          center: center,
          width: 468 * scale,
          height: 394 * scale,
        ),
        paint,
      );
    }

    final lock = _smooth((ms - 2360) / 150);
    drawLogo(.10 * lock);
    // Horizontal scan is part of the logo construction, independent of glints.
    final scan = _smooth((ms - 1220) / 880);
    if (scan >= .01) {
      final beam = 3 + 5 * pulse, half = 468 * scale * .52 * scan;
      paint.shader = ui.Gradient.linear(
        Offset(cx - half - 30, 0),
        Offset(cx + half + 30, 0),
        [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: .85 * (.11 + .18 * pulse)),
          Colors.white.withValues(alpha: 0),
        ],
        [0, .5, 1],
      );
      canvas.drawRect(
        Rect.fromLTWH(
          cx - half - 40,
          cy - beam / 2 - 7,
          half * 2 + 80,
          beam + 14,
        ),
        paint,
      );
      paint.shader = null;
      paint.color = Colors.white.withValues(alpha: .95 * .88);
      canvas.drawRect(
        Rect.fromLTWH(cx - half, cy - beam / 2, half * 2, beam),
        paint,
      );
    }
    for (final p in brandParticles) {
      final group = p.$1, seed = p.$10, delay = p.$8;
      final gp = _progress(ms, group);
      final appearBase = group.startsWith('corner')
          ? 65
          : group == 'ring'
          ? 110
          : 140;
      final appear = _smooth((ms - appearBase - delay * 170) / 210);
      if (appear <= .001) continue;
      final solidify = _smooth((ms - 2360) / 180);
      var x = 0.0, y = 0.0, alpha = .92, r = p.$9;
      if (group.startsWith('corner')) {
        final t = _smooth(_clamp(gp - delay * .12));
        final bow = (1 - t) * (18 + 6 * math.sin(seed * 4 + ms * .01));
        x = _lerp(p.$4, p.$2, t) + math.sin(seed + ms * .006) * bow;
        y = _lerp(p.$5, p.$3, t) + math.cos(seed * 1.3 + ms * .006) * bow;
        alpha = .22 + .74 * t;
        r *= .9 + .25 * t;
      } else if (group == 'ring') {
        final t = _smooth(_clamp(gp - delay * .07));
        final a =
            _lerp(p.$6 + math.sin(seed * 7) * 1.3, p.$6, t) +
            math.sin(ms * .01 + seed) * .05 * (1 - t);
        final radius = _lerp(p.$7 + 95 + 30 * math.sin(seed * 3), p.$7, t);
        x = math.cos(a) * radius;
        y = math.sin(a) * radius;
        alpha = .15 + .82 * t;
        r *= .8 + .33 * t;
      } else {
        final t = _smooth(_clamp(gp - delay * .08));
        final side = p.$2 == 0 ? 1 : p.$2.sign;
        x = _lerp(side * (8 + math.sin(seed * 5) * 8), p.$2 * t * t, t);
        y =
            _lerp(math.cos(seed * 6) * 10, p.$3, t) +
            math.sin(ms * .013 + seed) * 5 * (1 - t);
        alpha = .18 + .88 * t;
        r *= .85 + .25 * t;
      }
      final position = Offset(cx + x * scale, cy + y * scale);
      alpha *=
          appear *
          (reduced ? .82 : 1) *
          (1 + .18 * math.sin(ms * .014 + seed * 11)) *
          (1 - .92 * solidify);
      r *= 1 - .22 * solidify;
      if (alpha < .01) continue;
      paint.color = (p.$11 ? const Color(0xFFD7EDFF) : Colors.white).withValues(
        alpha: _clamp(alpha),
      );
      canvas.drawCircle(position, r, paint);
      if (!reduced && gp < .98 && solidify < .9) {
        final target = Offset(cx + p.$2 * scale, cy + p.$3 * scale);
        final distance = (target - position).distance;
        if (distance < 25) {
          paint.color = Colors.white.withValues(
            alpha: (1 - distance / 25) * .18 * appear * (1 - solidify),
          );
          paint.strokeWidth = 1;
          canvas.drawLine(position, target, paint);
        }
      }
      if (lock > .02 && gp > .92) {
        paint.color = Colors.white.withValues(
          alpha: .12 * lock * (1 - solidify * .35),
        );
        canvas.drawCircle(position, r * 2.4, paint);
      }
    }
    final halo = _smooth((ms - 2360) / 110);
    if (halo > .01) {
      paint.shader = ui.Gradient.radial(center, 140, [
        Colors.white.withValues(alpha: .28 * .42 * halo),
        Colors.white.withValues(alpha: 0),
      ]);
      canvas.drawRect(
        Rect.fromCenter(center: center, width: 280, height: 280),
        paint,
      );
      paint.shader = null;
    }
    drawLogo(
      math.min(
        1,
        .18 * _smooth((ms - 2320) / 140) + .92 * _smooth((ms - 2430) / 160),
      ),
    );
  }

  @override
  bool shouldRepaint(BrandRevealPainter old) =>
      old.logo != logo || old.timeline != timeline || old.reduced != reduced;
}

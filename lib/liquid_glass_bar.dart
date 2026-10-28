import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Flutter implementation of the floating interaction design in LiquidGlassBar.
/// No Compose/GPL implementation code is included; see docs/LIQUID_GLASS_BAR.md.
class LiquidGlassBar extends StatefulWidget {
  const LiquidGlassBar({
    super.key,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onSelected,
    required this.glass,
    this.iconBuilder,
  });

  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool glass;
  final Widget Function(int index, bool selected)? iconBuilder;

  @override
  State<LiquidGlassBar> createState() => _LiquidGlassBarState();
}

class _LiquidGlassBarState extends State<LiquidGlassBar>
    with TickerProviderStateMixin {
  late final _position = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );
  late final _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 260),
  );
  int? _pointer;
  bool _handlingPointer = false;
  double _distance = 0;
  double _startPosition = 0;
  late VelocityTracker _velocity;
  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void didUpdateWidget(LiquidGlassBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && _pointer == null) {
      _settle(widget.selectedIndex);
    }
  }

  void _settle(int target) {
    if (_reduced) {
      _position.value = target.toDouble();
      return;
    }
    _position.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 36),
        _position.value,
        target.toDouble(),
        0,
        tolerance: const Tolerance(distance: .001, velocity: .001),
      ),
    );
  }

  void _finish(int target) {
    _pointer = null;
    _press.reverse();
    _settle(target);
    if (target != widget.selectedIndex) widget.onSelected(target);
  }

  void _endPointer(int target) {
    _finish(target);
    // TextButton remains keyboard/semantics accessible; pointer selection is
    // owned here so its tap recognizer cannot override a short drag on release.
    Future.microtask(() => _handlingPointer = false);
  }

  @override
  void dispose() {
    _position.dispose();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final height = math.max(64.0, 44 + 16 * textScale);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cell = (width - 8) / widget.labels.length;
              double tabAt(double x) {
                final value = ((x - 4) / cell - .5);
                return rtl ? widget.labels.length - 1 - value : value;
              }

              int bounded(double value) =>
                  value.round().clamp(0, widget.labels.length - 1);
              final items = Row(
                children: List.generate(widget.labels.length, (i) {
                  final selected = widget.selectedIndex == i;
                  return Expanded(
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: widget.labels[i],
                      child: Tooltip(
                        message: widget.labels[i],
                        child: TextButton(
                          key: ValueKey('liquid-tab-$i'),
                          onPressed: () {
                            if (!_handlingPointer) _finish(i);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            minimumSize: Size(48, height - 8),
                            foregroundColor: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            shape: const StadiumBorder(),
                          ),
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                widget.iconBuilder?.call(i, selected) ??
                                    Icon(widget.icons[i], size: 24),
                                const SizedBox(height: 3),
                                Text(
                                  widget.labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );

              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (_pointer != null) return;
                  _pointer = event.pointer;
                  _handlingPointer = true;
                  _position.stop();
                  _distance = 0;
                  _startPosition = _position.value;
                  _velocity = VelocityTracker.withKind(event.kind)
                    ..addPosition(event.timeStamp, event.position);
                  if (!_reduced) _press.forward();
                },
                onPointerMove: (event) {
                  if (_pointer != event.pointer) return;
                  _velocity.addPosition(event.timeStamp, event.position);
                  _distance += event.delta.dx;
                  if (_distance.abs() > 8) {
                    _position.value =
                        (_startPosition + _distance / cell * (rtl ? -1 : 1))
                            .clamp(-.35, widget.labels.length - .65);
                  }
                },
                onPointerUp: (event) {
                  if (_pointer != event.pointer) return;
                  if (_distance.abs() <= 8) {
                    _endPointer(bounded(tabAt(event.localPosition.dx)));
                  } else {
                    final speed =
                        _velocity.getVelocity().pixelsPerSecond.dx /
                        cell *
                        (rtl ? -1 : 1);
                    _endPointer(bounded(_position.value + speed * .22));
                  }
                },
                onPointerCancel: (event) {
                  if (_pointer == event.pointer) {
                    _endPointer(widget.selectedIndex);
                  }
                },
                child: AnimatedBuilder(
                  animation: Listenable.merge([_position, _press]),
                  child: items,
                  builder: (context, items) {
                    final press = Curves.easeOutCubic.transform(_press.value);
                    final value = _position.value.clamp(
                      0.0,
                      widget.labels.length - 1.0,
                    );
                    final visual = rtl
                        ? widget.labels.length - 1 - value
                        : value;
                    final over = _position.value - value;
                    final surface = (dark
                        ? const Color(0xFF203049)
                        : Colors.white);
                    Widget glassSurface({
                      required double radius,
                      required Widget child,
                      bool capsule = false,
                    }) {
                      if (!widget.glass) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            color: capsule
                                ? scheme.primary.withValues(alpha: .13)
                                : surface,
                            borderRadius: BorderRadius.circular(radius),
                          ),
                          child: child,
                        );
                      }
                      return LiquidGlass.withOwnLayer(
                        fake: !ui.ImageFilter.isShaderFilterSupported,
                        shape: LiquidRoundedSuperellipse(borderRadius: radius),
                        settings: LiquidGlassSettings(
                          blur: capsule ? 0 : 4,
                          thickness: capsule ? 10 + 4 * press : 24,
                          glassColor: capsule
                              ? scheme.primary.withValues(
                                  alpha: .10 + press * .06,
                                )
                              : surface.withValues(alpha: .35),
                          saturation: 1.5,
                          chromaticAberration: capsule
                              ? .01 + press * .04
                              : .01,
                          lightIntensity: dark ? .5 : .7,
                          refractiveIndex: 1.15,
                        ),
                        child: child,
                      );
                    }

                    return Transform.translate(
                      offset: Offset((over * 12).clamp(-4.0, 4.0), 0),
                      child: SizedBox(
                        height: height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: dark ? .35 : .12,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: glassSurface(
                                  radius: 28,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: dark ? .18 : .65,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: items,
                              ),
                            ),
                            Positioned(
                              left: 4 + visual * cell,
                              top: 4,
                              width: cell,
                              height: height - 8,
                              child: IgnorePointer(
                                child: Transform.scale(
                                  scale: 1 + press * .39,
                                  child: glassSurface(
                                    radius: 28,
                                    capsule: true,
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

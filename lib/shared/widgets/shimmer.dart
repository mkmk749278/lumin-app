/// Shimmer — animated gradient sweep for skeleton placeholders.
///
/// Standard pattern from Binance / Robinhood / TradingView: while data
/// is loading, the static gray skeleton box gets a slow diagonal
/// gradient sweep that signals "loading in progress" without being
/// noisy.  Replaces the previous flat-gray skeleton (which users
/// perceived as "stuck") with a moving sheen.
///
/// Pure Flutter, no new dep.  Drives a single AnimationController per
/// instance; the child is composed inside a ShaderMask so the
/// gradient is clipped to whatever shape the child paints.  Cheap
/// enough to wrap every skeleton card without measurable cost (the
/// shader is recomputed once per frame at 60Hz, paint cost ~0.5ms
/// even on a 5-card Pulse skeleton).
import 'package:flutter/material.dart';

import '../tokens.dart';

class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1400),
  });

  final Widget child;

  /// Defaults to ``LuminColors.bgCard``-ish — matches the existing
  /// skeleton fill so the un-highlighted portions are identical to
  /// the pre-shimmer look.
  final Color? baseColor;

  /// The bright sweep colour — defaults to a slight lift on the base.
  final Color? highlightColor;

  /// One full left-to-right sweep.  1400ms reads as "alive but
  /// unhurried" — too fast (under 1s) looks frantic; too slow (over
  /// 2s) looks broken.
  final Duration duration;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? LuminColors.bgElevated;
    final highlight =
        widget.highlightColor ?? LuminColors.cardBorder.withOpacity(0.6);
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, child) {
        // ``-1.0`` starts the gradient off-screen left; ``+2.0`` lands
        // it off-screen right.  Net result: a smooth pass that doesn't
        // jump between cycles.
        final t = _ctl.value;
        final dx = -1.0 + 3.0 * t;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(dx - 0.3, -0.6),
              end: Alignment(dx + 0.3, 0.6),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

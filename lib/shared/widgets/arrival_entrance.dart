/// A one-time entrance for an item that arrived while the user was looking:
/// a short fade and rise, plus an accent edge that settles away.
///
/// Added 2026-09-23 for the Signals feed, where a new signal — the moment the
/// product exists for — used to appear in the list with no motion at all.
/// The caller decides WHICH items are arrivals (never the first load, or the
/// whole feed would animate on every open); this widget only plays once per
/// mount and reports [onDone] so the caller can stop marking the item.
library;

import 'package:flutter/material.dart';

import '../tokens.dart';

class ArrivalEntrance extends StatefulWidget {
  const ArrivalEntrance({super.key, required this.child, this.onDone});

  final Widget child;
  final VoidCallback? onDone;

  /// Total length of the entrance. Short enough that a list with several
  /// arrivals never feels busy.
  static const duration = Duration(milliseconds: 900);

  @override
  State<ArrivalEntrance> createState() => _ArrivalEntranceState();
}

class _ArrivalEntranceState extends State<ArrivalEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl =
      AnimationController(vsync: this, duration: ArrivalEntrance.duration)
        ..forward().whenComplete(() => widget.onDone?.call());

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Motion over the first ~40%, the accent edge fading over the rest.
    final enter = CurvedAnimation(
      parent: _ctl,
      curve: const Interval(0, 0.4, curve: Curves.easeOutCubic),
    );
    final glow = CurvedAnimation(
      parent: _ctl,
      curve: const Interval(0.3, 1, curve: Curves.easeIn),
    );
    return AnimatedBuilder(
      animation: _ctl,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: enter.value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - enter.value)),
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LuminRadii.lg),
                border: Border.all(
                  color: LuminColors.accent
                      .withValues(alpha: 0.7 * (1 - glow.value)),
                  width: 1.5,
                ),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Loading placeholder for a settings-style page: a title line and a few
/// cards, under the app's [Shimmer].
///
/// Added 2026-09-23. Eleven settings pages and sheets showed a lone
/// centred spinner while their data loaded — exactly the "looks stuck"
/// signal [Shimmer] was written to replace, and the Signals and Pulse tabs
/// had already moved off it. A skeleton also stops the page jumping when
/// the real layout arrives, because the space is already roughly spoken
/// for.
library;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'shimmer.dart';

class PageSkeleton extends StatelessWidget {
  const PageSkeleton({
    super.key,
    this.cards = 3,
    this.padding,
    this.inline = false,
  });

  /// True when the skeleton sits inside a list, sheet or column that already
  /// scrolls: it then lays out at its natural height instead of as its own
  /// scroll view (a ListView inside a ListView has no height to take).
  final bool inline;

  /// How many card-shaped blocks to draw under the title.
  final int cards;

  /// Defaults to the standard page gutter.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final body = Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(width: 180, height: 18),
                const SizedBox(height: LuminSpacing.sm),
                _bar(width: 260, height: 12),
                const SizedBox(height: LuminSpacing.xl),
                for (var i = 0; i < cards; i++) ...[
                  _card(),
                  const SizedBox(height: LuminSpacing.md),
                ],
              ],
            ),
          );
    final pad = padding ?? const EdgeInsets.all(LuminSpacing.lg);
    return Semantics(
      label: 'Loading',
      child: inline
          ? Padding(padding: pad, child: body)
          : ListView(
              physics: const NeverScrollableScrollPhysics(),
              padding: pad,
              children: [body],
            ),
    );
  }

  static Widget _bar({required double width, required double height}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: LuminColors.bgElevated,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  static Widget _card() => Container(
        height: 88,
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.lg),
          border: Border.all(color: LuminColors.cardBorder),
        ),
        padding: const EdgeInsets.all(LuminSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(width: 140, height: 14),
            const SizedBox(height: LuminSpacing.sm),
            _bar(width: double.infinity, height: 10),
            const SizedBox(height: 6),
            _bar(width: 200, height: 10),
          ],
        ),
      );
}

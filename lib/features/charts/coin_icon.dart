/// Coin avatar for the Markets list and the chart header.
///
/// A bundled CC0 icon when we have one ([kBundledCoinIcons]); otherwise a
/// monogram on a gradient derived from the ticker, so the same coin always
/// gets the same colours and no row ever shows a blank or broken image.
library;

import 'package:flutter/material.dart';

import 'coin_icon_set.dart';
import 'market_view.dart';

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, required this.symbol, this.size = 36});

  /// A pair (`BTCUSDT`, `1000PEPEUSDT`) or a bare base (`BTC`).
  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = baseAsset(symbol);
    final key = base.toLowerCase();
    if (kBundledCoinIcons.contains(key)) {
      return ClipOval(
        child: Image.asset(
          'assets/coins/$key.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _Monogram(base: base, size: size),
        ),
      );
    }
    return _Monogram(base: base, size: size);
  }
}

/// Two hues from the ticker's own letters — deterministic, so ETH's
/// neighbour on the list never swaps colour between frames or sessions.
List<Color> monogramColors(String base) {
  var h = 0;
  for (final c in base.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final hue = (h % 360).toDouble();
  return [
    HSLColor.fromAHSL(1, hue, 0.70, 0.55).toColor(),
    HSLColor.fromAHSL(1, (hue + 48) % 360, 0.75, 0.42).toColor(),
  ];
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.base, required this.size});
  final String base;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = monogramColors(base);
    final letters = base.isEmpty ? '?' : (base.length <= 3 ? base : base.substring(0, 2));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      padding: EdgeInsets.all(size * 0.2),
      child: FittedBox(
        // Letters fill the circle at any avatar size; the base size is the
        // readable one and the box scales it (type_floor_test).
        child: Text(
          letters,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: -0.3,
            height: 1,
          ),
        ),
      ),
    );
  }
}

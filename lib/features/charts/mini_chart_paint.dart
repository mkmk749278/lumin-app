/// Shared paint primitives for the native mini charts (alert thumbnails,
/// signal setup snaps).  Each mini chart keeps its own overlay semantics —
/// only the genuinely common pieces live here: the padded y-range and the
/// candle wick/body pass.
library;

import 'dart:ui';

import 'models/candle.dart';

/// Candle colours shared by every natively-painted mini chart.
const Color kMiniUp = Color(0xFF26A69A);
const Color kMiniDown = Color(0xFFEF5350);

/// Price range over [candles] plus any overlay [extras], padded by
/// [padFrac] breathing room on each side.  Returns `(min, max)` ready for
/// a y-axis mapping, or null when nothing finite is in range.
(double, double)? miniPriceRange(
  List<Candle> candles,
  Iterable<double?> extras, {
  double padFrac = 0.08,
}) {
  var minP = double.infinity;
  var maxP = -double.infinity;
  for (final c in candles) {
    if (c.low < minP) minP = c.low;
    if (c.high > maxP) maxP = c.high;
  }
  for (final v in extras) {
    if (v == null) continue;
    if (v < minP) minP = v;
    if (v > maxP) maxP = v;
  }
  if (!minP.isFinite || !maxP.isFinite) return null;
  final pad = (maxP - minP) == 0 ? maxP * 0.01 + 1e-9 : (maxP - minP) * padFrac;
  return (minP - pad, maxP + pad);
}

/// Wick + body pass over [candles] using the caller's coordinate mapping.
/// Bodies are clamped to stay ≥1 px tall so dojis remain visible.
void paintMiniCandles(
  Canvas canvas,
  List<Candle> candles,
  double Function(int) xAt,
  double Function(double) yAt,
  double xStep,
) {
  final bodyW = (xStep * 0.6).clamp(1.0, 6.0);
  for (var i = 0; i < candles.length; i++) {
    final c = candles[i];
    final x = xAt(i);
    final color = c.close >= c.open ? kMiniUp : kMiniDown;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, yAt(c.high)), Offset(x, yAt(c.low)), paint);
    final top = yAt(c.open >= c.close ? c.open : c.close);
    final bottom = yAt(c.open >= c.close ? c.close : c.open);
    canvas.drawRect(
      Rect.fromLTRB(
        x - bodyW / 2,
        top,
        x + bodyW / 2,
        bottom - top < 1 ? top + 1 : bottom, // dojis stay visible
      ),
      paint,
    );
  }
}

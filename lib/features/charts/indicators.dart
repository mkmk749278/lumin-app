/// Pure indicator math + price-format derivation for the Market Charts tab.
///
/// Computed Dart-side (not in the WebView JS) so the maths is unit-testable
/// with `flutter test` and the JS bridge stays a dumb renderer. All series
/// functions return lists aligned 1:1 with the input; positions inside the
/// warm-up window are `null` so the chart simply doesn't draw them.
library;

import 'dart:math' as math;

/// Simple moving average. `out[i]` is the SMA of `values[i-period+1 .. i]`;
/// null for the first `period-1` positions.
List<double?> sma(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0 || values.length < period) return out;
  double sum = 0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// Exponential moving average, seeded with the SMA of the first [period]
/// values (the standard charting convention, matching TradingView).
List<double?> ema(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0 || values.length < period) return out;
  double seed = 0;
  for (var i = 0; i < period; i++) {
    seed += values[i];
  }
  var e = seed / period;
  out[period - 1] = e;
  final k = 2 / (period + 1);
  for (var i = period; i < values.length; i++) {
    e = values[i] * k + e * (1 - k);
    out[i] = e;
  }
  return out;
}

/// Relative Strength Index with Wilder smoothing. First value lands at
/// index [period] (needs `period` deltas). 100 when there are no losses in
/// the window.
List<double?> rsi(List<double> values, {int period = 14}) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0 || values.length <= period) return out;
  double avgGain = 0;
  double avgLoss = 0;
  for (var i = 1; i <= period; i++) {
    final d = values[i] - values[i - 1];
    if (d >= 0) {
      avgGain += d;
    } else {
      avgLoss -= d;
    }
  }
  avgGain /= period;
  avgLoss /= period;
  double toRsi(double g, double l) => l == 0 ? 100 : 100 - 100 / (1 + g / l);
  out[period] = toRsi(avgGain, avgLoss);
  for (var i = period + 1; i < values.length; i++) {
    final d = values[i] - values[i - 1];
    avgGain = (avgGain * (period - 1) + (d > 0 ? d : 0)) / period;
    avgLoss = (avgLoss * (period - 1) + (d < 0 ? -d : 0)) / period;
    out[i] = toRsi(avgGain, avgLoss);
  }
  return out;
}

/// Decimal places the chart's price axis needs to resolve [price].
///
/// Lightweight Charts defaults to 2 decimals, which flattens every
/// sub-dollar perp (a 0.107-priced alt shows one axis step of 0.01 ≈ 9%).
/// Rule: enough decimals to show ~5 significant digits of the price's
/// magnitude, clamped to Binance's practical [2, 8] range.
int chartPrecisionFor(double price) {
  if (!price.isFinite || price <= 0) return 2;
  final magnitude = (-math.log(price) / math.ln10).ceil();
  return (magnitude + 4).clamp(2, 8);
}

/// The `minMove` matching [chartPrecisionFor]'s precision (10^-precision).
double minMoveForPrecision(int precision) => math.pow(10, -precision).toDouble();

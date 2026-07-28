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

/// Wilder's Parabolic SAR step / max acceleration factor.
///
/// These are not free chart settings — they are the engine's
/// `SAR_EXIT_SHADOW_STEP` / `SAR_EXIT_SHADOW_MAX_STEP` defaults
/// (`config/__init__.py` in `360-v2`). The chart draws the same indicator the
/// engine's SAR study measures, so a dot a user reads here is the same level
/// the study read. Changing either constant here without changing it there
/// silently makes the two describe different indicators.
const double kSarStep = 0.02;
const double kSarMaxStep = 0.2;

/// The timeframe the engine's SAR study runs on (`SAR_EXIT_SHADOW_BAR_MINUTES`).
/// The chart draws SAR on whatever timeframe is on screen — as an indicator
/// must — so the UI says so whenever the two differ.
const String kSarStudyTf = '15m';

/// Parabolic SAR (Wilder) — the stop-and-reverse level per bar.
///
/// **Port, not a re-derivation.** Line-for-line the engine's
/// `src/sar_exit_shadow.py::parabolic_sar`, including its seeding
/// (`out[0]` null, `out[1]` = the first SAR) and its two-bar min/max clamp on
/// the trailing level. Pinned against the engine's own output by a shared
/// vector in `test/features/charts/indicators_test.dart`, mirrored engine-side
/// in `tests/test_sar_chart_contract.py` — a drift in either implementation
/// fails CI on both sides rather than quietly putting a different indicator in
/// front of users than the one the study measured.
///
/// Returns a list aligned 1:1 with the input; `null` where no level exists
/// yet. [highs] and [lows] must be the same length — a mismatched pair is
/// refused (all-null) rather than clamped to the shorter one.
List<double?> parabolicSar(
  List<double> highs,
  List<double> lows, {
  double step = kSarStep,
  double maxStep = kSarMaxStep,
}) {
  final n = highs.length;
  final out = List<double?>.filled(n, null);
  if (n < 2 || lows.length != n) return out;
  var up = highs[1] >= highs[0];
  var af = step;
  var ep = up ? highs[1] : lows[1];
  var sar = up ? lows[0] : highs[0];
  out[1] = sar;
  for (var i = 2; i < n; i++) {
    sar = sar + af * (ep - sar);
    if (up) {
      sar = math.min(sar, math.min(lows[i - 1], lows[i - 2]));
      if (lows[i] < sar) {
        up = false;
        sar = ep;
        ep = lows[i];
        af = step;
      } else if (highs[i] > ep) {
        ep = highs[i];
        af = math.min(af + step, maxStep);
      }
    } else {
      sar = math.max(sar, math.max(highs[i - 1], highs[i - 2]));
      if (highs[i] > sar) {
        up = true;
        sar = ep;
        ep = highs[i];
        af = step;
      } else if (lows[i] < ep) {
        ep = lows[i];
        af = math.min(af + step, maxStep);
      }
    }
    out[i] = sar;
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

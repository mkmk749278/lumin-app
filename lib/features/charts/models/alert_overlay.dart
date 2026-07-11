/// Market-alert setup overlay for the chart — draws exactly what the
/// alert observed, on the alert's own timeframe, with zero manual effort:
///
/// * Near S/R          → solid level line titled "Support · 43×" + the
///                       alert-price reference line.
/// * RSI extreme       → alert-price line titled "RSI 19.0" (the RSI pane
///                       itself is auto-enabled by ChartPage).
/// * RSI divergence    → the divergence trend line connecting the two
///                       price pivots (engine ships pivot bars-ago +
///                       prices in `metrics`).
/// * Volume/volatility → alert-price line titled with the multiple.
///
/// Every type also gets a bar marker on the candle that fired the alert.
/// Serialises to the shape the WebView bridge's `setAlertOverlay` expects.
library;

import '../../../data/market_alert.dart';

/// Seconds per alert timeframe (matches the engine's TF_SECONDS).
const Map<String, int> kAlertTfSeconds = {
  '15m': 15 * 60,
  '1h': 3600,
  '4h': 4 * 3600,
};

class AlertChartOverlay {
  const AlertChartOverlay({
    required this.lines,
    required this.segments,
    required this.markers,
  });

  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>> segments;
  final List<Map<String, dynamic>> markers;

  static const _bullish = '#26a69a';
  static const _bearish = '#ef5350';
  static const _neutral = '#f6c85f';
  static const _reference = '#9aa7b4';

  static String _biasColor(String bias) {
    switch (bias) {
      case 'BULLISH':
        return _bullish;
      case 'BEARISH':
        return _bearish;
      default:
        return _neutral;
    }
  }

  static double? _metric(MarketAlert a, String key) {
    final v = a.metrics[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Open time (chart seconds) of the closed candle the alert was fired
  /// on: the last candle that CLOSED before the alert's creation instant.
  static int alertBarTime(MarketAlert a, {DateTime? now}) {
    final tfSec = kAlertTfSeconds[a.timeframe] ?? 3600;
    final created = a.createdAtUtc ?? (now ?? DateTime.now().toUtc());
    final createdSec = created.millisecondsSinceEpoch ~/ 1000;
    // floor(created / tf) * tf is the open of the candle containing the
    // alert instant; the candle that fired is the one before it.
    return (createdSec ~/ tfSec) * tfSec - tfSec;
  }

  factory AlertChartOverlay.fromAlert(MarketAlert a, {DateTime? now}) {
    final color = _biasColor(a.bias);
    final barTime = alertBarTime(a, now: now);
    final tfSec = kAlertTfSeconds[a.timeframe] ?? 3600;

    final lines = <Map<String, dynamic>>[];
    final segments = <Map<String, dynamic>>[];

    switch (a.alertType) {
      case 'NEAR_SUPPORT':
      case 'NEAR_RESISTANCE':
        final level = _metric(a, 'level_price');
        final touches = _metric(a, 'touches')?.toInt();
        final kind = a.alertType == 'NEAR_SUPPORT' ? 'Support' : 'Resistance';
        if (level != null) {
          lines.add({
            'price': level,
            'color': color,
            'title': touches != null ? '$kind · ${touches}×' : kind,
            'solid': true,
            'width': 2,
          });
        }
        lines.add({
          'price': a.price,
          'color': _reference,
          'title': 'Alert price',
        });
        break;

      case 'RSI_OVERBOUGHT':
      case 'RSI_OVERSOLD':
        final rsi = _metric(a, 'rsi');
        lines.add({
          'price': a.price,
          'color': color,
          'title': rsi != null ? 'RSI ${rsi.toStringAsFixed(1)}' : 'RSI extreme',
        });
        break;

      case 'RSI_BULLISH_DIVERGENCE':
      case 'RSI_BEARISH_DIVERGENCE':
        final aBars = _metric(a, 'pivot_a_bars_ago')?.toInt();
        final bBars = _metric(a, 'pivot_b_bars_ago')?.toInt();
        final aPrice = _metric(a, 'pivot_a_price');
        final bPrice = _metric(a, 'pivot_b_price');
        if (aBars != null && bBars != null && aPrice != null && bPrice != null) {
          segments.add({
            'color': color,
            'points': [
              {'time': barTime - aBars * tfSec, 'value': aPrice},
              {'time': barTime - bBars * tfSec, 'value': bPrice},
            ],
          });
        }
        lines.add({
          'price': a.price,
          'color': _reference,
          'title': 'Alert price',
        });
        break;

      default: // VOLUME_SPIKE / ABNORMAL_VOLATILITY / future types
        final mult =
            _metric(a, 'volume_mult') ?? _metric(a, 'tr_mult');
        lines.add({
          'price': a.price,
          'color': color,
          'title': mult != null ? '${mult.toStringAsFixed(1)}× normal' : 'Alert price',
        });
    }

    final markers = <Map<String, dynamic>>[
      {
        'time': barTime,
        'position': a.bias == 'BEARISH' ? 'above' : 'below',
        'color': color,
        'shape': a.bias == 'BEARISH'
            ? 'arrowDown'
            : (a.bias == 'BULLISH' ? 'arrowUp' : 'circle'),
        'text': a.title,
      },
    ];

    return AlertChartOverlay(lines: lines, segments: segments, markers: markers);
  }

  Map<String, dynamic> toJson() => {
        'lines': lines,
        'segments': segments,
        'markers': markers,
      };
}

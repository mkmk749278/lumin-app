/// Market-alert setup overlay for the chart — draws exactly what the
/// alert observed, on the alert's own timeframe, with zero manual effort
/// (the 100eyes chart look):
///
/// * Near S/R          → shaded zone rectangle over [zone_low, zone_high]
///                       from the first touch to the right edge, plus the
///                       solid level line titled "Support · 4×" and the
///                       alert-price reference line.
/// * RSI extreme       → alert-price line titled "RSI 19.0" (the RSI pane
///                       itself is auto-enabled by ChartPage).
/// * RSI divergence    → the divergence trend line connecting the two
///                       price pivots AND its mirror on the RSI band
///                       (engine ships pivot bars-ago + prices + RSI
///                       values in `metrics`).
/// * Volume/volatility → alert-price line titled with the multiple.
///
/// Every type also gets a bar marker on the candle that fired the alert,
/// and a `focus` visible range so the chart opens ON the setup instead of
/// fitting 500 bars.  Time-anchored geometry is only emitted when the
/// chart is on the alert's own timeframe (`chartTf`) — bar-offset math on
/// a different timeframe would draw the setup in the wrong place.
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
    this.rsiSegments = const [],
    this.zones = const [],
    this.focus,
  });

  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>> segments;
  final List<Map<String, dynamic>> markers;

  /// Divergence trend line mirrored on the RSI band ("rsi" price scale).
  final List<Map<String, dynamic>> rsiSegments;

  /// Shaded S/R zone rectangles `{from, low, high, color, borderColor, label}`.
  final List<Map<String, dynamic>> zones;

  /// Visible range `{from, to}` the chart zooms to after drawing.
  final Map<String, dynamic>? focus;

  static const _bullish = '#26a69a';
  static const _bearish = '#ef5350';
  static const _neutral = '#f6c85f';
  static const _reference = '#9aa7b4';

  /// Cap on how far left a zone may start — a level first touched 500
  /// bars ago would otherwise drag the focus window into a wall of
  /// history.
  static const _maxZoneBars = 180;

  /// Focus-window padding (bars) and the default window when the alert
  /// has no setup geometry to frame.
  static const _focusLeftPadBars = 8;
  static const _focusRightPadBars = 15;
  static const _defaultFocusBars = 60;

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

  static String _zoneFill(String bias) {
    switch (bias) {
      case 'BULLISH':
        return 'rgba(38,166,154,0.14)';
      case 'BEARISH':
        return 'rgba(239,83,80,0.14)';
      default:
        return 'rgba(246,200,95,0.14)';
    }
  }

  static String _zoneBorder(String bias) {
    switch (bias) {
      case 'BULLISH':
        return 'rgba(38,166,154,0.55)';
      case 'BEARISH':
        return 'rgba(239,83,80,0.55)';
      default:
        return 'rgba(246,200,95,0.55)';
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

  /// [chartTf] is the timeframe the chart is currently showing.  When it
  /// differs from the alert's own timeframe, only the horizontal price
  /// lines are emitted — segments/zones/markers/focus are bar-time math on
  /// the ALERT's timeframe and would land in the wrong place.
  factory AlertChartOverlay.fromAlert(
    MarketAlert a, {
    DateTime? now,
    String? chartTf,
  }) {
    final color = _biasColor(a.bias);
    final barTime = alertBarTime(a, now: now);
    final tfSec = kAlertTfSeconds[a.timeframe] ?? 3600;
    final timeAnchored = chartTf == null || chartTf == a.timeframe;

    final lines = <Map<String, dynamic>>[];
    final segments = <Map<String, dynamic>>[];
    final rsiSegments = <Map<String, dynamic>>[];
    final zones = <Map<String, dynamic>>[];
    int focusFromBars = _defaultFocusBars;

    switch (a.alertType) {
      case 'NEAR_SUPPORT':
      case 'NEAR_RESISTANCE':
        final level = _metric(a, 'level_price');
        final touches =
            (_metric(a, 'touch_count') ?? _metric(a, 'touches'))?.toInt();
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
        final zoneLow = _metric(a, 'zone_low');
        final zoneHigh = _metric(a, 'zone_high');
        final firstTouch = _metric(a, 'first_touch_bars_ago')?.toInt();
        if (timeAnchored &&
            zoneLow != null &&
            zoneHigh != null &&
            zoneHigh > zoneLow) {
          final zoneBars =
              (firstTouch ?? _defaultFocusBars).clamp(1, _maxZoneBars).toInt();
          zones.add({
            'from': barTime - zoneBars * tfSec,
            'low': zoneLow,
            'high': zoneHigh,
            'color': _zoneFill(a.bias),
            'borderColor': _zoneBorder(a.bias),
            'label': touches != null ? '$kind · ${touches}×' : kind,
          });
          focusFromBars = zoneBars;
        }
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
        if (timeAnchored &&
            aBars != null &&
            bBars != null &&
            aPrice != null &&
            bPrice != null) {
          segments.add({
            'color': color,
            'points': [
              {'time': barTime - aBars * tfSec, 'value': aPrice},
              {'time': barTime - bBars * tfSec, 'value': bPrice},
            ],
          });
          focusFromBars = aBars;
          // Mirror the trend line on the RSI band — the divergence IS the
          // disagreement between these two lines.
          final rsiFirst = _metric(a, 'rsi_first');
          final rsiSecond = _metric(a, 'rsi_second');
          if (rsiFirst != null && rsiSecond != null) {
            rsiSegments.add({
              'color': color,
              'points': [
                {'time': barTime - aBars * tfSec, 'value': rsiFirst},
                {'time': barTime - bBars * tfSec, 'value': rsiSecond},
              ],
            });
          }
        }
        lines.add({
          'price': a.price,
          'color': _reference,
          'title': 'Alert price',
        });
        break;

      default: // VOLUME_SPIKE / ABNORMAL_VOLATILITY / future types
        final mult = _metric(a, 'volume_mult') ?? _metric(a, 'tr_mult');
        lines.add({
          'price': a.price,
          'color': color,
          'title':
              mult != null ? '${mult.toStringAsFixed(1)}× normal' : 'Alert price',
        });
    }

    final markers = <Map<String, dynamic>>[
      if (timeAnchored)
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

    final focus = timeAnchored
        ? {
            'from': barTime - (focusFromBars + _focusLeftPadBars) * tfSec,
            'to': barTime + _focusRightPadBars * tfSec,
          }
        : null;

    return AlertChartOverlay(
      lines: lines,
      segments: segments,
      markers: markers,
      rsiSegments: rsiSegments,
      zones: zones,
      focus: focus,
    );
  }

  Map<String, dynamic> toJson() => {
        'lines': lines,
        'segments': segments,
        'markers': markers,
        'rsiSegments': rsiSegments,
        'zones': zones,
        if (focus != null) 'focus': focus,
      };
}

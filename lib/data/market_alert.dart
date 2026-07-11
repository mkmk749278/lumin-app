/// Market alert — one informational detector event from `/api/alerts`.
///
/// Mirrors the engine's `AlertItem` schema (`src/api/schemas.py`).
/// Alerts are 100eyes-class observations (RSI extremes, RSI divergence,
/// abnormal volatility, near horizontal S/R, volume anomaly), each
/// stamped with the detector's natural timeframe — NOT trade signals.
library;

class MarketAlert {
  const MarketAlert({
    required this.alertId,
    required this.alertType,
    required this.symbol,
    required this.timeframe,
    required this.price,
    required this.title,
    required this.message,
    required this.bias,
    this.metrics = const {},
    required this.createdAt,
  });

  final String alertId;

  /// Wire taxonomy: RSI_OVERBOUGHT / RSI_OVERSOLD / RSI_BULLISH_DIVERGENCE /
  /// RSI_BEARISH_DIVERGENCE / ABNORMAL_VOLATILITY / VOLUME_SPIKE /
  /// NEAR_SUPPORT / NEAR_RESISTANCE.  Unknown values render with the
  /// generic icon so an older app survives new engine detectors.
  final String alertType;
  final String symbol;

  /// Natural detector timeframe: 15m / 1h / 4h.
  final String timeframe;
  final double price;
  final String title;
  final String message;

  /// BULLISH / BEARISH / NEUTRAL — display lean only.
  final String bias;
  final Map<String, dynamic> metrics;

  /// ISO-8601 UTC.
  final String createdAt;

  DateTime? get createdAtUtc => DateTime.tryParse(createdAt)?.toUtc();

  /// Relative age label ("3m ago", "2h ago", "1d ago").
  String agoLabel({DateTime? now}) {
    final created = createdAtUtc;
    if (created == null) return '';
    final delta = (now?.toUtc() ?? DateTime.now().toUtc()).difference(created);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }

  factory MarketAlert.fromMap(Map<String, dynamic> m) => MarketAlert(
        alertId: m['alert_id'] as String? ?? '',
        alertType: m['alert_type'] as String? ?? '',
        symbol: m['symbol'] as String? ?? '',
        timeframe: m['timeframe'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0.0,
        title: m['title'] as String? ?? '',
        message: m['message'] as String? ?? '',
        bias: m['bias'] as String? ?? 'NEUTRAL',
        metrics: (m['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: m['created_at'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'alert_id': alertId,
        'alert_type': alertType,
        'symbol': symbol,
        'timeframe': timeframe,
        'price': price,
        'title': title,
        'message': message,
        'bias': bias,
        'metrics': metrics,
        'created_at': createdAt,
      };
}

/// Sample alerts for MockRepository (offline preview mode).
final List<MarketAlert> mockAlerts = [
  MarketAlert(
    alertId: 'mock-1',
    alertType: 'RSI_OVERBOUGHT',
    symbol: 'BTCUSDT',
    timeframe: '1h',
    price: 64230.0,
    title: 'RSI Extremely Overbought',
    message: 'RSI(14) at 83.4 — extremely overbought',
    bias: 'BEARISH',
    metrics: const {'rsi': 83.4},
    createdAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 12))
        .toIso8601String(),
  ),
  MarketAlert(
    alertId: 'mock-2',
    alertType: 'NEAR_RESISTANCE',
    symbol: 'ETHUSDT',
    timeframe: '1h',
    price: 1801.2,
    title: 'Near Horizontal Resistance',
    message: 'Price 0.14% from resistance at 1803.8 (5 touches)',
    bias: 'BEARISH',
    metrics: const {
      'level_price': 1803.8,
      'touches': 5,
      'touch_count': 5,
      'zone_low': 1801.1,
      'zone_high': 1806.5,
      'first_touch_bars_ago': 42,
      'last_touch_bars_ago': 1,
    },
    createdAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1, minutes: 5))
        .toIso8601String(),
  ),
  MarketAlert(
    alertId: 'mock-3',
    alertType: 'ABNORMAL_VOLATILITY',
    symbol: 'SOLUSDT',
    timeframe: '15m',
    price: 148.6,
    title: 'Abnormal Volatility',
    message: 'Candle range 4.1× normal — −2.31% move',
    bias: 'NEUTRAL',
    metrics: const {'tr_mult': 4.1, 'move_pct': -2.31},
    createdAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 3))
        .toIso8601String(),
  ),
  MarketAlert(
    alertId: 'mock-4',
    alertType: 'RSI_BULLISH_DIVERGENCE',
    symbol: 'XRPUSDT',
    timeframe: '4h',
    price: 1.042,
    title: 'RSI Bullish Divergence',
    message: 'Price made a lower low while RSI rose 24→37',
    bias: 'BULLISH',
    metrics: const {
      'rsi_first': 24.0,
      'rsi_second': 37.0,
      'pivot_a_bars_ago': 18,
      'pivot_b_bars_ago': 4,
      'pivot_a_price': 0.981,
      'pivot_b_price': 0.958,
    },
    createdAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 6))
        .toIso8601String(),
  ),
];

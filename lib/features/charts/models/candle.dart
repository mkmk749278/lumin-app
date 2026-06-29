/// OHLCV candle for the Market Charts tab.
///
/// Sourced from Binance public `/fapi/v1/klines` (history) and the kline
/// WebSocket (live). `time` is a UNIX timestamp in **seconds** — the unit
/// TradingView Lightweight Charts expects for intraday series
/// (`UTCTimestamp`). Binance reports `openTime` in milliseconds, so we divide.
library;

class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  /// Candle open time, **seconds** since epoch (Lightweight Charts unit).
  final int time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  /// Parse one Binance kline array:
  /// `[openTime, open, high, low, close, volume, closeTime, ...]`
  /// (REST `/klines` rows and the `k` object's array-equivalent fields).
  factory Candle.fromKlineArray(List<dynamic> a) {
    return Candle(
      time: (_num(a[0]) ~/ 1000),
      open: _dbl(a[1]),
      high: _dbl(a[2]),
      low: _dbl(a[3]),
      close: _dbl(a[4]),
      volume: _dbl(a[5]),
    );
  }

  /// Parse the `k` payload from a `<symbol>@kline_<tf>` WS frame:
  /// `{ "t": openTimeMs, "o","h","l","c","v": strings, "x": isClosed }`.
  factory Candle.fromWsKline(Map<String, dynamic> k) {
    return Candle(
      time: (_num(k['t']) ~/ 1000),
      open: _dbl(k['o']),
      high: _dbl(k['h']),
      low: _dbl(k['l']),
      close: _dbl(k['c']),
      volume: _dbl(k['v']),
    );
  }

  /// Shape Lightweight Charts' candlestick series consumes (via the bridge).
  Map<String, dynamic> toChartJson() => {
        'time': time,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
      };

  /// Shape for the volume histogram series.
  Map<String, dynamic> toVolumeJson() => {'time': time, 'value': volume};

  static int _num(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? (double.tryParse(v)?.toInt() ?? 0);
    if (v is num) return v.toInt();
    return 0;
  }

  static double _dbl(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    if (v is num) return v.toDouble();
    return 0.0;
  }
}

/// One row of the Charts-tab pair list: a tradable perp + its 24h context.
class MarketTicker {
  const MarketTicker({
    required this.symbol,
    required this.lastPrice,
    required this.changePct,
    required this.quoteVolume,
  });

  final String symbol;
  final double lastPrice;

  /// 24h price change percent (e.g. -23.5 for −23.5%).
  final double changePct;

  /// 24h quote volume (USDT) — used to sort/floor the list by liquidity.
  final double quoteVolume;

  factory MarketTicker.fromJson(Map<String, dynamic> j) {
    return MarketTicker(
      symbol: (j['symbol'] ?? '').toString(),
      lastPrice: Candle._dbl(j['lastPrice']),
      changePct: Candle._dbl(j['priceChangePercent']),
      quoteVolume: Candle._dbl(j['quoteVolume']),
    );
  }
}

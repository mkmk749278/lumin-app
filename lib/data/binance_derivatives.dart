/// Binance USDⓈ-M **derivatives context** for one pair — public, no key.
///
/// The chart screen's strip under the candles (2026-09-25 Charts redesign,
/// part 2): what a futures trader reads before acting and a spot chart
/// cannot show.
///
///   GET /fapi/v1/premiumIndex?symbol=                       funding + next time   (weight 1)
///   GET /futures/data/openInterestHist?period=1h&limit=25   OI now vs 24h ago     (weight 0)
///   GET /futures/data/globalLongShortAccountRatio?period=1h accounts long / short (weight 0)
///   GET /futures/data/takerlongshortRatio?period=1h         taker buy / sell      (weight 0)
///
/// App→Binance direct, like the klines: the engine sees none of it. Each
/// figure is fetched and parsed on its own, and a figure that fails is null
/// and renders as "—": a missing funding rate is not a zero funding rate,
/// and one blocked endpoint must not blank the other three.
///
/// These are descriptions of positioning, never forecasts. The strip names
/// what each number is ("longs pay shorts") and draws no conclusion from it.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class DerivativesSnapshot {
  const DerivativesSnapshot({
    this.fundingRate,
    this.nextFundingTime,
    this.openInterestUsd,
    this.openInterestChange24hPct,
    this.longAccountShare,
    this.takerBuyShare,
    required this.fetchedAt,
  });

  /// Last funding rate as a fraction (0.0001 = 0.01%).
  final double? fundingRate;
  final DateTime? nextFundingTime;

  /// Open interest in USDT, newest hourly bucket.
  final double? openInterestUsd;

  /// Percent change of [openInterestUsd] against 24 buckets earlier.
  final double? openInterestChange24hPct;

  /// Share of accounts net long, 0..1 (Binance "global" ratio).
  final double? longAccountShare;

  /// Share of taker volume that was buying over the last hour, 0..1.
  final double? takerBuyShare;

  final DateTime fetchedAt;

  bool get isEmpty =>
      fundingRate == null && openInterestUsd == null && longAccountShare == null && takerBuyShare == null;
}

class BinanceDerivatives {
  BinanceDerivatives({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const String baseUrl = 'https://fapi.binance.com';

  Future<DerivativesSnapshot> snapshot(String symbol) async {
    final results = await Future.wait([
      _get('/fapi/v1/premiumIndex?symbol=$symbol'),
      _get('/futures/data/openInterestHist?symbol=$symbol&period=1h&limit=25'),
      _get('/futures/data/globalLongShortAccountRatio?symbol=$symbol&period=1h&limit=1'),
      _get('/futures/data/takerlongshortRatio?symbol=$symbol&period=1h&limit=1'),
    ]);
    final funding = parseFunding(results[0]);
    final oi = parseOpenInterest(results[1]);
    return DerivativesSnapshot(
      fundingRate: funding.$1,
      nextFundingTime: funding.$2,
      openInterestUsd: oi.$1,
      openInterestChange24hPct: oi.$2,
      longAccountShare: parseLongAccountShare(results[2]),
      takerBuyShare: parseTakerBuyShare(results[3]),
      fetchedAt: DateTime.now(),
    );
  }

  /// Decoded JSON, or null on any failure — each figure fails alone.
  Future<Object?> _get(String path) async {
    try {
      final r = await _http.get(Uri.parse('$baseUrl$path')).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body);
    } catch (_) {
      return null;
    }
  }

  void close() => _http.close();
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// premiumIndex → (lastFundingRate, nextFundingTime).
(double?, DateTime?) parseFunding(Object? j) {
  if (j is! Map) return (null, null);
  final rate = _num(j['lastFundingRate']);
  final next = _num(j['nextFundingTime']);
  return (
    rate != null && rate.isFinite ? rate : null,
    next != null && next > 0 ? DateTime.fromMillisecondsSinceEpoch(next.toInt(), isUtc: true) : null,
  );
}

/// openInterestHist (oldest first) → (newest OI in USDT, % change vs the
/// row 24 buckets earlier). The change is null when fewer than 25 rows came
/// back: a change over a shorter window is not a 24h change.
(double?, double?) parseOpenInterest(Object? j) {
  if (j is! List || j.isEmpty) return (null, null);
  double? valueAt(int i) => j[i] is Map ? _num((j[i] as Map)['sumOpenInterestValue']) : null;
  final now = valueAt(j.length - 1);
  if (now == null || now <= 0) return (null, null);
  double? chg;
  if (j.length >= 25) {
    final then = valueAt(j.length - 25);
    if (then != null && then > 0) chg = (now - then) / then * 100;
  }
  return (now, chg);
}

/// globalLongShortAccountRatio → share of accounts long (0..1).
double? parseLongAccountShare(Object? j) {
  if (j is! List || j.isEmpty || j.last is! Map) return null;
  final v = _num((j.last as Map)['longAccount']);
  return v != null && v >= 0 && v <= 1 ? v : null;
}

/// takerlongshortRatio → buy share of taker volume (0..1).
double? parseTakerBuyShare(Object? j) {
  if (j is! List || j.isEmpty || j.last is! Map) return null;
  final row = j.last as Map;
  final buy = _num(row['buyVol']);
  final sell = _num(row['sellVol']);
  if (buy == null || sell == null || buy + sell <= 0) return null;
  return buy / (buy + sell);
}

/// `+0.0100%` — funding is quoted to four places because 0.01% is normal
/// and 0.05% is not; two places would print both as 0.01%.
String formatFundingRate(double r) => '${r >= 0 ? '+' : ''}${(r * 100).toStringAsFixed(4)}%';

/// `3h 12m` / `12m` / `now` until the next funding.
String formatCountdown(DateTime next, DateTime now) {
  final d = next.difference(now);
  if (d.inMinutes <= 0) return 'now';
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// Which side pays at the next funding — the plain-words reading of the sign.
String fundingPayer(double r) {
  if (r > 0) return 'Longs pay shorts';
  if (r < 0) return 'Shorts pay longs';
  return 'No payment';
}

/// The same, short enough for a quarter-width tile.
String fundingPayerShort(double r) {
  if (r > 0) return 'Longs pay';
  if (r < 0) return 'Shorts pay';
  return 'Nobody pays';
}

/// Binance Futures **public market data** — unsigned, mainnet, no API key.
///
/// Separate from [BinanceClient] (the signed, key-holding, possibly-testnet
/// order client) on purpose: chart data must always reflect real **mainnet**
/// prices regardless of a user's trading-testnet setting, and it touches no
/// secrets. All endpoints here are public and free; the app calls Binance
/// directly, so there is no load on the Lumin engine.
///
/// Endpoints:
///   GET /fapi/v1/klines?symbol=&interval=&limit=   — OHLCV history (≤1500)
///   GET /fapi/v1/ticker/24hr                       — all-symbol 24h stats
///   GET /fapi/v1/exchangeInfo                      — tradable perp universe
///
/// Live updates come from the kline WebSocket and live in [BinanceKlineSocket]
/// (added with the chart screen), not here.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/charts/models/candle.dart';

class BinanceMarketData {
  BinanceMarketData({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Always mainnet — chart prices are real-market, never testnet.
  static const String baseUrl = 'https://fapi.binance.com';

  /// Timeframes offered by the Charts tab → Binance interval codes.
  static const Map<String, String> intervals = {
    '1m': '1m',
    '5m': '5m',
    '15m': '15m',
    '1h': '1h',
    '4h': '4h',
  };

  /// OHLCV history for [symbol] at [interval] (Binance code, e.g. `15m`).
  /// [limit] is clamped to Binance's 1500-row ceiling.
  Future<List<Candle>> klines({
    required String symbol,
    String interval = '15m',
    int limit = 500,
  }) async {
    final lim = limit.clamp(1, 1500);
    final uri = Uri.parse(
      '$baseUrl/fapi/v1/klines?symbol=$symbol&interval=$interval&limit=$lim',
    );
    final resp = await _http.get(uri).timeout(const Duration(seconds: 12));
    _ensureOk(resp, '/klines');
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) {
      throw BinanceMarketDataError('unexpected /klines payload for $symbol');
    }
    final out = <Candle>[];
    for (final row in decoded) {
      if (row is List && row.length >= 6) out.add(Candle.fromKlineArray(row));
    }
    return out;
  }

  /// 24h ticker for every symbol, parsed into [MarketTicker] rows. The Charts
  /// tab uses this for the per-row last price + %change context.
  Future<List<MarketTicker>> ticker24h() async {
    final uri = Uri.parse('$baseUrl/fapi/v1/ticker/24hr');
    final resp = await _http.get(uri).timeout(const Duration(seconds: 12));
    _ensureOk(resp, '/ticker/24hr');
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) {
      throw BinanceMarketDataError('unexpected /ticker/24hr payload');
    }
    final out = <MarketTicker>[];
    for (final row in decoded) {
      if (row is Map<String, dynamic>) out.add(MarketTicker.fromJson(row));
    }
    return out;
  }

  /// The tradable USDT-M **perpetual** universe (symbol strings), for the
  /// full pair list. Filters to `TRADING` status, `PERPETUAL` contracts,
  /// USDT-quoted — the set a user can actually chart/trade.
  Future<List<String>> perpetualSymbols() async {
    final uri = Uri.parse('$baseUrl/fapi/v1/exchangeInfo');
    final resp = await _http.get(uri).timeout(const Duration(seconds: 15));
    _ensureOk(resp, '/exchangeInfo');
    final j = jsonDecode(resp.body);
    if (j is! Map<String, dynamic>) {
      throw BinanceMarketDataError('unexpected /exchangeInfo payload');
    }
    final symbols = j['symbols'] as List? ?? const [];
    final out = <String>[];
    for (final raw in symbols) {
      if (raw is! Map<String, dynamic>) continue;
      if (raw['status'] != 'TRADING') continue;
      if (raw['contractType'] != 'PERPETUAL') continue;
      if (raw['quoteAsset'] != 'USDT') continue;
      final sym = raw['symbol'];
      if (sym is String && sym.isNotEmpty) out.add(sym);
    }
    out.sort();
    return out;
  }

  void _ensureOk(http.Response resp, String what) {
    if (resp.statusCode == 200) return;
    String msg = 'HTTP ${resp.statusCode} on $what';
    try {
      final j = jsonDecode(resp.body);
      if (j is Map && j['msg'] != null) msg = j['msg'].toString();
    } catch (_) {/* keep default */}
    throw BinanceMarketDataError(msg, statusCode: resp.statusCode);
  }

  void close() => _http.close();
}

class BinanceMarketDataError implements Exception {
  BinanceMarketDataError(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'BinanceMarketDataError($statusCode): $message';
}

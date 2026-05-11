/// Binance Futures REST client — HMAC-SHA256 signed requests.
///
/// Phase 3 of the per-user expansion.  The engine never holds user
/// Binance keys; the app holds them in flutter_secure_storage and fires
/// orders directly against Binance with HMAC-signed REST.  Smallest
/// blast radius if engine is breached — only that user's keys are at
/// risk, the engine can't fire on their behalf.
///
/// Phase 3a (this PR) wires the keys-management UX: validate a key /
/// secret pair against ``GET /fapi/v2/account`` so the user can
/// confirm "yes, the engine can see my balance" before saving.  Phase
/// 3b adds the order-placement methods (``createMarketOrder``,
/// ``createTpSlOrder``).
///
/// Endpoint reference (no SDK dep — surface is small):
///   GET  /fapi/v2/account            (signed)  account state + balance
///   POST /fapi/v1/order              (signed)  place an order
///   GET  /fapi/v2/positionRisk       (signed)  open positions per symbol
///
/// Signing rule: build query string of all params + ``timestamp`` +
/// optional ``recvWindow``, HMAC-SHA256 with the API secret as key, hex
/// digest is appended as the ``signature`` query param.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class BinanceError implements Exception {
  BinanceError({required this.statusCode, required this.message, this.code});

  /// HTTP status from Binance (typically 401, 403, 418, 429, 5xx).
  final int statusCode;

  /// Human-readable message.  For non-200 responses Binance returns
  /// JSON like ``{"code": -2014, "msg": "API-key format invalid."}``;
  /// we surface ``msg`` here when present.
  final String message;

  /// Binance's own error code, when present (negative integers).
  final int? code;

  @override
  String toString() => 'BinanceError($statusCode, code=$code): $message';
}

/// Decoded subset of ``GET /fapi/v2/account`` response.  Keeps only
/// the fields the app surfaces (balance + position summary); the
/// full payload has dozens of fields we don't care about yet.
class BinanceAccount {
  const BinanceAccount({
    required this.totalWalletBalance,
    required this.availableBalance,
    required this.totalUnrealizedProfit,
    required this.openPositionCount,
    required this.canTrade,
    required this.feeTier,
  });

  final double totalWalletBalance;
  final double availableBalance;
  final double totalUnrealizedProfit;
  final int openPositionCount;
  final bool canTrade;
  final int feeTier;

  factory BinanceAccount.fromJson(Map<String, dynamic> j) {
    final positions = (j['positions'] as List? ?? const [])
        .where((p) {
          final amt = double.tryParse(
                  (p as Map<String, dynamic>)['positionAmt'] as String? ?? '0') ??
              0.0;
          return amt.abs() > 0;
        })
        .length;
    return BinanceAccount(
      totalWalletBalance: _asDouble(j['totalWalletBalance']),
      availableBalance: _asDouble(j['availableBalance']),
      totalUnrealizedProfit: _asDouble(j['totalUnrealizedProfit']),
      openPositionCount: positions,
      canTrade: j['canTrade'] as bool? ?? false,
      feeTier: (j['feeTier'] as num?)?.toInt() ?? 0,
    );
  }
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

/// Per-symbol filters from /fapi/v1/exchangeInfo.  We only consume the
/// three that matter for order placement; everything else stays on
/// Binance's side.
class BinanceSymbolFilters {
  const BinanceSymbolFilters({
    required this.symbol,
    required this.tickSize,
    required this.stepSize,
    required this.minQty,
    required this.minNotional,
  });

  /// Smallest price increment.  Round prices DOWN for SELL stops /
  /// UP for BUY stops to avoid invalid trigger placement.
  final double tickSize;

  /// Smallest quantity increment.  Round qty DOWN to fit.
  final double stepSize;

  /// Smallest tradable quantity.  Below this the broker rejects.
  final double minQty;

  /// Smallest notional value (price × qty).  Below this the broker
  /// rejects with -4164 "Order's notional must be no smaller than..."
  final double minNotional;

  final String symbol;

  factory BinanceSymbolFilters.fromJson(Map<String, dynamic> j) {
    double tick = 0.0;
    double step = 0.0;
    double minQ = 0.0;
    double minN = 0.0;
    for (final raw in j['filters'] as List? ?? const []) {
      final f = raw as Map<String, dynamic>;
      switch (f['filterType']) {
        case 'PRICE_FILTER':
          tick = _asDouble(f['tickSize']);
          break;
        case 'LOT_SIZE':
          step = _asDouble(f['stepSize']);
          minQ = _asDouble(f['minQty']);
          break;
        case 'MIN_NOTIONAL':
          minN = _asDouble(f['notional']);
          break;
      }
    }
    return BinanceSymbolFilters(
      symbol: j['symbol'] as String,
      tickSize: tick,
      stepSize: step,
      minQty: minQ,
      minNotional: minN,
    );
  }

  /// Round ``qty`` DOWN to a multiple of ``stepSize``.  Returns 0 if
  /// the result would be below ``minQty``.
  double roundQty(double qty) {
    if (stepSize <= 0) return qty;
    final rounded = (qty / stepSize).floor() * stepSize;
    if (rounded < minQty) return 0.0;
    // Floating point drift cleanup — Binance rejects "9.999999" when
    // the step is 0.01.
    final decimals = _decimalsFor(stepSize);
    return double.parse(rounded.toStringAsFixed(decimals));
  }

  /// Round ``price`` to the nearest tick.  Caller picks direction
  /// via the ``floor`` flag — STOPs below entry round DOWN, TPs above
  /// entry round UP, so the broker accepts them.
  double roundPrice(double price, {bool floor = true}) {
    if (tickSize <= 0) return price;
    final n = price / tickSize;
    final rounded = floor ? n.floorToDouble() : n.ceilToDouble();
    final result = rounded * tickSize;
    final decimals = _decimalsFor(tickSize);
    return double.parse(result.toStringAsFixed(decimals));
  }

  static int _decimalsFor(double step) {
    final s = step.toString();
    final dot = s.indexOf('.');
    if (dot < 0) return 0;
    return s.length - dot - 1;
  }
}

class BinanceClient {
  BinanceClient({
    required this.apiKey,
    required this.apiSecret,
    required this.testnet,
    http.Client? httpClient,
    this.recvWindow = 5000,
  }) : _http = httpClient ?? http.Client();

  final String apiKey;
  final String apiSecret;
  final bool testnet;
  final int recvWindow;
  final http.Client _http;

  /// Mainnet: ``fapi.binance.com``.  Testnet: ``testnet.binancefuture.com``.
  /// Both expose the same v1/v2 paths used here.
  String get baseUrl => testnet
      ? 'https://testnet.binancefuture.com'
      : 'https://fapi.binance.com';

  /// Fetch the user's Futures account state.  Used by the "Test
  /// connection" button on the API keys page; also seeds the
  /// account-balance card on the Trade tab in Phase 3c.
  Future<BinanceAccount> getAccount() async {
    final body = await _signedGet('/fapi/v2/account');
    if (body is! Map<String, dynamic>) {
      throw BinanceError(
        statusCode: 200,
        message: 'unexpected response shape from /fapi/v2/account',
      );
    }
    return BinanceAccount.fromJson(body);
  }

  /// Hit ``GET /fapi/v1/time`` (unsigned, public).  Cheap clock sanity-
  /// check — the device's local clock must be within ``recvWindow`` ms
  /// of Binance's, otherwise every signed request returns -1021
  /// "Timestamp for this request is outside of the recvWindow."  Used
  /// by the keys page to surface a clear error before the user blames
  /// their key/secret.
  Future<int> getServerTime() async {
    final uri = Uri.parse('$baseUrl/fapi/v1/time');
    final resp = await _http
        .get(uri)
        .timeout(const Duration(seconds: 10));
    _ensureOk(resp);
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return (j['serverTime'] as num).toInt();
  }

  /// Symbol exchange-info subset — ``stepSize`` for qty rounding +
  /// ``tickSize`` for price rounding + ``minQty`` for minimum order.
  /// Cached at the call site; this is the unsigned public endpoint.
  Future<BinanceSymbolFilters> getSymbolFilters(String symbol) async {
    final uri = Uri.parse('$baseUrl/fapi/v1/exchangeInfo');
    final resp = await _http.get(uri).timeout(const Duration(seconds: 12));
    _ensureOk(resp);
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final symbols = j['symbols'] as List? ?? const [];
    for (final raw in symbols) {
      final entry = raw as Map<String, dynamic>;
      if (entry['symbol'] == symbol) {
        return BinanceSymbolFilters.fromJson(entry);
      }
    }
    throw BinanceError(
      statusCode: 200,
      message: 'symbol $symbol not listed on $baseUrl',
    );
  }

  /// Current mark price — used by the review sheet to show the
  /// expected fill price next to the signal's nominal entry.
  Future<double> getMarkPrice(String symbol) async {
    final uri = Uri.parse('$baseUrl/fapi/v1/premiumIndex?symbol=$symbol');
    final resp = await _http.get(uri).timeout(const Duration(seconds: 10));
    _ensureOk(resp);
    final j = jsonDecode(resp.body);
    if (j is Map<String, dynamic>) {
      return _asDouble(j['markPrice']);
    }
    throw BinanceError(
      statusCode: 200,
      message: 'unexpected markPrice payload',
    );
  }

  /// Set per-symbol leverage.  Binance Futures requires this to be
  /// configured before placing an order at that leverage; doing it
  /// per-symbol-per-call is idempotent + cheap.
  Future<void> setLeverage(String symbol, int leverage) async {
    await _signedPost('/fapi/v1/leverage', {
      'symbol': symbol,
      'leverage': leverage,
    });
  }

  /// Place a MARKET order for ``symbol`` in ``side`` direction at
  /// ``quantity`` (already step-rounded).  Returns the broker order
  /// blob — caller pulls ``orderId``, ``avgPrice``, ``executedQty``
  /// out of it.
  ///
  /// ``newClientOrderId`` is set to the engine's signal_id so we get
  /// idempotency against accidental retries (a duplicate POST with the
  /// same client order ID returns the existing fill).
  Future<Map<String, dynamic>> createMarketOrder({
    required String symbol,
    required String side,
    required double quantity,
    String? clientOrderId,
  }) async {
    final body = await _signedPost('/fapi/v1/order', {
      'symbol': symbol,
      'side': side,
      'type': 'MARKET',
      'quantity': quantity,
      if (clientOrderId != null) 'newClientOrderId': clientOrderId,
    });
    return body as Map<String, dynamic>;
  }

  /// Place a reduce-only STOP_MARKET (SL) or TAKE_PROFIT_MARKET (TP)
  /// trigger order.  ``reduceOnly=true`` so it can't accidentally flip
  /// the position into the opposite direction once the entry is
  /// closed.  ``closePosition=true`` flattens whatever quantity is
  /// open at the time, which is what we want for SL — even if a
  /// later DCA adds more.  TP1 uses ``quantity`` instead so partial
  /// TP-takes don't close the runner.
  Future<Map<String, dynamic>> createStopOrder({
    required String symbol,
    required String side,
    required String stopType, // 'STOP_MARKET' | 'TAKE_PROFIT_MARKET'
    required double stopPrice,
    double? quantity,
    bool closePosition = false,
    String? clientOrderId,
  }) async {
    final params = <String, dynamic>{
      'symbol': symbol,
      'side': side,
      'type': stopType,
      'stopPrice': stopPrice,
      if (closePosition) 'closePosition': 'true' else 'reduceOnly': 'true',
      if (quantity != null && !closePosition) 'quantity': quantity,
      if (clientOrderId != null) 'newClientOrderId': clientOrderId,
    };
    final body = await _signedPost('/fapi/v1/order', params);
    return body as Map<String, dynamic>;
  }

  // ----- signed primitives -------------------------------------------

  Future<dynamic> _signedGet(
    String path, [
    Map<String, dynamic>? params,
  ]) async {
    final qs = _buildSignedQuery(params);
    final uri = Uri.parse('$baseUrl$path?$qs');
    final resp = await _http
        .get(uri, headers: {'X-MBX-APIKEY': apiKey})
        .timeout(const Duration(seconds: 12));
    _ensureOk(resp);
    return resp.body.isEmpty ? null : jsonDecode(resp.body);
  }

  Future<dynamic> _signedPost(
    String path,
    Map<String, dynamic> params,
  ) async {
    // Binance Futures accepts POST params either as query string or as
    // form-encoded body.  Query string is simpler — same signing path
    // as GET, no separate Content-Type handling.
    final qs = _buildSignedQuery(params);
    final uri = Uri.parse('$baseUrl$path?$qs');
    final resp = await _http
        .post(uri, headers: {'X-MBX-APIKEY': apiKey})
        .timeout(const Duration(seconds: 12));
    _ensureOk(resp);
    return resp.body.isEmpty ? null : jsonDecode(resp.body);
  }

  /// Compose the signed query string: ``key=value&...&timestamp=NNN&recvWindow=NNN&signature=HEX``.
  /// Order of inclusion in the signed bytes must match the request URL,
  /// so we sort by insertion order (Map preserves it in Dart).  Binance
  /// doesn't require alphabetical ordering — only that the signature
  /// matches the actual query string sent.
  String _buildSignedQuery(Map<String, dynamic>? params) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final all = <String, String>{
      ...?params?.map((k, v) => MapEntry(k, '$v')),
      'recvWindow': '$recvWindow',
      'timestamp': '$ts',
    };
    final unsigned = all.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final sig = _sign(unsigned);
    return '$unsigned&signature=$sig';
  }

  String _sign(String payload) {
    final hmac = Hmac(sha256, utf8.encode(apiSecret));
    final digest = hmac.convert(utf8.encode(payload));
    return digest.toString(); // hex
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode == 200) return;
    String msg = resp.body;
    int? code;
    try {
      final j = jsonDecode(resp.body);
      if (j is Map) {
        msg = (j['msg'] as String?) ?? msg;
        code = (j['code'] as num?)?.toInt();
      }
    } catch (_) {
      // Body wasn't JSON — keep the raw text.
    }
    throw BinanceError(
      statusCode: resp.statusCode,
      message: msg,
      code: code,
    );
  }

  void dispose() => _http.close();
}

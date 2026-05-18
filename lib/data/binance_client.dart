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

/// Abstract surface ``OrderExecutor`` consumes from ``BinanceClient``.
/// Only the methods the executor actually calls — keeps the test
/// fake's blast radius tight and decouples test compile from the
/// rest of BinanceClient's surface (getServerTime, getMarkPrice,
/// listenKey lifecycle, etc.).  ``BinanceClient`` implements this
/// interface so production wiring is unchanged.
abstract class BinanceClientApi {
  Future<BinanceSymbolFilters> getSymbolFilters(String symbol);
  Future<void> setLeverage(String symbol, int leverage);
  Future<Map<String, dynamic>> createMarketOrder({
    required String symbol,
    required String side,
    required double quantity,
    String? clientOrderId,
  });
  Future<Map<String, dynamic>> createStopOrder({
    required String symbol,
    required String side,
    required String stopType,
    required double stopPrice,
    double? quantity,
    bool closePosition = false,
    String? clientOrderId,
  });
  Future<Map<String, dynamic>> cancelOrder({
    required String symbol,
    int? orderId,
    String? origClientOrderId,
  });
  Future<Map<String, dynamic>> closePartialMarket({
    required String symbol,
    required String side,
    required double quantity,
    String? clientOrderId,
  });
  void dispose();
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

/// Per-symbol open position from /fapi/v2/positionRisk.  Only entries
/// where ``positionAmt`` is non-zero are surfaced — Binance returns
/// every tradable symbol regardless of whether the user holds.
class BinancePosition {
  const BinancePosition({
    required this.symbol,
    required this.positionAmt,
    required this.entryPrice,
    required this.markPrice,
    required this.unrealizedProfit,
    required this.leverage,
    required this.marginType,
    required this.liquidationPrice,
    required this.updatedAt,
  });

  final String symbol;

  /// Signed quantity — positive for LONG, negative for SHORT.
  final double positionAmt;

  final double entryPrice;
  final double markPrice;
  final double unrealizedProfit;
  final double leverage;

  /// ``cross`` or ``isolated``.
  final String marginType;

  /// 0 when the broker hasn't computed it yet (very-small positions).
  final double liquidationPrice;

  /// ms since epoch — Binance's ``updateTime`` field.
  final int updatedAt;

  bool get isLong => positionAmt > 0;
  bool get isShort => positionAmt < 0;
  String get side => isLong ? 'LONG' : 'SHORT';
  double get qty => positionAmt.abs();
  double get notional => qty * markPrice;

  /// P&L as a fraction of margin posted (handy for percentage display
  /// without us tracking the user's per-position margin separately).
  /// Returns 0 when entryPrice is 0 — avoids divide-by-zero on fresh
  /// rows.
  double get pnlPctOnMargin {
    if (entryPrice <= 0 || leverage <= 0) return 0.0;
    final movePct = isLong
        ? ((markPrice - entryPrice) / entryPrice)
        : ((entryPrice - markPrice) / entryPrice);
    return movePct * leverage * 100.0;
  }

  factory BinancePosition.fromJson(Map<String, dynamic> j) =>
      BinancePosition(
        symbol: j['symbol'] as String,
        positionAmt: _asDouble(j['positionAmt']),
        entryPrice: _asDouble(j['entryPrice']),
        markPrice: _asDouble(j['markPrice']),
        unrealizedProfit: _asDouble(j['unRealizedProfit']),
        leverage: _asDouble(j['leverage']),
        marginType: j['marginType'] as String? ?? 'cross',
        liquidationPrice: _asDouble(j['liquidationPrice']),
        updatedAt: (j['updateTime'] as num?)?.toInt() ?? 0,
      );
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

class BinanceClient implements BinanceClientApi {
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

  /// All open positions on the user's Futures account.
  ///
  /// /fapi/v2/positionRisk returns every tradable symbol; we filter
  /// to ``positionAmt != 0``.  Cheap signed call (~150ms p50).  Used
  /// by the Trade tab to display real positions instead of engine-
  /// paper, and by AutoTradeWatcher to enforce the per-user concurrent
  /// cap before each fire.
  Future<List<BinancePosition>> getOpenPositions() async {
    final body = await _signedGet('/fapi/v2/positionRisk');
    if (body is! List) {
      throw BinanceError(
        statusCode: 200,
        message: 'unexpected response shape from /fapi/v2/positionRisk',
      );
    }
    final positions = <BinancePosition>[];
    for (final raw in body) {
      if (raw is! Map<String, dynamic>) continue;
      final amt = _asDouble(raw['positionAmt']);
      if (amt == 0.0) continue;
      positions.add(BinancePosition.fromJson(raw));
    }
    return positions;
  }

  /// Symbol exchange-info subset — ``stepSize`` for qty rounding +
  /// ``tickSize`` for price rounding + ``minQty`` for minimum order.
  /// Cached at the call site; this is the unsigned public endpoint.
  @override
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
  @override
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
  @override
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
  @override
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

  /// Cancel a single open order on *symbol*.  Used by the Phase 4
  /// pre-TP partial-close flow to replace the original SL with a new
  /// breakeven SL after the partial has been banked (the original SL
  /// would over-close — closePosition=true would flatten the residual
  /// too).
  ///
  /// Idempotent on the caller's side: Binance returns ``-2011 Unknown
  /// order sent`` when the order was already cancelled or filled;
  /// callers treat that as a no-op and proceed.
  @override
  Future<Map<String, dynamic>> cancelOrder({
    required String symbol,
    int? orderId,
    String? origClientOrderId,
  }) async {
    if (orderId == null && origClientOrderId == null) {
      throw ArgumentError(
        'cancelOrder requires either orderId or origClientOrderId',
      );
    }
    final params = <String, dynamic>{
      'symbol': symbol,
      if (orderId != null) 'orderId': orderId,
      if (origClientOrderId != null) 'origClientOrderId': origClientOrderId,
    };
    final body = await _signedDelete('/fapi/v1/order', params);
    return body as Map<String, dynamic>;
  }

  /// Reduce-only MARKET close for a fraction of an open position.  Used
  /// by Phase 4 pre-TP execution to bank ``grab_fraction × entry_qty``
  /// at market when the engine reports the pre-TP threshold fired.
  /// ``side`` is the close side (SELL for a LONG entry, BUY for SHORT).
  ///
  /// ``reduceOnly=true`` ensures the order can never flip the position
  /// into the opposite direction — even if a race with the SL flatten
  /// momentarily zeroes the position, the reduce-only guard returns
  /// ``-2022 reduceOnly Order is rejected`` rather than opening a
  /// counter-position.
  @override
  Future<Map<String, dynamic>> closePartialMarket({
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
      'reduceOnly': 'true',
      if (clientOrderId != null) 'newClientOrderId': clientOrderId,
    });
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

  Future<dynamic> _signedDelete(
    String path,
    Map<String, dynamic> params,
  ) async {
    final qs = _buildSignedQuery(params);
    final uri = Uri.parse('$baseUrl$path?$qs');
    final resp = await _http
        .delete(uri, headers: {'X-MBX-APIKEY': apiKey})
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

  @override
  void dispose() => _http.close();
}

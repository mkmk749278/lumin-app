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

/// Typed models for the server-side execution custody flow.
///
/// Mirrors the engine-side ``BinanceConnectRequest`` / ``BinanceConnectResponse``
/// in ``src/api/schemas.py`` (engine PR-2).  The connect flow lives at
/// ``POST /api/binance/connect``; the response on success contains the
/// truncated public key id + the three validation flags
/// (withdraw_disabled_ok / futures_enabled_ok / ip_whitelist_ok).
///
/// On validation failure the engine returns HTTP 400 with a detail
/// message that's user-facing (Binance setting to fix) plus an
/// ``X-Connect-Error-Code`` header carrying a stable token the app
/// can switch on for targeted UI (e.g. deep-link to Binance's API
/// Management page for ``WITHDRAW_ENABLED``).
library;

class BinanceConnectSuccess {
  const BinanceConnectSuccess({
    required this.keyPublicIdFirst8,
    required this.withdrawDisabledOk,
    required this.futuresEnabledOk,
    required this.ipWhitelistOk,
  });

  final String keyPublicIdFirst8;
  final bool withdrawDisabledOk;
  final bool futuresEnabledOk;
  final bool ipWhitelistOk;

  factory BinanceConnectSuccess.fromJson(Map<String, dynamic> j) =>
      BinanceConnectSuccess(
        keyPublicIdFirst8: j['key_public_id_first8'] as String? ?? '',
        withdrawDisabledOk: j['withdraw_disabled_ok'] as bool? ?? false,
        futuresEnabledOk: j['futures_enabled_ok'] as bool? ?? false,
        ipWhitelistOk: j['ip_whitelist_ok'] as bool? ?? false,
      );
}

/// Thrown by [LuminRepository.connectBinanceServerSide] when the
/// engine rejects the connect request.  The ``code`` is the stable
/// ``X-Connect-Error-Code`` header value when present, otherwise
/// ``UNKNOWN``.  The ``detail`` is the engine's user-facing message
/// (typically tells the user which Binance setting to fix).
///
/// ``engineVpsIp`` is the engine's outbound IP (per PR-2's
/// ``X-Engine-VPS-IP`` header) — populated on IP-related failures so
/// the app can display the exact IP to whitelist.
/// Mirror of the engine's ``GET /api/auto-trade/user-status``
/// response.  Drives the Trade-tab banner: when
/// ``autoTradeGloballyEnabled`` is false OR
/// ``autoTradeUserDisabled`` is true, the banner renders the
/// corresponding doctrinal message.
class AutoTradeUserStatus {
  const AutoTradeUserStatus({
    required this.autoTradeGloballyEnabled,
    required this.autoTradeUserDisabled,
    this.disabledReason = '',
    this.disabledAt,
  });

  final bool autoTradeGloballyEnabled;
  final bool autoTradeUserDisabled;
  final String disabledReason;
  final DateTime? disabledAt;

  /// True iff this user can currently auto-trade (both flags clear).
  /// The banner is hidden when this is true.
  bool get isFullyEnabled =>
      autoTradeGloballyEnabled && !autoTradeUserDisabled;

  factory AutoTradeUserStatus.fromJson(Map<String, dynamic> j) =>
      AutoTradeUserStatus(
        autoTradeGloballyEnabled:
            j['auto_trade_globally_enabled'] as bool? ?? false,
        autoTradeUserDisabled:
            j['auto_trade_user_disabled'] as bool? ?? false,
        disabledReason: j['disabled_reason'] as String? ?? '',
        disabledAt: DateTime.tryParse(j['disabled_at'] as String? ?? ''),
      );
}


/// Mirror of the engine's ``GET /api/binance/connect/status`` response.
///
/// Drives the Server-side execution settings page's revisit UI: on
/// page mount we fetch this to decide between rendering the connect
/// form (``connected == false``) or the connected-state card
/// (``connected == true``) with the truncated key id + connect
/// timestamp + validation flags.
class BinanceConnectStatus {
  const BinanceConnectStatus({
    required this.connected,
    this.keyPublicIdFirst8,
    this.connectedAt,
    this.withdrawDisabledOk,
    this.ipWhitelistOk,
  });

  final bool connected;
  final String? keyPublicIdFirst8;
  final DateTime? connectedAt;
  final bool? withdrawDisabledOk;
  final bool? ipWhitelistOk;

  factory BinanceConnectStatus.fromJson(Map<String, dynamic> j) =>
      BinanceConnectStatus(
        connected: j['connected'] as bool? ?? false,
        keyPublicIdFirst8: j['key_public_id_first8'] as String?,
        connectedAt: DateTime.tryParse(j['connected_at'] as String? ?? ''),
        withdrawDisabledOk: j['withdraw_disabled_ok'] as bool?,
        ipWhitelistOk: j['ip_whitelist_ok'] as bool?,
      );

  static const notConnected = BinanceConnectStatus(connected: false);
}


/// Mirror of the engine's ``GET /api/auto-trade/runtime-status`` response.
///
/// Drives the Live-tab "Auto-trade armed" card: each ``boolean`` gate
/// gets a green/red check, the symbol allowlist gets surfaced as a
/// footnote so users understand why some signals don't trigger
/// orders, and ``armed`` collapses the four configurable gates so the
/// card can flip its overall colour.
class AutoTradeRuntimeStatus {
  const AutoTradeRuntimeStatus({
    required this.autoTradeGloballyEnabled,
    required this.autoTradeUserDisabled,
    required this.binanceKeyConnected,
    required this.userMode,
    required this.allowedSymbols,
    required this.effectiveAllowedSymbols,
    required this.armed,
  });

  final bool autoTradeGloballyEnabled;
  final bool autoTradeUserDisabled;
  final bool binanceKeyConnected;
  final String? userMode; // 'live' | 'paper' | 'off' | null

  /// Engine-wide allowlist (the security cap).  Symbol picker shows
  /// this as the universe the user can choose from.
  final List<String> allowedSymbols;

  /// Intersection of engine-wide cap and user's symbol_preference.
  /// When the user has set no preference, equals ``allowedSymbols``.
  /// Drives the Live-tab footnote so it shows what will actually
  /// trade for this user (not just the engine cap).
  final List<String> effectiveAllowedSymbols;

  final bool armed;

  factory AutoTradeRuntimeStatus.fromJson(Map<String, dynamic> j) {
    List<String> parseList(Object? raw) => raw is List
        ? raw.map((s) => s.toString()).toList(growable: false)
        : const <String>[];
    final allowed = parseList(j['allowed_symbols']);
    final effective = j.containsKey('effective_allowed_symbols')
        ? parseList(j['effective_allowed_symbols'])
        : allowed;
    final mode = j['user_mode'];
    return AutoTradeRuntimeStatus(
      autoTradeGloballyEnabled:
          j['auto_trade_globally_enabled'] as bool? ?? false,
      autoTradeUserDisabled: j['auto_trade_user_disabled'] as bool? ?? false,
      binanceKeyConnected: j['binance_key_connected'] as bool? ?? false,
      userMode: mode is String && mode.isNotEmpty ? mode : null,
      allowedSymbols: allowed,
      effectiveAllowedSymbols: effective,
      armed: j['armed'] as bool? ?? false,
    );
  }
}


/// Mirror of one open-position document from
/// ``GET /api/auto-trade/positions`` (engine reads Firestore under
/// ``users/{firebase_uid}/positions/``).  Only the fields the Live-
/// tab card actually renders — full FSM state lives engine-side.
class ServerSidePosition {
  const ServerSidePosition({
    required this.signalId,
    required this.symbol,
    required this.side,
    required this.state,
    required this.entryPriceTarget,
    required this.entryPriceFilled,
    required this.slPrice,
    required this.tp1Price,
    required this.totalQty,
    required this.filledQty,
    required this.realizedPnlTotal,
    required this.pretpFired,
    this.createdAt,
  });

  final String signalId;
  final String symbol;
  final String side; // 'LONG' | 'SHORT'
  final String state; // PENDING | OPEN | PRETP_FIRED | TP1_HIT | etc.
  final double entryPriceTarget;
  final double entryPriceFilled;
  final double slPrice;
  final double tp1Price;
  final double totalQty;
  final double filledQty;
  final double realizedPnlTotal;
  final bool pretpFired;
  final DateTime? createdAt;

  factory ServerSidePosition.fromJson(Map<String, dynamic> j) =>
      ServerSidePosition(
        signalId: j['signal_id'] as String? ?? '',
        symbol: j['symbol'] as String? ?? '',
        side: j['side'] as String? ?? '',
        state: j['state'] as String? ?? '',
        entryPriceTarget: (j['entry_price_target'] as num?)?.toDouble() ?? 0.0,
        entryPriceFilled: (j['entry_price_filled'] as num?)?.toDouble() ?? 0.0,
        slPrice: (j['sl_price'] as num?)?.toDouble() ?? 0.0,
        tp1Price: (j['tp1_price'] as num?)?.toDouble() ?? 0.0,
        totalQty: (j['total_qty'] as num?)?.toDouble() ?? 0.0,
        filledQty: (j['filled_qty'] as num?)?.toDouble() ?? 0.0,
        realizedPnlTotal:
            (j['realized_pnl_total'] as num?)?.toDouble() ?? 0.0,
        pretpFired: j['pretp_fired'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );
}


class BinanceConnectError implements Exception {
  BinanceConnectError({
    required this.code,
    required this.detail,
    this.httpStatus = 0,
    this.engineVpsIp,
  });

  final String code;
  final String detail;
  final int httpStatus;
  final String? engineVpsIp;

  @override
  String toString() => 'BinanceConnectError($code, $httpStatus): $detail';
}

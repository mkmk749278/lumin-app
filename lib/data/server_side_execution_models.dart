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

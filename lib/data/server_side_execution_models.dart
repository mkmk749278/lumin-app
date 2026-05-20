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


/// One row from ``GET /api/auto-trade/recent-events`` — a per-user
/// log of every order-placement attempt the engine made on this
/// account, captured in Firestore by the engine's
/// ``src/execution/dispatch_log.py`` module.
///
/// Drives the Trade-tab "Recent activity for your account" card so
/// the user can see *why* a signal didn't open on their Binance
/// account.  Most common reasons surfaced via [rejectBinanceCode]:
///
/// * ``-2019 'Margin is insufficient.'`` → empty Futures wallet
/// * ``-2014 'Invalid API-key, IP, or permissions.'`` → IP whitelist
///   drifted; user needs to re-whitelist the VPS IP on Binance
/// * ``-4131 'PERCENT_PRICE filter limit.'`` → SL/TP too far from mark
/// * ``-2010 'Account has insufficient balance for requested action.'``
///   → not enough free margin for the position size
///
/// And from [rejectClass] for engine-side rejections (no Binance
/// involvement):
///
/// * ``SymbolNotInUserPreference`` → user's symbol picker excluded the pair
/// * ``UserNotConnectedError`` → keys never connected via /api/binance/connect
/// * ``AutoTradeDisabledError`` → master switch off on the Connect page
/// * ``RateLimitExceededError`` → per-user dispatch rate limit hit
/// * ``PositionCapExceededError`` → user's per-user position cap reached
/// * ``GlobalKillSwitchActiveError`` → operator flipped the global kill switch
///
/// [DispatchEventTranslation] maps these into plain-English copy for
/// the UI; the raw fields are preserved so we can still display the
/// underlying detail in a "Why?" sheet without round-tripping.
class DispatchEvent {
  const DispatchEvent({
    required this.eventId,
    required this.signalId,
    required this.symbol,
    required this.direction,
    required this.outcome,
    required this.timestamp,
    required this.entryPrice,
    required this.totalQty,
    this.rejectClass,
    this.rejectDetail,
    this.rejectBinanceCode,
    this.rejectBinanceMsg,
  });

  final String eventId;
  final String signalId;
  final String symbol;
  final String direction; // 'LONG' | 'SHORT'
  final String outcome; // 'placed' | 'rejected'
  final DateTime timestamp;
  final double entryPrice;
  final double totalQty;
  final String? rejectClass;
  final String? rejectDetail;
  final int? rejectBinanceCode;
  final String? rejectBinanceMsg;

  bool get isPlaced => outcome == 'placed';
  bool get isRejected => outcome == 'rejected';

  factory DispatchEvent.fromJson(Map<String, dynamic> j) => DispatchEvent(
        eventId: j['event_id'] as String? ?? '',
        signalId: j['signal_id'] as String? ?? '',
        symbol: j['symbol'] as String? ?? '',
        direction: j['direction'] as String? ?? '',
        outcome: j['outcome'] as String? ?? '',
        timestamp:
            DateTime.tryParse(j['timestamp'] as String? ?? '') ??
                DateTime.now().toUtc(),
        entryPrice: (j['entry_price'] as num?)?.toDouble() ?? 0.0,
        totalQty: (j['total_qty'] as num?)?.toDouble() ?? 0.0,
        rejectClass: j['reject_class'] as String?,
        rejectDetail: j['reject_detail'] as String?,
        rejectBinanceCode: (j['reject_binance_code'] as num?)?.toInt(),
        rejectBinanceMsg: j['reject_binance_msg'] as String?,
      );
}


/// Translates a [DispatchEvent] rejection into a plain-English,
/// user-actionable explanation.
///
/// Why this is app-side, not engine-side
/// -------------------------------------
///
/// The engine emits raw Binance codes + msgs + our typed exception
/// class names.  These are stable contracts the app can switch on,
/// AND they need to be re-rendered for the user without an engine
/// redeploy when copy needs tweaking.  Doing the translation app-
/// side means we can iterate on the wording without round-tripping
/// through the engine's PR queue.
///
/// The mapping below is intentionally exhaustive for the Binance
/// codes we've observed; unknown codes fall through to a generic
/// "Binance rejected the order ({code})" message with the raw
/// Binance ``msg`` appended so the user still sees the underlying
/// reason even if our copy hasn't caught up.
class DispatchEventTranslation {
  DispatchEventTranslation({
    required this.headline,
    required this.action,
    required this.severity,
  });

  /// Short user-facing reason ("Margin is insufficient", "API key
  /// IP whitelist changed", "Symbol not in your picker").  Goes in
  /// the row's primary line.
  final String headline;

  /// One-sentence what-to-do hint ("Top up your Futures wallet on
  /// Binance and try again").  Goes in the secondary/subtitle line.
  final String action;

  /// Drives chip colour: ``user_action`` = orange (user can fix),
  /// ``transient`` = grey (will retry on next signal), ``system`` =
  /// red (something deeper — operator should know).
  final DispatchEventSeverity severity;

  static DispatchEventTranslation forEvent(DispatchEvent e) {
    if (e.isPlaced) {
      return DispatchEventTranslation(
        headline: 'Placed on Binance',
        action: 'Position is open and tracked by the engine.',
        severity: DispatchEventSeverity.success,
      );
    }
    // Binance-side rejections are switched on by code (stable
    // numeric contract from Binance Futures docs).
    final code = e.rejectBinanceCode;
    if (code != null) {
      switch (code) {
        case -2019:
          return DispatchEventTranslation(
            headline: 'Insufficient margin',
            action:
                'Your Binance Futures wallet does not have enough USDT to '
                'open this size. Top up the Futures wallet on Binance.',
            severity: DispatchEventSeverity.userAction,
          );
        case -2010:
          return DispatchEventTranslation(
            headline: 'Insufficient balance',
            action:
                'Binance reports your account does not have enough free '
                'balance for this order. Check Futures wallet + open positions.',
            severity: DispatchEventSeverity.userAction,
          );
        case -2014:
        case -2015:
          return DispatchEventTranslation(
            headline: 'API key blocked',
            action:
                'Your Binance API key is rejecting our requests — usually '
                'because the IP whitelist changed. Re-connect your key on '
                'the Connect page.',
            severity: DispatchEventSeverity.userAction,
          );
        case -4131:
        case -1013:
          return DispatchEventTranslation(
            headline: 'Order outside allowed price range',
            action:
                'Binance rejected the stop-loss or take-profit because the '
                'price moved too far from the entry. The engine will retry '
                'on the next signal.',
            severity: DispatchEventSeverity.transient,
          );
        case -1111:
        case -4014:
          return DispatchEventTranslation(
            headline: 'Order precision rejected',
            action:
                'The engine rounded the order incorrectly for this symbol. '
                'This is a bug — please report it if it keeps happening.',
            severity: DispatchEventSeverity.system,
          );
        case -2021:
          return DispatchEventTranslation(
            headline: 'Stop order would trigger immediately',
            action:
                'The SL or TP was already past the current mark price when '
                'placed. The engine will retry on the next signal.',
            severity: DispatchEventSeverity.transient,
          );
        case -4164:
          return DispatchEventTranslation(
            headline: 'Order notional too small',
            action:
                'Position size below Binance\'s minimum (~\$5 notional). '
                'Increase your per-trade USDT allocation on the Connect page.',
            severity: DispatchEventSeverity.userAction,
          );
        default:
          final msg = (e.rejectBinanceMsg ?? '').trim();
          return DispatchEventTranslation(
            headline: 'Binance rejected the order ($code)',
            action: msg.isNotEmpty
                ? msg
                : 'Binance returned a rejection without a message. '
                    'The engine will retry on the next signal.',
            severity: DispatchEventSeverity.transient,
          );
      }
    }
    // Engine-side rejections — switch on the typed exception class.
    switch (e.rejectClass) {
      case 'SymbolNotInUserPreference':
        return DispatchEventTranslation(
          headline: 'Symbol not in your picker',
          action:
              '${e.symbol} is not enabled in your symbol preference. Enable '
              'it on the Symbol Preference page to receive these signals.',
          severity: DispatchEventSeverity.userAction,
        );
      case 'UserNotConnectedError':
      case 'AutoTradeDisabledError':
        return DispatchEventTranslation(
          headline: 'Auto-trade is off',
          action:
              'Connect your Binance API key and enable auto-trade on the '
              'Connect page to start placing orders.',
          severity: DispatchEventSeverity.userAction,
        );
      case 'RateLimitExceededError':
        return DispatchEventTranslation(
          headline: 'Rate limit reached',
          action:
              'Too many dispatches in a short window. The engine will '
              'resume on the next signal.',
          severity: DispatchEventSeverity.transient,
        );
      case 'PositionCapExceededError':
        return DispatchEventTranslation(
          headline: 'Position cap reached',
          action:
              'You already have the maximum number of open positions '
              'allowed by the per-user cap.',
          severity: DispatchEventSeverity.transient,
        );
      case 'GlobalKillSwitchActiveError':
        return DispatchEventTranslation(
          headline: 'Trading paused by operator',
          action:
              'The global kill switch is on — no orders are being placed '
              'on any account right now.',
          severity: DispatchEventSeverity.system,
        );
      case 'NotGloballyEnabledError':
        return DispatchEventTranslation(
          headline: 'Auto-trade not yet enabled',
          action:
              'Server-side execution is in beta and not yet enabled for '
              'your account.',
          severity: DispatchEventSeverity.system,
        );
      case 'OrderRejectedByBinance':
        // Fell through code-switch (Binance returned an error
        // without a parseable numeric code).  Surface the detail.
        return DispatchEventTranslation(
          headline: 'Binance rejected the order',
          action:
              (e.rejectBinanceMsg ?? e.rejectDetail ?? 'Unknown reason').trim(),
          severity: DispatchEventSeverity.transient,
        );
      default:
        return DispatchEventTranslation(
          headline: e.rejectClass ?? 'Rejected',
          action:
              (e.rejectDetail ?? 'No detail available from the engine.').trim(),
          severity: DispatchEventSeverity.system,
        );
    }
  }
}

enum DispatchEventSeverity {
  success, // green chip — order placed on Binance
  userAction, // orange chip — user can fix (top up, re-whitelist, etc.)
  transient, // grey chip — engine will retry on the next signal
  system, // red chip — operator-side issue or app/engine bug
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

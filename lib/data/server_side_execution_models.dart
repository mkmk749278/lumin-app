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


/// Mirror of the engine's ``GET /api/binance/connect/info`` response.
///
/// Non-secret onboarding info shown on the Server-side execution page
/// BEFORE a connect attempt.  Today that is just the engine VPS IP the
/// user must add to their Binance API-key IP whitelist.  The engine
/// serves this independently of KMS/Firestore, so the IP stays
/// retrievable even while the connect flow itself is 500ing on a server
/// misconfiguration — the user can still copy the IP and prepare their
/// Binance key.
///
/// ``engineVpsIp == null`` means the operator hasn't set
/// ``ENGINE_VPS_PUBLIC_IP``; the page falls back to generic whitelist
/// wording rather than showing an error.
class BinanceConnectInfo {
  const BinanceConnectInfo({this.engineVpsIp});

  final String? engineVpsIp;

  factory BinanceConnectInfo.fromJson(Map<String, dynamic> j) =>
      BinanceConnectInfo(
        engineVpsIp: j['engine_vps_ip'] as String?,
      );
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
    this.allowedPaths = const <String>[],
    this.regimeOptions = const <String>[],
    required this.armed,
    this.userTier,
    this.tierAllowsAuto,
    this.autoPaused,
    this.pathPreference,
    this.regimePreference,
    this.preferencesBlockAll = false,
  });

  final bool autoTradeGloballyEnabled;
  final bool autoTradeUserDisabled;
  final bool binanceKeyConnected;
  final String? userMode; // 'live' | 'paper' | 'off' | null

  /// Effective subscription tier the dispatcher will apply (expiry-aware:
  /// a lapsed paid window reads as 'free').  Null = older engine without
  /// the 2026-07-17 truth fields → tier row hidden.
  final String? userTier;

  /// Whether the tier gate lets hands-off auto-execution run for this
  /// user.  Null = older engine (unknown, row hidden) — never default a
  /// tri-state to a bool, "unknown" must stay representable.
  final bool? tierAllowsAuto;

  /// Server-side dispatcher pause (paused_reason set after consecutive
  /// -2019 rejections).  Null = older engine.
  final bool? autoPaused;

  /// LIVE eligibility filters.  Null = no preference (all eligible);
  /// EMPTY list = explicit block-all — the distinction is semantic, so
  /// these never collapse null into const [].
  final List<String>? pathPreference;
  final List<String>? regimePreference;

  /// True when a preference set is the explicit empty set — guaranteed
  /// zero orders, rendered as a failing gate row.
  final bool preferencesBlockAll;

  /// Engine-wide allowlist (the security cap).  Symbol picker shows
  /// this as the universe the user can choose from.
  final List<String> allowedSymbols;

  /// Intersection of engine-wide cap and user's symbol_preference.
  /// When the user has set no preference, equals ``allowedSymbols``.
  /// Drives the Live-tab footnote so it shows what will actually
  /// trade for this user (not just the engine cap).
  final List<String> effectiveAllowedSymbols;

  /// Canonical list of selectable evaluator paths (setup classes) the
  /// engine actually emits — source of truth for the Path picker so the
  /// app never drifts from the engine's SetupClass enum.  Empty when an
  /// older engine doesn't yet send the field.
  final List<String> allowedPaths;

  /// Regime buckets offered by the Regime picker (TRENDING / RANGING /
  /// CHOPPY).  Server maps these onto backend regime labels.
  final List<String> regimeOptions;

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
    // Preference lists: null ≠ [] (no-preference vs block-all), so only
    // parse when the key is present AND a list — same guard style as
    // effective_allowed_symbols above.
    List<String>? parseNullableList(String key) {
      final raw = j[key];
      return raw is List
          ? raw.map((s) => s.toString()).toList(growable: false)
          : null;
    }

    final tier = j['user_tier'];
    return AutoTradeRuntimeStatus(
      autoTradeGloballyEnabled:
          j['auto_trade_globally_enabled'] as bool? ?? false,
      autoTradeUserDisabled: j['auto_trade_user_disabled'] as bool? ?? false,
      binanceKeyConnected: j['binance_key_connected'] as bool? ?? false,
      userMode: mode is String && mode.isNotEmpty ? mode : null,
      allowedSymbols: allowed,
      effectiveAllowedSymbols: effective,
      allowedPaths: parseList(j['allowed_paths']),
      regimeOptions: parseList(j['regime_options']),
      armed: j['armed'] as bool? ?? false,
      userTier: tier is String && tier.isNotEmpty ? tier : null,
      tierAllowsAuto: j['tier_allows_auto'] as bool?,
      autoPaused: j['auto_paused'] as bool?,
      pathPreference: parseNullableList('path_preference'),
      regimePreference: parseNullableList('regime_preference'),
      preferencesBlockAll: j['preferences_block_all'] as bool? ?? false,
    );
  }
}


/// Outcome of ``POST /api/auto-trade/take`` — the server-side manual take
/// (owner-approved 2026-07-17).  ``outcome`` is one of:
///
/// * ``placed``   — the engine placed the entry; fill fields populated.
/// * ``rejected`` — a business rejection (tier, dup position, Binance
///   error…); the reject fields mirror [DispatchEvent] so
///   [DispatchEventTranslation] can render the same plain-English copy.
/// * ``queued``   — the engine didn't answer inside the API's poll
///   window; the outcome lands in Recent Activity.
class TakeSignalResult {
  const TakeSignalResult({
    required this.outcome,
    this.signalId = '',
    this.symbol,
    this.direction,
    this.entryPrice,
    this.totalQty,
    this.rejectClass,
    this.rejectDetail,
    this.rejectBinanceCode,
    this.rejectBinanceMsg,
    this.detail,
  });

  final String outcome; // 'placed' | 'rejected' | 'skipped' | 'queued'
  final String signalId;
  final String? symbol;
  final String? direction;
  final double? entryPrice;
  final double? totalQty;
  final String? rejectClass;
  final String? rejectDetail;
  final int? rejectBinanceCode;
  final String? rejectBinanceMsg;

  /// Server-provided guidance for the 'queued' outcome.
  final String? detail;

  bool get placed => outcome == 'placed';
  bool get queued => outcome == 'queued';

  factory TakeSignalResult.fromJson(Map<String, dynamic> j) =>
      TakeSignalResult(
        outcome: j['outcome'] as String? ?? 'rejected',
        signalId: j['signal_id'] as String? ?? '',
        symbol: j['symbol'] as String?,
        direction: j['direction'] as String?,
        entryPrice: (j['entry_price'] as num?)?.toDouble(),
        totalQty: (j['total_qty'] as num?)?.toDouble(),
        rejectClass: j['reject_class'] as String?,
        rejectDetail: j['reject_detail'] as String?,
        rejectBinanceCode: (j['reject_binance_code'] as num?)?.toInt(),
        rejectBinanceMsg: j['reject_binance_msg'] as String?,
        detail: j['detail'] as String?,
      );
}


/// A trade the user built on the chart, sent to
/// ``POST /api/manual-trade/take`` (manual trade builder, 2026-07-18).
///
/// Server-side execution on the user's connected key — MARKET entry or a
/// resting LIMIT at [entryPrice], with OPTIONAL [slPrice] / [tpPrices] (the
/// engine stamps ``protection_mode="user_owned"``; SL is not compulsory for a
/// manual take). This is the server-side replacement for the client-side
/// (device-key, IP-locked) alert take that is unusable on mobile networks.
class ManualTradeRequest {
  const ManualTradeRequest({
    required this.refId,
    required this.symbol,
    required this.direction,
    required this.entryType,
    required this.entryPrice,
    this.slPrice = 0.0,
    this.tpPrices = const [],
    this.validForMinutes = 0,
  });

  final String refId; // alert_id | signal_id — idempotency key
  final String symbol;
  final String direction; // 'LONG' | 'SHORT'
  final String entryType; // 'market' | 'limit'
  final double entryPrice; // LIMIT price (limit) / sizing anchor (market)
  final double slPrice; // 0 = no stop (entry-only)
  final List<double> tpPrices; // 0..3 legs; empty = no take-profit
  final int validForMinutes; // LIMIT-entry TTL; 0 = GTC

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ref_id': refId,
        'symbol': symbol,
        'direction': direction,
        'entry_type': entryType,
        'entry_price': entryPrice,
        'sl_price': slPrice,
        'tp_prices': tpPrices,
        'valid_for_minutes': validForMinutes,
      };
}


/// Outcome of ``POST /api/manual-trade/take``. Mirrors [TakeSignalResult] with
/// the manual-builder extras: [refId], [resting] (LIMIT still on the book),
/// and [entryType]. Business rejections come back as ``outcome == 'rejected'``
/// with the same reject fields [DispatchEventTranslation] renders; only
/// transport failures throw.
class ManualTradeResult {
  const ManualTradeResult({
    required this.outcome,
    this.refId = '',
    this.symbol,
    this.direction,
    this.entryPrice,
    this.totalQty,
    this.entryType,
    this.resting = false,
    this.rejectClass,
    this.rejectDetail,
    this.rejectBinanceCode,
    this.rejectBinanceMsg,
    this.detail,
  });

  final String outcome; // 'placed' | 'rejected' | 'queued'
  final String refId;
  final String? symbol;
  final String? direction;
  final double? entryPrice;
  final double? totalQty;
  final String? entryType; // 'market' | 'limit'
  final bool resting; // true → LIMIT resting until filled/expired
  final String? rejectClass;
  final String? rejectDetail;
  final int? rejectBinanceCode;
  final String? rejectBinanceMsg;
  final String? detail;

  bool get placed => outcome == 'placed';
  bool get queued => outcome == 'queued';

  factory ManualTradeResult.fromJson(Map<String, dynamic> j) =>
      ManualTradeResult(
        outcome: j['outcome'] as String? ?? 'rejected',
        refId: j['ref_id'] as String? ?? '',
        symbol: j['symbol'] as String?,
        direction: j['direction'] as String?,
        entryPrice: (j['entry_price'] as num?)?.toDouble(),
        totalQty: (j['total_qty'] as num?)?.toDouble(),
        entryType: j['entry_type'] as String?,
        resting: j['resting'] as bool? ?? false,
        rejectClass: j['reject_class'] as String?,
        rejectDetail: j['reject_detail'] as String?,
        rejectBinanceCode: (j['reject_binance_code'] as num?)?.toInt(),
        rejectBinanceMsg: j['reject_binance_msg'] as String?,
        detail: j['detail'] as String?,
      );
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
    this.skipReason,
    this.source,
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

  /// Which of the user's own per-signal preferences declined this signal
  /// (``path_preference`` / ``regime_preference``).  Null unless
  /// [outcome] is ``skipped``.
  final String? skipReason;

  /// How the order originated: 'auto' (hands-off dispatch) or
  /// 'manual_take' (one-tap take).  Null on engines that pre-date the
  /// field (2026-07-17).
  final String? source;

  bool get isPlaced => outcome == 'placed';
  bool get isRejected => outcome == 'rejected';

  /// A signal the user's OWN per-signal preference declined, before the
  /// order path.  Only ``path_preference`` and ``regime_preference``
  /// persist a row (engine ``dispatch_log.record_skipped``); the
  /// account-level gates are answered by the runtime-status card
  /// instead of one write per signal per user.
  bool get isSkipped => outcome == 'skipped';

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
        skipReason: j['skip_reason'] as String?,
        source: j['source'] as String?,
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

  /// [outcome] is what the placement BECAME on Binance, when known.
  ///
  /// Until 2026-08-31 this returned the fixed sentence *"Position is open
  /// — Lumin manages it from here."* for every placed event, forever.  A
  /// [DispatchEvent] records a placement ATTEMPT: it carries no fill, no
  /// PnL and no close state, so the sentence was a static string on a
  /// record that could not know it.  Four such rows sat directly beneath
  /// "YOUR OPEN POSITIONS 0" in the owner's screenshot — the card above
  /// was engine truth, the rows below were copy, and each was internally
  /// right while the page contradicted itself.
  ///
  /// With no [outcome] the row now states only what the event itself
  /// witnessed: Binance accepted the order.  It claims nothing about the
  /// position, because it cannot.
  static DispatchEventTranslation forEvent(
    DispatchEvent e, {
    SignalOutcome? outcome,
  }) {
    if (e.isPlaced) {
      if (outcome != null && outcome.isClosed) {
        final pnl = outcome.realizedPnlUsd;
        final reason = outcome.closeReason;
        final bits = <String>[
          if (reason != null && reason.isNotEmpty) 'exit $reason',
          if (pnl != null)
            'realised ${pnl >= 0 ? '+' : '-'}\$${pnl.abs().toStringAsFixed(2)}',
        ];
        return DispatchEventTranslation(
          headline: 'Closed on Binance',
          action: bits.isEmpty
              ? 'The position has closed.'
              : bits.join(' · '),
          severity: DispatchEventSeverity.success,
        );
      }
      if (outcome != null && outcome.isOpen) {
        final filled = outcome.entryPriceFilled;
        return DispatchEventTranslation(
          headline: 'Placed on Binance',
          action: filled != null && filled > 0
              ? 'Open at $filled — Lumin manages it from here.'
              : 'Position is open — Lumin manages it from here.',
          severity: DispatchEventSeverity.success,
        );
      }
      return DispatchEventTranslation(
        headline: 'Placed on Binance',
        action: 'Binance accepted the order.',
        severity: DispatchEventSeverity.success,
      );
    }
    if (e.outcome == 'skipped') {
      // The user's own path/regime filter declined this signal.  Nothing
      // failed, so it must not be coloured or worded as an error — it is
      // one of exactly two gates that can stop ONE signal on an
      // otherwise-working account, which is what makes it worth a row.
      return DispatchEventTranslation(
        headline: 'Not auto-traded',
        action: e.rejectDetail ??
            'Your own auto-trade filter excluded this signal.',
        severity: DispatchEventSeverity.transient,
      );
    }
    return forReject(
      rejectClass: e.rejectClass,
      rejectDetail: e.rejectDetail,
      binanceCode: e.rejectBinanceCode,
      binanceMsg: e.rejectBinanceMsg,
      symbol: e.symbol,
    );
  }

  /// Core rejection→copy mapping, shared by the Recent Activity rows
  /// ([forEvent]) and the take sheet (`take_error_mapper.dart`) so the
  /// same failure never reads differently on two surfaces.
  static DispatchEventTranslation forReject({
    String? rejectClass,
    String? rejectDetail,
    int? binanceCode,
    String? binanceMsg,
    String symbol = '',
  }) {
    // Binance-side rejections are switched on by code (stable
    // numeric contract from Binance Futures docs).
    final code = binanceCode;
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
                'price moved too far from the entry. Lumin will retry on '
                'the next signal.',
            severity: DispatchEventSeverity.transient,
          );
        case -1111:
        case -4014:
          return DispatchEventTranslation(
            headline: 'Order precision rejected',
            action:
                'The order size was rounded incorrectly for this symbol. '
                'This is a bug on our side — please report it if it keeps '
                'happening.',
            severity: DispatchEventSeverity.system,
          );
        case -2021:
          return DispatchEventTranslation(
            headline: 'Stop order would trigger immediately',
            action:
                'The SL or TP was already past the current mark price when '
                'placed. Lumin will retry on the next signal.',
            severity: DispatchEventSeverity.transient,
          );
        case -4411:
          // "Please sign TradFi-Perps agreement contract fapi." — Binance
          // rejects this because the SYMBOL is a tokenised-stock / TradFi
          // perpetual (e.g. WDCUSDT = Western Digital), a separate product
          // from crypto Futures with its own agreement.  It is NOT an
          // account-wide problem: crypto pairs trade fine on the same
          // account.  The old copy here wrongly told users their account
          // hadn't accepted the Futures agreement, which alarmed a paid
          // subscriber whose account traded crypto perps daily (2026-07-18).
          // The engine now filters these symbols out of the universe
          // (pair_manager + symbol_filters, contractType TRADIFI_PERPETUAL),
          // so this path is a defensive backstop for a manually-taken
          // stock symbol or a boot-race window — hence transient, not a
          // user-action the subscriber needs to chase.
          final sym = symbol.isNotEmpty ? symbol : 'This signal';
          return DispatchEventTranslation(
            headline: 'Not a crypto pair',
            action:
                '$sym is a Binance stock (TradFi) perpetual, which needs a '
                'separate Binance agreement and isn\'t a crypto pair. Your '
                'account is fine — Lumin auto-trades crypto only and filters '
                'these out.',
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
          final msg = (binanceMsg ?? '').trim();
          return DispatchEventTranslation(
            headline: 'Binance rejected the order ($code)',
            action: msg.isNotEmpty
                ? msg
                : 'Binance returned a rejection without a message. '
                    'Lumin will retry on the next signal.',
            severity: DispatchEventSeverity.transient,
          );
      }
    }
    // Engine-side rejections — switch on the typed exception class.
    switch (rejectClass) {
      case 'SymbolNotAllowed':
        // Engine-wide tripwire: the symbol is not in the engine's
        // tradeable universe.  Post the 2026-07-18 TradFi-Perps
        // exclusion this fires when a signal outlives a universe
        // update (e.g. a stock perp removed while its signal was
        // still open — the owner saw the raw engine string
        // "symbol 'WDCUSDT' is not on the tripwire allowlist
        // (allowlist size: 76)" leak straight to the take sheet).
        // Not the user's fault and nothing for them to fix.
        return DispatchEventTranslation(
          headline: 'Pair not tradeable through Lumin',
          action:
              '${symbol.isEmpty ? 'This pair' : symbol} isn\'t on Lumin\'s '
              'tradeable pair list right now — usually because the list '
              'was updated after this signal appeared (stock perpetuals '
              'and delisted pairs are removed automatically). No action '
              'needed.',
          severity: DispatchEventSeverity.transient,
        );
      case 'SymbolNotInUserPreference':
        return DispatchEventTranslation(
          headline: 'Symbol not in your picker',
          action:
              '${symbol.isEmpty ? 'This symbol' : symbol} is not enabled in '
              'your symbol preference. Enable it on the Symbol Preference '
              'page to receive these signals.',
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
              'Too many orders in a short window — a built-in safety '
              'limit. Lumin will resume on the next signal.',
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
      case 'GlobalKillSwitchEngaged':
      case 'GlobalKillSwitchActiveError':
        return DispatchEventTranslation(
          headline: 'Trading temporarily paused',
          action:
              'Trading is paused for everyone right now as a safety '
              'measure. No action needed — it resumes automatically.',
          severity: DispatchEventSeverity.system,
        );
      case 'UserAutoDisabled':
        // The engine's raw detail embeds the Firebase UID ("user <uid>
        // is auto-disabled") — never surface it.
        return DispatchEventTranslation(
          headline: 'Trading is switched off on your account',
          action:
              'A safety check paused trading on your account after '
              'repeated order failures. Fix the underlying issue shown in '
              'your recent activity, then email support to re-enable.',
          severity: DispatchEventSeverity.userAction,
        );
      case 'SignalClosed':
        return DispatchEventTranslation(
          headline: 'Signal already closed',
          action:
              'This signal finished before the order could be placed — '
              'entering now would be a trade without its setup.',
          severity: DispatchEventSeverity.transient,
        );
      case 'TakeRequestStale':
        return DispatchEventTranslation(
          headline: 'Request took too long',
          action:
              'Your take arrived late and was refused for your safety — '
              'a delayed market order could fill far from the signal '
              'price. Try again.',
          severity: DispatchEventSeverity.transient,
        );
      case 'OrderPlacementUnreachable':
      case 'OrderPlacementKeyError':
      case 'OrderPlacementError':
        return DispatchEventTranslation(
          headline: 'Order could not be placed',
          action:
              'Binance could not be reached with your key just now. '
              'Lumin will retry on the next signal; if this keeps '
              'happening, re-connect your key in Settings.',
          severity: DispatchEventSeverity.transient,
        );
      case 'NotGloballyEnabledError':
        return DispatchEventTranslation(
          headline: 'Auto-trade not yet enabled',
          action:
              'Server-side execution is not switched on right now. '
              'No action needed on your side.',
          severity: DispatchEventSeverity.system,
        );
      case 'NotionalTooSmall':
        return DispatchEventTranslation(
          headline: 'Position size too small',
          action:
              'Your position size is too small to open '
              '${symbol.isEmpty ? 'this' : 'a $symbol'} order at the '
              'current price after lot-size rounding. Go to Settings → '
              'Auto-trade and increase your position size to at least '
              '\$10.',
          severity: DispatchEventSeverity.userAction,
        );
      case 'OrderRejectedByBinance':
        // Fell through code-switch (Binance returned an error
        // without a parseable numeric code).  Surface the Binance
        // message only — never the raw engine detail, which carries
        // internal phase/code framing.
        final msg = (binanceMsg ?? '').trim();
        return DispatchEventTranslation(
          headline: 'Binance rejected the order',
          action: msg.isNotEmpty
              ? msg
              : 'Binance did not accept the order. Lumin will retry on '
                  'the next signal.',
          severity: DispatchEventSeverity.transient,
        );
      default:
        // Unknown class — never leak the raw exception name as the
        // headline (pre-2026-07-17 this rendered e.g.
        // "UserAutoDisabled" verbatim).  Sanitized detail only.
        return DispatchEventTranslation(
          headline: 'Trade not placed',
          action: sanitizeEngineDetail(rejectDetail) ??
              'Something unexpected stopped this trade. Lumin will retry '
                  'on the next signal.',
          severity: DispatchEventSeverity.system,
        );
    }
  }

  /// Strip engine internals from a free-text `detail` string before it
  /// can reach a widget: Firebase UIDs, "user <uid> is auto-disabled"
  /// framing, kill-switch/circuit-breaker vocabulary.  Returns null
  /// when nothing safely presentable remains so the caller falls back
  /// to its own generic copy.
  static String? sanitizeEngineDetail(String? detail) {
    var s = (detail ?? '').trim();
    if (s.isEmpty) return null;
    // Firebase UIDs are 20-40 char base62 tokens; the engine embeds
    // them as "user <uid> is auto-disabled" / "user <uid> auto-disabled
    // by circuit breaker (...)".
    s = s.replaceAll(
      RegExp(r'user\s+[A-Za-z0-9]{16,40}\s+(is\s+)?auto-disabled'
          r'(\s+by\s+circuit\s+breaker)?(\s*\([^)]*\))?'),
      'trading is switched off on your account',
    );
    // Any residual bare UID-shaped token.
    s = s.replaceAll(RegExp(r'\b[A-Za-z0-9]{24,40}\b'), '');
    // If the residue still reads like engine internals, drop it.
    final internal = RegExp(
      r'kill switch|circuit breaker|globally disabled|Firestore|'
      r'phase=|code=[A-Z_]+|Traceback|Exception|'
      // Tripwire vocabulary — "symbol 'X' is not on the tripwire
      // allowlist (allowlist size: N)" reached a subscriber verbatim
      // on 2026-07-18.  The SymbolNotAllowed case above owns the
      // consumer copy; anything else mentioning these is engine-speak.
      r'tripwire|allowlist',
      caseSensitive: false,
    );
    if (internal.hasMatch(s)) return null;
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (s.length < 4) return null;
    return s;
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

/// Result of the self-service breaker re-enable
/// (``POST /api/auto-trade/resume-disabled-mine``, 2026-07-18).
///
/// The per-user safety breaker used to be recoverable only through
/// support (an owner-run admin endpoint); the paused card now offers a
/// "Re-enable auto-trade" button backed by this call.  ``message``
/// carries the server's human-readable refusal when the once-per-
/// cooldown rate limit blocks the tap (HTTP 429) — rendered verbatim,
/// same convention as the other engine-authored user copy.
class SelfReenableResult {
  const SelfReenableResult({
    required this.ok,
    this.alreadyEnabled = false,
    this.message,
  });

  final bool ok;

  /// True when the account wasn't disabled in the first place — the UI
  /// just refreshes status instead of celebrating.
  final bool alreadyEnabled;

  /// User-facing refusal copy (cooldown), null on success.
  final String? message;
}


/// One row from ``GET /api/auto-trade/signal-outcomes`` — what happened
/// to a signal **on this user's own Binance account**.
///
/// Why this exists (owner, 2026-08-31: *"why don't we show actually same
/// like signal it's outcome, actually what traded in binance ... with
/// that user can understand what actually engine produced and what's
/// traded in binance"*).
///
/// The two halves already existed and had never been joined.  The
/// Signals tab renders the ENGINE's object — entry / SL / TP and a live
/// mark — and says so in its own subtitle.  The Trade tab renders the
/// USER's object, and its only per-signal record was [DispatchEvent],
/// which is a record of a placement ATTEMPT: it carries no fill price,
/// no PnL and no close state.  That is why a placed row asserts
/// "Position is open" in the present tense forever, and why four such
/// rows could sit directly beneath "YOUR OPEN POSITIONS 0" — the card
/// above was engine truth and the rows below were a static string.
///
/// This class is the join, keyed by [signalId], so a signal card can say
/// what *your* account did with it.
class SignalOutcome {
  const SignalOutcome({
    required this.signalId,
    required this.symbol,
    required this.direction,
    required this.status,
    this.state,
    this.entryPriceFilled,
    this.filledQty,
    this.realizedPnlUsd,
    this.closeReason,
    this.openedAt,
    this.closedAt,
    this.notTradedClass,
    this.notTradedReason,
    this.notTradedDetail,
    this.binanceCode,
    this.source,
  });

  final String signalId;
  final String symbol;
  final String direction;

  /// 'open' | 'closed' | 'not_traded'.  Absence of a [SignalOutcome]
  /// for a signal is a FOURTH state and must never be rendered as
  /// 'not_traded' — it means the engine has no record for this account
  /// inside the windows the response names.
  final String status;

  /// The FSM state behind [status] (``OPEN``, ``CLOSED``, …).  Null when
  /// no position exists.
  final String? state;

  /// What Binance actually filled at — not what the signal asked for.
  /// The gap between this and the signal's `entry` is the whole reason
  /// this endpoint exists.
  final double? entryPriceFilled;
  final double? filledQty;
  final double? realizedPnlUsd;

  /// 'TP1' | 'TP2' | 'TP3' | 'SL' | 'MANUAL' | … — engine truth about how
  /// the position ended.
  final String? closeReason;

  final DateTime? openedAt;
  final DateTime? closedAt;

  /// 'rejected' (something refused the order — the user has something to
  /// fix) or 'preference' (the user's own path/regime filter declined it
  /// and nothing is wrong).  Two states with two different next moves;
  /// pooling them makes a working account read as a broken one.
  final String? notTradedClass;
  final String? notTradedReason;
  final String? notTradedDetail;
  final int? binanceCode;

  /// 'auto' | 'manual_take'.
  final String? source;

  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get isNotTraded => status == 'not_traded';

  /// True when the user's OWN preference declined the signal — nothing
  /// failed, so this must not be coloured or worded as an error.
  bool get declinedByPreference => notTradedClass == 'preference';

  factory SignalOutcome.fromJson(Map<String, dynamic> j) => SignalOutcome(
        signalId: j['signal_id'] as String? ?? '',
        symbol: j['symbol'] as String? ?? '',
        direction: j['direction'] as String? ?? '',
        status: j['status'] as String? ?? '',
        state: j['state'] as String?,
        entryPriceFilled: (j['entry_price_filled'] as num?)?.toDouble(),
        filledQty: (j['filled_qty'] as num?)?.toDouble(),
        realizedPnlUsd: (j['realized_pnl_usd'] as num?)?.toDouble(),
        closeReason: j['close_reason'] as String?,
        openedAt: DateTime.tryParse(j['opened_at'] as String? ?? ''),
        closedAt: DateTime.tryParse(j['closed_at'] as String? ?? ''),
        notTradedClass: j['not_traded_class'] as String?,
        notTradedReason: j['not_traded_reason'] as String?,
        notTradedDetail: j['not_traded_detail'] as String?,
        binanceCode: (j['binance_code'] as num?)?.toInt(),
        source: j['source'] as String?,
      );
}


/// The response envelope for ``GET /api/auto-trade/signal-outcomes``.
///
/// The window counts are not decoration.  A signal with no [SignalOutcome]
/// has no record on this account *within these windows*, which is a
/// different fact from a signal the account declined — and only these
/// numbers let the UI tell the reader which one it is looking at.
class SignalOutcomes {
  const SignalOutcomes({
    required this.bySignalId,
    this.closedWindow = 0,
    this.closedTruncated = false,
    this.eventsWindow = 0,
    this.eventsTruncated = false,
  });

  const SignalOutcomes.empty()
      : bySignalId = const <String, SignalOutcome>{},
        closedWindow = 0,
        closedTruncated = false,
        eventsWindow = 0,
        eventsTruncated = false;

  final Map<String, SignalOutcome> bySignalId;
  final int closedWindow;
  final bool closedTruncated;
  final int eventsWindow;
  final bool eventsTruncated;

  /// True when either window was full, so an absent signal may simply be
  /// older than the read reached.
  bool get truncated => closedTruncated || eventsTruncated;

  SignalOutcome? operator [](String signalId) => bySignalId[signalId];

  factory SignalOutcomes.fromJson(Map<String, dynamic> j) {
    final raw = j['outcomes'];
    final map = <String, SignalOutcome>{};
    if (raw is List) {
      for (final row in raw) {
        if (row is Map<String, dynamic>) {
          final o = SignalOutcome.fromJson(row);
          if (o.signalId.isNotEmpty) map[o.signalId] = o;
        }
      }
    }
    return SignalOutcomes(
      bySignalId: map,
      closedWindow: (j['closed_window'] as num?)?.toInt() ?? 0,
      closedTruncated: j['closed_truncated'] as bool? ?? false,
      eventsWindow: (j['events_window'] as num?)?.toInt() ?? 0,
      eventsTruncated: j['events_truncated'] as bool? ?? false,
    );
  }
}

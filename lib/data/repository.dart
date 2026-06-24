/// Repository abstraction — the single seam between UI and data source.
///
/// Pages call ``LuminRepository`` methods.  The concrete implementation
/// (``MockRepository`` for offline/preview, ``HttpRepository`` for live
/// engine) is chosen at app startup based on user preference.  Adding a
/// new data source (websocket, on-device cache, …) means writing a new
/// implementation; no page has to change.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/tokens.dart';
import 'api_client.dart';
import 'mock_data.dart';
import 'server_side_execution_models.dart';
import 'swr_cache.dart';

class AutoModeStatus {
  const AutoModeStatus({
    required this.mode,
    required this.openPositions,
    required this.dailyPnlUsd,
    required this.dailyLossPct,
    required this.dailyKillTripped,
    required this.manualPaused,
    required this.currentEquityUsd,
    this.simulatedPnlUsd,
    this.weeklyPnlUsd = 0.0,
    this.monthlyPnlUsd = 0.0,
  });

  final String mode;
  final int openPositions;
  final double dailyPnlUsd;
  final double dailyLossPct;
  final bool dailyKillTripped;
  final bool manualPaused;
  final double currentEquityUsd;
  final double? simulatedPnlUsd;
  /// Realised PnL over the last 7 UTC days, sourced from the engine's
  /// persistent daily ledger (engine PR #338).  Default 0.0 on clean
  /// install / pre-#338 backends so the UI can render zeros without
  /// conditional null handling.
  final double weeklyPnlUsd;
  /// Realised PnL over the last 30 UTC days (rolling).
  final double monthlyPnlUsd;

  factory AutoModeStatus.fromJson(Map<String, dynamic> j) => AutoModeStatus(
        mode: j['mode'] as String,
        openPositions: (j['open_positions'] as num?)?.toInt() ?? 0,
        dailyPnlUsd: (j['daily_pnl_usd'] as num?)?.toDouble() ?? 0.0,
        dailyLossPct: (j['daily_loss_pct'] as num?)?.toDouble() ?? 0.0,
        dailyKillTripped: j['daily_kill_tripped'] as bool? ?? false,
        manualPaused: j['manual_paused'] as bool? ?? false,
        currentEquityUsd:
            (j['current_equity_usd'] as num?)?.toDouble() ?? 0.0,
        simulatedPnlUsd: (j['simulated_pnl_usd'] as num?)?.toDouble(),
        weeklyPnlUsd: (j['weekly_pnl_usd'] as num?)?.toDouble() ?? 0.0,
        monthlyPnlUsd: (j['monthly_pnl_usd'] as num?)?.toDouble() ?? 0.0,
      );
}

/// One day's bucket from the persistent PnL ledger.  Used by the chart
/// widget on Pulse.
class PnlPoint {
  const PnlPoint({required this.date, required this.pnlUsd});
  final String date;  // ISO YYYY-MM-DD
  final double pnlUsd;
}

class PnlHistory {
  const PnlHistory({
    required this.mode,
    required this.days,
    required this.items,
    required this.weeklyPnlUsd,
    required this.monthlyPnlUsd,
  });
  final String mode;
  final int days;
  final List<PnlPoint> items;
  final double weeklyPnlUsd;
  final double monthlyPnlUsd;
}

class AgentStat {
  const AgentStat({
    required this.evaluator,
    required this.setupClass,
    required this.displayName,
    required this.enabled,
    required this.attempts,
    required this.generated,
    required this.noSignal,
    this.closedToday = 0,
    this.tpHits = 0,
    this.slHits = 0,
    this.invalidated = 0,
    this.lastSignalAgeMinutes,
  });
  final String evaluator;
  final String setupClass;
  final String displayName;
  final bool enabled;
  // Telemetry counters (reset per scan-cycle window):
  final int attempts;
  final int generated;
  final int noSignal;
  // Lifecycle counters (rolling 24h):
  final int closedToday;
  final int tpHits;
  final int slHits;
  final int invalidated;
  // Minutes since this agent's most recent emission, or null if it has
  // never fired since the engine's history window started.
  final int? lastSignalAgeMinutes;

  factory AgentStat.fromJson(Map<String, dynamic> j) => AgentStat(
        evaluator: j['evaluator'] as String? ?? '',
        setupClass: j['setup_class'] as String? ?? '',
        displayName: j['display_name'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        generated: (j['generated'] as num?)?.toInt() ?? 0,
        noSignal: (j['no_signal'] as num?)?.toInt() ?? 0,
        closedToday: (j['closed_today'] as num?)?.toInt() ?? 0,
        tpHits: (j['tp_hits'] as num?)?.toInt() ?? 0,
        slHits: (j['sl_hits'] as num?)?.toInt() ?? 0,
        invalidated: (j['invalidated'] as num?)?.toInt() ?? 0,
        lastSignalAgeMinutes: (j['last_signal_age_minutes'] as num?)?.toInt(),
      );
}

/// Pre-TP grab settings — backend ``GET / PUT /api/settings/pretp``.
///
/// All fields nullable on PUT — the backend merges a partial payload into
/// the stored state, so a one-toggle change doesn't wipe the others.  GET
/// returns the engine's resolved view (user overrides where set, config
/// defaults otherwise) so the page renders live state without a separate
/// "defaults" call.
class PretpSettings {
  const PretpSettings({
    this.enabled,
    this.regimeAllowlist,
    this.setupAllowlist,
    this.thresholdPct,
    this.atrMultiplier,
    this.feeFloorPct,
    this.minAgeSec,
    this.maxAgeSec,
    this.grabFraction,
    this.protectManualEntries,
    this.usingDefaults,
  });

  final bool? enabled;
  final List<String>? regimeAllowlist;
  final List<String>? setupAllowlist;
  final double? thresholdPct;
  final double? atrMultiplier;
  final double? feeFloorPct;
  final int? minAgeSec;
  final int? maxAgeSec;

  /// Fraction of the position to close at market when the pre-TP threshold
  /// hits.  Backend enforces a 30%-100% range (OWNER_BRIEF B17 — hard 30%
  /// floor prevents the pre-2026-05-17 SL-to-BE-only collapse; 100% ceiling
  /// fully banks the partial).  Engine default 50%.  Null means "use the
  /// engine default" for this field.
  final double? grabFraction;

  /// OWNER_BRIEF B17 (2026-05-17) — when true, the AutoTradeWatcher
  /// keeps polling for pre-TP partial closes on manually-taken entries
  /// even when auto-trade ``mode == 'off'``.  Default true extends
  /// capital-preservation doctrine to manual operators (the most
  /// engaged subscriber cohort).  False respects "off means off" for
  /// users who want pure manual control.  Null on responses where the
  /// backend hasn't seen a user override (engine default true).
  final bool? protectManualEntries;

  /// Only present on per-user responses (``/api/settings/user/pretp``).
  /// True when the user has no override row — every field above is the
  /// engine default.  False once at least one field is user-set.  Null
  /// on engine-wide responses where the concept doesn't apply.
  final bool? usingDefaults;

  factory PretpSettings.fromJson(Map<String, dynamic> j) => PretpSettings(
        enabled: j['enabled'] as bool?,
        regimeAllowlist: (j['regime_allowlist'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        setupAllowlist: (j['setup_allowlist'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        thresholdPct: (j['threshold_pct'] as num?)?.toDouble(),
        atrMultiplier: (j['atr_multiplier'] as num?)?.toDouble(),
        feeFloorPct: (j['fee_floor_pct'] as num?)?.toDouble(),
        minAgeSec: (j['min_age_sec'] as num?)?.toInt(),
        maxAgeSec: (j['max_age_sec'] as num?)?.toInt(),
        grabFraction: (j['grab_fraction'] as num?)?.toDouble(),
        protectManualEntries: j['protect_manual_entries'] as bool?,
        usingDefaults: j['using_defaults'] as bool?,
      );

  /// Serialise only the non-null fields so a partial PUT doesn't wipe
  /// settings the user didn't touch.
  Map<String, dynamic> toJsonPartial() {
    final out = <String, dynamic>{};
    if (enabled != null) out['enabled'] = enabled;
    if (regimeAllowlist != null) out['regime_allowlist'] = regimeAllowlist;
    if (setupAllowlist != null) out['setup_allowlist'] = setupAllowlist;
    if (thresholdPct != null) out['threshold_pct'] = thresholdPct;
    if (atrMultiplier != null) out['atr_multiplier'] = atrMultiplier;
    if (feeFloorPct != null) out['fee_floor_pct'] = feeFloorPct;
    if (minAgeSec != null) out['min_age_sec'] = minAgeSec;
    if (maxAgeSec != null) out['max_age_sec'] = maxAgeSec;
    if (grabFraction != null) out['grab_fraction'] = grabFraction;
    if (protectManualEntries != null) {
      out['protect_manual_entries'] = protectManualEntries;
    }
    return out;
  }
}

/// Invalidation settings — backend ``GET / PUT /api/settings/user/invalidation``.
///
/// OWNER_BRIEF B17 (2026-05-17 doctrine): per-user invalidation aggressiveness.
/// Three preset modes (``loose`` / ``standard`` / ``tight``) cover the common
/// cases.  Advanced-section overrides are exposed for users who want fine
/// control without committing to a preset; NULL means "use the preset's
/// value for this knob".
///
/// Engine-side TradeMonitor is owner-only auto-trade today and uses the
/// engine default (``INVALIDATION_MODE_DEFAULT``).  Per-user values stored
/// here are consumed by the app-side OrderExecutor in Phase 4 when users
/// have their own Binance keys.
class InvalidationSettings {
  const InvalidationSettings({
    this.mode,
    this.minAgeSec,
    this.momentumThresholdMult,
    this.emaCrossoverEnabled,
    this.regimeShiftEnabled,
    this.trailingKillEnabled,
    this.trailingMfeRThreshold,
    this.trailingRetracePct,
    this.usingDefaults,
  });

  /// Preset aggressiveness — ``loose`` / ``standard`` / ``tight``.
  /// * ``loose``    — only the SL itself + max-hold can close.
  /// * ``standard`` — engine baseline + MFE protection (default).
  /// * ``tight``    — standard + ATR-trailing kill at MFE >= 0.3R.
  final String? mode;

  /// Earliest signal age (seconds) at which invalidation may fire.
  final int? minAgeSec;

  /// Multiplier applied to the engine's ATR-adaptive momentum threshold.
  /// ``<1.0`` = more sensitive (kill earlier); ``>1.0`` = less sensitive.
  final double? momentumThresholdMult;

  /// Whether 5m EMA9/EMA21 cross-against-thesis triggers a kill.
  final bool? emaCrossoverEnabled;

  /// Whether a regime flip opposing direction triggers a kill.
  final bool? regimeShiftEnabled;

  /// Whether the ATR-trailing kill is active (tight-mode signature).
  final bool? trailingKillEnabled;

  /// MFE threshold (as a multiple of SL distance) above which the
  /// ATR-trailing kill becomes armed.  Default 0.3R per B17.
  final double? trailingMfeRThreshold;

  /// Retracement fraction of the MFE peak at which the trailing kill
  /// fires.  Default 0.50 (50% retrace) per B17.  Range [0.0, 1.0].
  final double? trailingRetracePct;

  /// Only present on per-user responses.  True when the user has no
  /// override row — every field above is the engine default.
  final bool? usingDefaults;

  factory InvalidationSettings.fromJson(Map<String, dynamic> j) =>
      InvalidationSettings(
        mode: j['mode'] as String?,
        minAgeSec: (j['min_age_sec'] as num?)?.toInt(),
        momentumThresholdMult:
            (j['momentum_threshold_mult'] as num?)?.toDouble(),
        emaCrossoverEnabled: j['ema_crossover_enabled'] as bool?,
        regimeShiftEnabled: j['regime_shift_enabled'] as bool?,
        trailingKillEnabled: j['trailing_kill_enabled'] as bool?,
        trailingMfeRThreshold:
            (j['trailing_mfe_r_threshold'] as num?)?.toDouble(),
        trailingRetracePct: (j['trailing_retrace_pct'] as num?)?.toDouble(),
        usingDefaults: j['using_defaults'] as bool?,
      );

  /// Serialise only the non-null fields so a partial PUT doesn't wipe
  /// settings the user didn't touch.
  Map<String, dynamic> toJsonPartial() {
    final out = <String, dynamic>{};
    if (mode != null) out['mode'] = mode;
    if (minAgeSec != null) out['min_age_sec'] = minAgeSec;
    if (momentumThresholdMult != null) {
      out['momentum_threshold_mult'] = momentumThresholdMult;
    }
    if (emaCrossoverEnabled != null) {
      out['ema_crossover_enabled'] = emaCrossoverEnabled;
    }
    if (regimeShiftEnabled != null) {
      out['regime_shift_enabled'] = regimeShiftEnabled;
    }
    if (trailingKillEnabled != null) {
      out['trailing_kill_enabled'] = trailingKillEnabled;
    }
    if (trailingMfeRThreshold != null) {
      out['trailing_mfe_r_threshold'] = trailingMfeRThreshold;
    }
    if (trailingRetracePct != null) {
      out['trailing_retrace_pct'] = trailingRetracePct;
    }
    return out;
  }
}

/// Auto-trade settings — backend ``GET / PUT /api/settings/auto-trade``.
///
/// Bundles execution mode + sizing knobs into one round-trip so the
/// settings page renders the whole live state without separate calls.
/// All fields nullable on PUT.  Server clamps ``leverageCap`` to 30
/// (B12 hard cap) and rejects out-of-range values with 422.
class AutoTradeSettings {
  const AutoTradeSettings({
    this.mode,
    this.positionSizePct,
    this.leverageCap,
    this.maxConcurrentPositions,
    this.symbolPreference,
    this.symbolPreferenceSet = false,
    this.pathPreference,
    this.pathPreferenceSet = false,
    this.regimePreference,
    this.regimePreferenceSet = false,
    this.paperSymbolPreference,
    this.paperSymbolPreferenceSet = false,
    this.paperPathPreference,
    this.paperPathPreferenceSet = false,
    this.paperRegimePreference,
    this.paperRegimePreferenceSet = false,
    this.notionalUsd,
    this.usingDefaults,
    this.pausedReason,
    this.pausedAt,
  });

  /// "off" | "paper" | "live" | "both".
  /// "both" = live orders fire AND paper simulation runs simultaneously.
  final String? mode;
  final double? positionSizePct;
  final double? leverageCap;
  final int? maxConcurrentPositions;

  /// Per-user symbol-preference picker (PR E 2026-05-19).
  ///
  /// Tri-state:
  /// * ``symbolPreferenceSet == false`` → field NOT included in PUT
  ///   payload (server keeps existing value).  Default for the
  ///   ordinary settings-page save that didn't touch the picker.
  /// * ``symbolPreferenceSet == true && symbolPreference == null`` →
  ///   sends ``symbol_preference: null`` → engine CLEARS the row →
  ///   user falls back to engine-wide allowlist (default-all UX).
  /// * ``symbolPreferenceSet == true && symbolPreference != null`` →
  ///   sends the list (may be empty == "explicit block all").
  final List<String>? symbolPreference;
  final bool symbolPreferenceSet;

  /// Per-user PATH picker (which evaluator paths / setup classes may
  /// auto-trade live for me — 2026-06-20).  Same tri-state contract as
  /// ``symbolPreference``: ``null`` = all paths, non-empty list = only
  /// these, empty list = block all.  The ``…Set`` flag controls whether
  /// the field is included in the PUT payload.
  final List<String>? pathPreference;
  final bool pathPreferenceSet;

  /// Per-user REGIME picker (which entry regimes may auto-trade live for
  /// me — 2026-06-20).  Values are the UI tokens TRENDING / RANGING /
  /// CHOPPY; the server normalises them onto backend regime labels.
  /// Tri-state identical to ``pathPreference``.
  final List<String>? regimePreference;
  final bool regimePreferenceSet;

  /// PAPER eligibility triple — the paper-simulation counterparts of
  /// ``symbolPreference`` / ``pathPreference`` / ``regimePreference``
  /// (engine columns ``paper_*_preference``, 2026-06-20).  Independent of
  /// the live triple, so a user can paper-test one symbol/path/regime set
  /// while live-trading another.  Same tri-state + ``…Set`` contract as
  /// the live fields.  Consumed by the per-user paper book fan-out on the
  /// engine when ``PAPER_PER_USER_BOOKS`` is enabled.
  final List<String>? paperSymbolPreference;
  final bool paperSymbolPreferenceSet;
  final List<String>? paperPathPreference;
  final bool paperPathPreferenceSet;
  final List<String>? paperRegimePreference;
  final bool paperRegimePreferenceSet;

  /// Per-user notional override (2026-05-20).  USD value the engine
  /// uses when sizing each live Binance order for THIS user.  ``null``
  /// → engine default ($500).  Clamped server-side to [$5, $2000].
  /// Smaller-wallet users (e.g. $20 Futures wallet) lower this so the
  /// engine doesn't fire $500-notional orders that Binance rejects
  /// with -2019 "Margin is insufficient".
  final double? notionalUsd;

  /// Only present on ``/api/settings/user/auto-trade`` responses.
  final bool? usingDefaults;

  /// Auto-pause state (engine PR #479, 2026-05-24). Set by the engine
  /// after N consecutive Binance ``-2019`` rejections; cleared by the
  /// user calling ``POST /api/auto-mode/resume-mine`` (typically via
  /// the "Resume" button on the Live tab's empty-wallet banner).
  /// Read-only — the app never PUTs these back.
  ///
  /// * ``pausedReason == null`` → user is dispatching normally.
  /// * ``pausedReason == 'insufficient_margin'`` → Futures wallet was
  ///   empty for 3+ signals; engine stopped dispatching to silence the
  ///   Recent Activity spam; user needs to top up + tap Resume.
  /// * ``pausedReason == <other>`` → reserved for future pause
  ///   reasons; render the generic banner with the raw reason as the
  ///   subtitle (forward-compatible default).
  final String? pausedReason;

  /// ISO-8601 UTC timestamp of the pause event. Useful for banner copy
  /// ("Paused 5m ago"). Null when ``pausedReason`` is null.
  final String? pausedAt;

  bool get isAutoPaused => pausedReason != null && pausedReason!.isNotEmpty;

  factory AutoTradeSettings.fromJson(Map<String, dynamic> j) {
    final symsRaw = j['symbol_preference'];
    final symsParsed = symsRaw is List
        ? symsRaw.map((s) => s.toString()).toList(growable: false)
        : null;
    final pathsRaw = j['path_preference'];
    final pathsParsed = pathsRaw is List
        ? pathsRaw.map((s) => s.toString()).toList(growable: false)
        : null;
    final regimesRaw = j['regime_preference'];
    final regimesParsed = regimesRaw is List
        ? regimesRaw.map((s) => s.toString()).toList(growable: false)
        : null;
    final pSymsRaw = j['paper_symbol_preference'];
    final pSymsParsed = pSymsRaw is List
        ? pSymsRaw.map((s) => s.toString()).toList(growable: false)
        : null;
    final pPathsRaw = j['paper_path_preference'];
    final pPathsParsed = pPathsRaw is List
        ? pPathsRaw.map((s) => s.toString()).toList(growable: false)
        : null;
    final pRegimesRaw = j['paper_regime_preference'];
    final pRegimesParsed = pRegimesRaw is List
        ? pRegimesRaw.map((s) => s.toString()).toList(growable: false)
        : null;
    return AutoTradeSettings(
      mode: j['mode'] as String?,
      positionSizePct: (j['position_size_pct'] as num?)?.toDouble(),
      leverageCap: (j['leverage_cap'] as num?)?.toDouble(),
      maxConcurrentPositions:
          (j['max_concurrent_positions'] as num?)?.toInt(),
      symbolPreference: symsParsed,
      // GET response reflects current server state — flag this as
      // "we know what the server has" so subsequent PUTs that copy
      // this model don't strip the field by accident.
      symbolPreferenceSet: symsRaw is List || symsRaw == null && j.containsKey('symbol_preference'),
      pathPreference: pathsParsed,
      pathPreferenceSet: pathsRaw is List || pathsRaw == null && j.containsKey('path_preference'),
      regimePreference: regimesParsed,
      regimePreferenceSet: regimesRaw is List || regimesRaw == null && j.containsKey('regime_preference'),
      paperSymbolPreference: pSymsParsed,
      paperSymbolPreferenceSet: pSymsRaw is List || pSymsRaw == null && j.containsKey('paper_symbol_preference'),
      paperPathPreference: pPathsParsed,
      paperPathPreferenceSet: pPathsRaw is List || pPathsRaw == null && j.containsKey('paper_path_preference'),
      paperRegimePreference: pRegimesParsed,
      paperRegimePreferenceSet: pRegimesRaw is List || pRegimesRaw == null && j.containsKey('paper_regime_preference'),
      notionalUsd: (j['notional_usd'] as num?)?.toDouble(),
      usingDefaults: j['using_defaults'] as bool?,
      pausedReason: j['paused_reason'] as String?,
      pausedAt: j['paused_at'] as String?,
    );
  }

  Map<String, dynamic> toJsonPartial() {
    final out = <String, dynamic>{};
    if (mode != null) out['mode'] = mode;
    if (positionSizePct != null) out['position_size_pct'] = positionSizePct;
    if (leverageCap != null) out['leverage_cap'] = leverageCap;
    if (maxConcurrentPositions != null) {
      out['max_concurrent_positions'] = maxConcurrentPositions;
    }
    if (symbolPreferenceSet) {
      out['symbol_preference'] = symbolPreference;
    }
    if (pathPreferenceSet) {
      out['path_preference'] = pathPreference;
    }
    if (regimePreferenceSet) {
      out['regime_preference'] = regimePreference;
    }
    if (paperSymbolPreferenceSet) {
      out['paper_symbol_preference'] = paperSymbolPreference;
    }
    if (paperPathPreferenceSet) {
      out['paper_path_preference'] = paperPathPreference;
    }
    if (paperRegimePreferenceSet) {
      out['paper_regime_preference'] = paperRegimePreference;
    }
    if (notionalUsd != null) out['notional_usd'] = notionalUsd;
    return out;
  }
}

/// User profile — backend ``GET / PUT /api/profile`` (Phase 3).
///
/// All fields nullable on read (a freshly-created user has nothing set
/// until SignupPage completes); ``needsOnboarding`` mirrors the engine's
/// derived flag so the app doesn't have to inspect ``onboardedAt``
/// directly.  On PUT, the engine accepts a partial body — only the
/// non-null fields are sent so the caller doesn't have to round-trip
/// the entire row to update one column.
class Profile {
  const Profile({
    this.userId,
    this.phoneE164,
    this.tier,
    this.paidUntil,
    this.displayName,
    this.countryCode,
    this.timezone,
    this.currency,
    this.termsAcceptedAt,
    this.onboardedAt,
    this.needsOnboarding = true,
  });

  final int? userId;
  final String? phoneE164;
  final String? tier;
  final String? paidUntil;
  final String? displayName;
  final String? countryCode;
  final String? timezone;
  final String? currency;
  final String? termsAcceptedAt;
  final String? onboardedAt;
  final bool needsOnboarding;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        userId: (j['user_id'] as num?)?.toInt(),
        phoneE164: j['phone_e164'] as String?,
        tier: j['tier'] as String?,
        paidUntil: j['paid_until'] as String?,
        displayName: j['display_name'] as String?,
        countryCode: j['country_code'] as String?,
        timezone: j['timezone'] as String?,
        currency: j['currency'] as String?,
        termsAcceptedAt: j['terms_accepted_at'] as String?,
        onboardedAt: j['onboarded_at'] as String?,
        needsOnboarding: j['needs_onboarding'] as bool? ?? true,
      );

  /// Partial PUT — only non-null fields are sent.
  Map<String, dynamic> toJsonPartial({bool acceptTerms = false}) {
    final out = <String, dynamic>{};
    if (displayName != null) out['display_name'] = displayName;
    if (countryCode != null) out['country_code'] = countryCode;
    if (timezone != null) out['timezone'] = timezone;
    if (currency != null) out['currency'] = currency;
    if (acceptTerms) out['accept_terms'] = true;
    return out;
  }
}

/// One TP partial-close inside a paper trade record.
///
/// The engine fires partial fills as TP1/TP2/TP3 ladders hit — each one
/// closes a fraction of the position at that level's price and books a
/// slice of the total realised PnL.  Surfaced on the trade detail page
/// so subscribers can see exactly how a trade unwound rather than just
/// the aggregate close.
class PartialFill {
  const PartialFill({
    required this.tpLevel,
    required this.fraction,
    required this.fillPrice,
    required this.pnlUsd,
    required this.feeUsd,
    required this.ts,
  });

  /// 1, 2, or 3 — which TP rung this fill corresponds to.
  final int tpLevel;
  /// 0.0–1.0 — proportion of remaining qty closed at this rung.
  final double fraction;
  final double fillPrice;
  final double pnlUsd;
  final double feeUsd;
  final DateTime ts;

  factory PartialFill.fromJson(Map<String, dynamic> j) => PartialFill(
        tpLevel: (j['tp_level'] as num?)?.toInt() ?? 0,
        fraction: (j['fraction'] as num?)?.toDouble() ?? 0.0,
        fillPrice: (j['fill_price'] as num?)?.toDouble() ?? 0.0,
        pnlUsd: (j['pnl_usd'] as num?)?.toDouble() ?? 0.0,
        feeUsd: (j['fee_usd'] as num?)?.toDouble() ?? 0.0,
        ts: DateTime.tryParse(j['ts'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  Map<String, dynamic> toMap() => {
        'tp_level': tpLevel,
        'fraction': fraction,
        'fill_price': fillPrice,
        'pnl_usd': pnlUsd,
        'fee_usd': feeUsd,
        'ts': ts.toIso8601String(),
      };
}

/// One paper-trade record — open or closed.
///
/// Matches the engine ``GET /api/trades?mode=paper`` payload.  Open
/// trades have ``closedAt`` + the PnL fields null; closed trades carry
/// the full settlement (gross / fees / net) plus ``roiPctOnMargin``
/// which is the key metric the Trade tab leads with (margin = notional
/// / leverage, so a 10x trade that moved +2% on price shows ~+20% ROI).
class TradeRecord {
  const TradeRecord({
    required this.signalId,
    required this.symbol,
    required this.side,
    required this.entry,
    required this.qty,
    required this.leverage,
    required this.positionSizePct,
    required this.notionalUsd,
    required this.marginUsd,
    required this.partialFills,
    required this.createdAt,
    this.closeReason,
    this.closePrice,
    this.grossPnlUsd,
    this.feesUsd,
    this.netPnlUsd,
    this.roiPctOnMargin,
    this.closedAt,
  });

  /// Originating signal id (e.g. ``SIG-2841``).  Used as the order
  /// number on the detail page.
  final String signalId;
  final String symbol;
  /// ``'long'`` | ``'short'`` — lowercase per the engine contract.
  final String side;
  final double entry;
  final double qty;
  /// Leverage snapshot at open (e.g. 10.0).  Captured at fill time so
  /// later config changes don't retroactively rewrite history.
  final double leverage;
  /// Position-size % snapshot at open.
  final double positionSizePct;
  /// ``entry * qty`` — the gross exposure of the position.
  final double notionalUsd;
  /// ``notionalUsd / leverage`` — the actual capital committed.  Used
  /// as the denominator for ``roiPctOnMargin``.
  final double marginUsd;
  final List<PartialFill> partialFills;

  /// One of ``tp1``/``tp2``/``tp3``/``sl_hit``/``invalidated``/
  /// ``expired``/``cancelled``/``pre_tp_grab``.  Null while the trade
  /// is still open.
  final String? closeReason;
  final double? closePrice;
  final double? grossPnlUsd;
  final double? feesUsd;
  final double? netPnlUsd;
  /// **Key metric for display** — net PnL as a % of margin committed.
  /// Honest "what would I have earned on my actual capital outlay"
  /// number that subscribers asked for.
  final double? roiPctOnMargin;
  final DateTime createdAt;
  final DateTime? closedAt;

  bool get isOpen => closedAt == null;

  Map<String, dynamic> toMap() => {
        'signal_id': signalId,
        'symbol': symbol,
        'side': side,
        'entry': entry,
        'qty': qty,
        'leverage': leverage,
        'position_size_pct': positionSizePct,
        'notional_usd': notionalUsd,
        'margin_usd': marginUsd,
        'partial_fills': partialFills.map((f) => f.toMap()).toList(),
        'close_reason': closeReason,
        'close_price': closePrice,
        'gross_pnl_usd': grossPnlUsd,
        'fees_usd': feesUsd,
        'net_pnl_usd': netPnlUsd,
        'roi_pct_on_margin': roiPctOnMargin,
        'created_at': createdAt.toIso8601String(),
        'closed_at': closedAt?.toIso8601String(),
      };

  factory TradeRecord.fromJson(Map<String, dynamic> j) => TradeRecord(
        signalId: j['signal_id'] as String? ?? '',
        symbol: j['symbol'] as String? ?? '',
        side: j['side'] as String? ?? 'long',
        entry: (j['entry'] as num?)?.toDouble() ?? 0.0,
        qty: (j['qty'] as num?)?.toDouble() ?? 0.0,
        leverage: (j['leverage'] as num?)?.toDouble() ?? 1.0,
        positionSizePct:
            (j['position_size_pct'] as num?)?.toDouble() ?? 0.0,
        notionalUsd: (j['notional_usd'] as num?)?.toDouble() ?? 0.0,
        marginUsd: (j['margin_usd'] as num?)?.toDouble() ?? 0.0,
        partialFills: ((j['partial_fills'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PartialFill.fromJson)
            .toList(),
        closeReason: j['close_reason'] as String?,
        closePrice: (j['close_price'] as num?)?.toDouble(),
        grossPnlUsd: (j['gross_pnl_usd'] as num?)?.toDouble(),
        feesUsd: (j['fees_usd'] as num?)?.toDouble(),
        netPnlUsd: (j['net_pnl_usd'] as num?)?.toDouble(),
        roiPctOnMargin: (j['roi_pct_on_margin'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')
                ?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        closedAt: j['closed_at'] == null
            ? null
            : DateTime.tryParse(j['closed_at'] as String)?.toUtc(),
      );
}

/// Paginated paper-trade list response.
///
/// ``items`` is the page slice; ``total`` is the full count so the page
/// knows whether to keep loading more.  The infinite-scroll loader on
/// :class:`PaperTradesPage` halts when ``offset + items.length >= total``.
class TradeListResponse {
  const TradeListResponse({required this.items, required this.total});
  final List<TradeRecord> items;
  final int total;

  factory TradeListResponse.fromJson(Map<String, dynamic> j) =>
      TradeListResponse(
        items: ((j['items'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(TradeRecord.fromJson)
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
      );

  String toJsonString() => jsonEncode({
        'items': items.map((t) => t.toMap()).toList(),
        'total': total,
      });

  static TradeListResponse? fromJsonString(String str) {
    try {
      final j = jsonDecode(str) as Map<String, dynamic>;
      return TradeListResponse.fromJson(j);
    } catch (_) {
      return null;
    }
  }
}

/// Response from ``POST /api/auto-mode/paper/reset``.
///
/// ``resetAt`` is the moment the engine archived the prior ledger and
/// started a fresh one; ``startingEquityUsd`` is the new equity (always
/// $1000 in the current implementation, but plumbed through the type
/// so a future configurable starting balance doesn't break the contract).
class PaperResetResponse {
  const PaperResetResponse({
    required this.resetAt,
    required this.startingEquityUsd,
  });
  final DateTime resetAt;
  final double startingEquityUsd;

  factory PaperResetResponse.fromJson(Map<String, dynamic> j) =>
      PaperResetResponse(
        resetAt: DateTime.tryParse(j['reset_at'] as String? ?? '')
                ?.toUtc() ??
            DateTime.now().toUtc(),
        startingEquityUsd:
            (j['starting_equity_usd'] as num?)?.toDouble() ?? 1000.0,
      );
}

/// Response from ``POST /api/auto-mode/paper/reset-mine`` — the per-user
/// "clear my paper history" endpoint introduced 2026-05-23 to unblock
/// non-owner users (the existing ``/reset`` endpoint requires
/// ``tier='owner'`` and returned 403 to free users hitting the in-app
/// Reset button).
///
/// ``newStartedAt`` is the timestamp of the user's fresh paper-
/// subscription window. ``GET /api/trades`` only returns rows closed
/// at-or-after this stamp until the user disables paper or calls
/// reset-mine again.
class PaperResetMineResponse {
  const PaperResetMineResponse({required this.newStartedAt});
  final DateTime newStartedAt;

  factory PaperResetMineResponse.fromJson(Map<String, dynamic> j) =>
      PaperResetMineResponse(
        newStartedAt: DateTime.tryParse(j['new_started_at'] as String? ?? '')
                ?.toUtc() ??
            DateTime.now().toUtc(),
      );
}

/// Response from ``POST /api/auto-mode/paper/close-all``.
///
/// Engine PR #403 (2026-05-16) added this endpoint to flatten the paper
/// book on demand — the user-facing companion to ``/api/auto-mode/paper/
/// reset``'s B12 lifecycle guard, which refuses while open positions
/// exist.  The two-step user flow is: close-all → reset.  Each
/// returned position is closed at its entry price (zero-move fill,
/// fees only) so the reset that follows can land cleanly.
/// Client region info — backend ``GET /api/region`` (Play Store
/// launch, 2026-05-20).
///
/// Soft-fail semantics: when the server can't derive a region from
/// CDN headers, ``countryCode`` is the literal string ``"unknown"``
/// (not null) and ``isBlocked`` is false.  Doctrine: we'd rather
/// show the auto-trade UI to a user we can't identify than block a
/// user in a permitted region.  Server-side dispatch is the real
/// security boundary.
class RegionInfo {
  const RegionInfo({
    required this.countryCode,
    required this.source,
    required this.isBlocked,
    required this.blockedRegions,
  });

  /// ISO 3166-1 alpha-2 ("IN", "GB", "US", ...) or the literal
  /// string ``"unknown"`` when no region could be derived.
  final String countryCode;

  /// Where the region came from: ``"cf-header"`` (Cloudflare) /
  /// ``"x-header"`` (other CDN) / ``"unknown"`` (no header).  Used
  /// by debug surfaces, not by the user-facing UI.
  final String source;

  /// True iff the country is in the server's BLOCKED_REGIONS set.
  /// The client mirrors this rather than computing locally so the
  /// env-overridable server list stays the single source of truth.
  final bool isBlocked;

  /// The current server-side block list, sorted.  The client uses
  /// this to render "not available in US / CN / BD" copy without
  /// hard-coding the list.
  final List<String> blockedRegions;

  /// True when [countryCode] is the literal ``"unknown"`` — i.e.
  /// the server couldn't derive a region from headers.  Callers
  /// that want to differentiate "known + not blocked" from "soft-
  /// fail open" check this flag.
  bool get isUnknown => countryCode == 'unknown';

  factory RegionInfo.fromJson(Map<String, dynamic> j) {
    final blocked = (j['blocked_regions'] as List?) ?? const [];
    return RegionInfo(
      countryCode: (j['country_code'] as String?) ?? 'unknown',
      source: (j['source'] as String?) ?? 'unknown',
      isBlocked: (j['is_blocked'] as bool?) ?? false,
      blockedRegions: blocked.map((e) => e.toString()).toList(growable: false),
    );
  }
}


/// Thrown by [LuminRepository.deleteAccount] on known backend
/// failure tags (Play Store launch E1 / A4-partial, 2026-05-20).
///
/// The backend returns 503 with a specific ``detail`` string for
/// each step that can fail in the deletion orchestration; we surface
/// those tags to the UI so the user gets an actionable message
/// rather than a generic "try again".
class DeleteAccountException implements Exception {
  const DeleteAccountException(this.tag, this.message);

  /// Backend-supplied failure tag (e.g.
  /// ``key_blob_delete_failed``, ``user_row_delete_failed``,
  /// ``server_misconfiguration_user_store``).  Stable across the
  /// engine + lumin-app pair via the contract defined in
  /// ``src/api/account_routes.py``.
  final String tag;

  /// Human-readable description of the failure for use in a
  /// SnackBar or dialog body.
  final String message;

  @override
  String toString() => 'DeleteAccountException($tag): $message';
}


class PaperCloseAllResponse {
  const PaperCloseAllResponse({
    required this.closedCount,
    required this.realisedPnlTotal,
  });

  /// Number of paper positions that were open and got closed.  Zero
  /// when the book was already flat (idempotent — no error fires).
  final int closedCount;

  /// Sum of realised PnL across the batch.  Slightly negative in
  /// general (round-trip fees on the zero-move fills); engine PR #403's
  /// docstring notes this is behaviourally correct — a Binance flatten
  /// pays the same fees.
  final double realisedPnlTotal;

  factory PaperCloseAllResponse.fromJson(Map<String, dynamic> j) =>
      PaperCloseAllResponse(
        closedCount: (j['closed_count'] as num?)?.toInt() ?? 0,
        realisedPnlTotal:
            (j['realised_pnl_total'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Composed payload the Pulse page renders.  Lives here (not in
/// pulse_page.dart) so the repository can construct + cache it as a
/// single SwrCache entry — single cache hit on tab re-entry, single
/// emit per refresh cycle.  Plain data class; no logic.
class PulseBundle {
  const PulseBundle({
    required this.engine,
    required this.recent,
    required this.tickers,
    required this.pnlHistory,
    required this.userPnl,
  });
  final MockEngineSnapshot engine;
  final List<MockSignal> recent;
  final List<MockTicker> tickers;
  /// Engine-global PnL history (last 30 days).  Kept around for the
  /// engine-health chart but **not** rendered as the user's own
  /// performance — that's [userPnl] now.
  final PnlHistory pnlHistory;
  /// Per-user PnL snapshot — replaces what used to be sourced from
  /// ``engine.todayPnlUsd``.  See [UserPnlSnapshot] for the per-user
  /// fix doctrine.
  final UserPnlSnapshot userPnl;
}

/// Engine-side payload the Trade page consumes.  Pure repo data —
/// no Binance / no secure-storage / no context dependency, so the
/// repo can cache it via SwrCache the same way as PulseBundle.  The
/// page composes this with its locally-fetched Binance slice
/// (kept page-local because the secure-storage key lookup needs
/// user-context).
class TradeEngineSnapshot {
  const TradeEngineSnapshot({
    required this.autoMode,
    required this.userSettings,
    required this.positions,
    required this.activity,
  });
  final AutoModeStatus autoMode;
  final AutoTradeSettings userSettings;
  final List<MockPosition> positions;
  final List<MockActivityEvent> activity;
}

/// Per-user PnL snapshot — drives the Pulse tab "TODAY'S P&L" card.
///
/// Sources from ``GET /api/auto-trade/positions`` (per-user via
/// Firebase ID token).  ``realisedUsd`` sums ``realized_pnl_total``
/// across every open position the user has — that's the partial-close
/// realised PnL booked on TP1 fills and pre-TP grabs (B17).  Closed
/// positions aren't returned by that endpoint so historical PnL isn't
/// part of this snapshot today; the page renders "No closed history
/// yet" rather than a misleading aggregate.
///
/// ``hasAnyTrading`` lets the page distinguish "user is trading,
/// PnL just happens to be 0 right now" from "user hasn't opted in at
/// all" — the latter gets the "Enable trading from the Trade tab"
/// CTA rather than a deceptive $0.00.
class UserPnlSnapshot {
  const UserPnlSnapshot({
    required this.realisedUsd,
    required this.openPositionCount,
    required this.hasAnyTrading,
  });
  /// Sum of ``realized_pnl_total`` across the user's open positions.
  /// Negative when partial closes booked losses.
  final double realisedUsd;
  /// How many positions the user currently has open server-side.
  final int openPositionCount;
  /// True when the user has at least one open position — proxy for
  /// "user has opted into server-side auto-trade".  False = render
  /// the not-enabled CTA on Pulse.
  final bool hasAnyTrading;

  static const empty = UserPnlSnapshot(
    realisedUsd: 0.0,
    openPositionCount: 0,
    hasAnyTrading: false,
  );
}

/// Top-level assembler — same rationale as ``assemblePulseBundle``.
/// Per-user PnL is currently a client-side roll-up of the user's
/// open server-side positions; when the engine adds a per-user PnL
/// endpoint (deferred per OWNER_BRIEF §3.8), this is the swap point.
///
/// ``hasAnyTrading`` is true when either: (a) the user has at least
/// one open server-side position, OR (b) the user's auto-trade mode
/// is not ``'off'``.  Covers the "trading enabled but no signal has
/// fired yet" edge case so brand-new opt-in users don't see the
/// misleading "Trading not enabled yet" CTA.
Future<UserPnlSnapshot> assembleUserPnlSnapshot(LuminRepository repo) async {
  try {
    final results = await Future.wait([
      repo.getAutoTradePositions(),
      // Runtime status carries the per-user mode pill — catch on the
      // anonymous-device-JWT 401 path so we still produce a snapshot
      // when only positions came back.
      repo.getAutoTradeRuntimeStatus().then<AutoTradeRuntimeStatus?>(
            (s) => s,
            onError: (_) => null,
          ),
    ]);
    final positions = results[0] as List<ServerSidePosition>;
    final runtime = results[1] as AutoTradeRuntimeStatus?;
    final modeOptedIn =
        runtime != null && (runtime.userMode ?? 'off') != 'off';
    if (positions.isEmpty && !modeOptedIn) {
      return UserPnlSnapshot.empty;
    }
    final realised = positions.fold<double>(
      0.0,
      (acc, p) => acc + p.realizedPnlTotal,
    );
    return UserPnlSnapshot(
      realisedUsd: realised,
      openPositionCount: positions.length,
      hasAnyTrading: true,
    );
  } catch (_) {
    return UserPnlSnapshot.empty;
  }
}

/// Top-level assembler — same rationale as ``assemblePulseBundle``
/// (Dart doesn't inherit method bodies across ``implements``).
/// ``fetchUserAutoTradeSettings`` 404s for anonymous device JWTs;
/// catch + fall back to the "no overrides" sentinel so the mode pill
/// follows engine until phone sign-in lands.
Future<TradeEngineSnapshot> assembleTradeEngineSnapshot(
    LuminRepository repo) async {
  final results = await Future.wait([
    repo.fetchAutoMode(),
    repo.fetchPositions(),
    repo.fetchActivity(limit: 30),
    repo.fetchUserAutoTradeSettings().catchError(
          (_) => const AutoTradeSettings(usingDefaults: true),
        ),
  ]);
  return TradeEngineSnapshot(
    autoMode: results[0] as AutoModeStatus,
    positions: (results[1] as List).cast<MockPosition>(),
    activity: (results[2] as List).cast<MockActivityEvent>(),
    userSettings: results[3] as AutoTradeSettings,
  );
}

/// Top-level assembler so the abstract default + each concrete
/// implementation can share one fan-out path.  Top-level (not a
/// method on LuminRepository) because Dart doesn't inherit method
/// bodies across ``implements`` — putting the body here is the
/// cleanest way to avoid duplicating it across Mock + Http.
///
/// Tickers + pnl history catch errors and fall back to empty
/// payloads so a missing strip or a pre-engine-#338 deployment
/// never blocks the rest of the page.
///
/// Phase 3 perf — recent-signals fetch goes through ``watchSignals``
/// (limit=100, same as SignalsPage + AutoTradeWatcher) and slices to
/// 3 client-side so all three consumers share one SwrCache entry
/// (key ``signals:all:100:_``).  Watcher's 15s tick keeps the cache
/// warm; Pulse subscribers get instant cache hits.
Future<PulseBundle> assemblePulseBundle(LuminRepository repo) async {
  final results = await Future.wait([
    repo.fetchPulse(),
    repo
        .watchSignals(status: 'all', limit: 100)
        .first
        .then((sigs) => sigs.take(3).toList()),
    repo.fetchTickers().catchError((_) => <MockTicker>[]),
    repo.fetchPnlHistory(days: 30).catchError(
          (_) => const PnlHistory(
            mode: 'off',
            days: 30,
            items: <PnlPoint>[],
            weeklyPnlUsd: 0.0,
            monthlyPnlUsd: 0.0,
          ),
        ),
    // Per-user PnL — replaces the engine-global todayPnlUsd that
    // was leaking across users.  Already error-tolerant inside the
    // assembler (falls through to ``UserPnlSnapshot.empty``).
    assembleUserPnlSnapshot(repo),
  ]);
  return PulseBundle(
    engine: results[0] as MockEngineSnapshot,
    recent: (results[1] as List).cast<MockSignal>(),
    tickers: (results[2] as List).cast<MockTicker>(),
    pnlHistory: results[3] as PnlHistory,
    userPnl: results[4] as UserPnlSnapshot,
  );
}

/// Result of verifying a Google Play purchase with the engine (B16).
class PlayVerifyResult {
  const PlayVerifyResult({
    required this.ok,
    required this.tier,
    required this.subscriptionState,
    this.paidUntil,
  });

  final bool ok;

  /// Entitlement tier the engine persisted (``paid`` on success).
  final String tier;

  /// ISO-8601 UTC subscription expiry, or null when not entitled.
  final String? paidUntil;

  /// Raw Play ``subscriptionState`` (diagnostics).
  final String subscriptionState;

  /// Any paid entitlement — assist, auto, legacy paid, or all-access.
  bool get isPaid =>
      tier == 'assist' ||
      tier == 'auto' ||
      tier == 'paid' ||
      tier == 'all-access';

  factory PlayVerifyResult.fromJson(Map<String, dynamic> j) => PlayVerifyResult(
        ok: j['ok'] == true,
        tier: (j['tier'] as String?) ?? 'free',
        paidUntil: j['paid_until'] as String?,
        subscriptionState: (j['subscription_state'] as String?) ?? '',
      );
}

abstract class LuminRepository {
  /// True when the underlying source is the live engine (vs. mocks).
  bool get isLive;

  Future<MockEngineSnapshot> fetchPulse();
  Future<List<MockTicker>> fetchTickers();
  Future<List<MockSignal>> fetchSignals({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  });

  /// Stale-while-revalidate variant of ``fetchSignals``.  Default
  /// implementation just wraps the future as a single-event stream so
  /// mock/test impls don't need to opt in; ``HttpRepository`` overrides
  /// to actually cache + emit stale-then-fresh.  See
  /// :class:`SwrCache` for the pattern rationale.
  Stream<List<MockSignal>> watchSignals({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  }) =>
      Stream.fromFuture(fetchSignals(
        status: status,
        limit: limit,
        setupClass: setupClass,
      ));

  /// Drop the cached ``watchSignals`` entries — called from
  /// pull-to-refresh so the next resubscribe re-fetches instead of
  /// serving stale.  No-op on impls without a cache (Mock).
  void invalidateSignalsCache({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  }) {
    // Default no-op.  HttpRepository overrides.
  }

  /// Stream the composed Pulse bundle (engine snapshot + recent
  /// signals + tickers + pnl history) with SWR semantics.  Default
  /// impl assembles the four sub-fetches in parallel and wraps the
  /// result as a single-event stream so non-cached impls have a
  /// uniform interface; ``HttpRepository`` caches the assembled bundle.
  Stream<PulseBundle> watchPulseBundle() async* {
    yield await assemblePulseBundle(this);
  }

  /// Drop the cached Pulse bundle — pull-to-refresh entry point.
  void invalidatePulseBundleCache() {
    // Default no-op.  HttpRepository overrides.
  }

  /// Stream the engine-side Trade payload (auto-mode, positions,
  /// activity, user-settings) with SWR semantics.  Page composes
  /// this with its locally-fetched Binance slice.
  Stream<TradeEngineSnapshot> watchTradeEngineSnapshot() async* {
    yield await assembleTradeEngineSnapshot(this);
  }

  /// Drop the cached Trade engine snapshot — pull-to-refresh entry.
  void invalidateTradeEngineSnapshotCache() {
    // Default no-op.  HttpRepository overrides.
  }

  // SWR-cached watches for the four user-scoped endpoints the Trade
  // tab previously hit directly on every mount.  Wrapping them lets
  // ``prewarmCaches`` warm them at sign-in so the first tap on the
  // Trade tab is instant instead of waiting 4 sequential network
  // round-trips.  Each is keyed without a user-id because the engine
  // already scopes by Firebase ID token, and ``SwrCache.clear()``
  // wipes everything on sign-out.
  Stream<List<AgentStat>> watchAgents() async* {
    yield await fetchAgents();
  }
  void invalidateAgentsCache() {}

  Stream<AutoTradeUserStatus> watchAutoTradeUserStatus() async* {
    yield await getAutoTradeUserStatus();
  }
  void invalidateAutoTradeUserStatusCache() {}

  Stream<AutoTradeRuntimeStatus> watchAutoTradeRuntimeStatus() async* {
    yield await getAutoTradeRuntimeStatus();
  }
  void invalidateAutoTradeRuntimeStatusCache() {}

  Stream<List<ServerSidePosition>> watchAutoTradePositions() async* {
    yield await getAutoTradePositions();
  }
  void invalidateAutoTradePositionsCache() {}

  Stream<List<DispatchEvent>> watchRecentDispatchEvents({int limit = 20}) async* {
    yield await getRecentDispatchEvents(limit: limit);
  }
  void invalidateRecentDispatchEventsCache({int limit = 20}) {}

  /// SWR-cached first page of the paper-trade ledger.  PaperTradesPage is
  /// a pushed route with fresh State on every open, so without this it
  /// showed a full-screen spinner on every visit.  Caching the first page
  /// lets a re-open render the prior rows instantly while a background
  /// refresh fires.  Pagination (offset > 0) stays a direct ``fetchTrades``
  /// call — only the first page is cached.
  Stream<TradeListResponse> watchPaperTradesFirstPage({int limit = 50}) async* {
    yield await fetchTrades(
      mode: 'paper', limit: limit, offset: 0, includeOpen: true,
    );
  }
  void invalidatePaperTradesCache({int limit = 50}) {}

  /// Per-user daily-PnL snapshot — computed from the user's
  /// server-side execution positions (``/api/auto-trade/positions``).
  /// Replaces the pre-2026-05-22 Pulse card that surfaced
  /// ``engine.todayPnlUsd`` from ``/api/pulse`` — that field is the
  /// engine-global ``RiskManager.daily_realised_pnl_usd``, the same
  /// number for every signed-in user, regardless of whether their
  /// per-user trading was even enabled.  Owner-reported 2026-05-22:
  /// "every user after logging seeing same PnL even not Paper mode
  /// not enabled".  Compute lives on the client because the engine
  /// doesn't expose a per-user PnL endpoint yet (single-tenant paper
  /// book per OWNER_BRIEF §3.8).
  Stream<UserPnlSnapshot> watchUserPnlSnapshot() async* {
    yield await assembleUserPnlSnapshot(this);
  }
  void invalidateUserPnlSnapshotCache() {}

  Future<List<MockPosition>> fetchPositions();
  Future<List<MockActivityEvent>> fetchActivity({
    int limit = 50,
    String? setupClass,
  });
  Future<AutoModeStatus> fetchAutoMode();
  Future<AutoModeStatus> setAutoMode(String mode);
  Future<List<AgentStat>> fetchAgents();
  /// Daily-bucketed realised PnL series + rolling aggregates (last
  /// ``days`` UTC days, default 30).  Powers the dashboard chart and
  /// the weekly / monthly summary cards.  ``mode`` defaults to the
  /// engine's current auto-execution mode; pass an explicit value to
  /// view the opposite ledger (paper history while in live, etc.).
  Future<PnlHistory> fetchPnlHistory({int days = 30, String? mode});
  /// Pre-TP grab settings page — engine-wide defaults (owner-only writes).
  /// Used by Settings → Engine defaults.
  Future<PretpSettings> fetchPretpSettings();
  Future<PretpSettings> updatePretpSettings(PretpSettings partial);
  /// Auto-trade settings page — engine-wide defaults (owner-only writes).
  Future<AutoTradeSettings> fetchAutoTradeSettings();
  Future<AutoTradeSettings> updateAutoTradeSettings(AutoTradeSettings partial);
  /// Per-user pre-TP overrides (Phase 2).  Every signed-in user can
  /// edit their own; the engine doesn't yet consume per-user values
  /// (Phase 3 wires execution).  Same data class — server adds the
  /// ``using_defaults`` flag so the page can render a "Custom" badge.
  Future<PretpSettings> fetchUserPretpSettings();
  Future<PretpSettings> updateUserPretpSettings(PretpSettings partial);

  /// Reset the user's pre-TP overrides to engine defaults
  /// (``DELETE /api/settings/user/pretp``).  Returns the rebuilt view with
  /// ``usingDefaults == true``.  Idempotent.
  Future<PretpSettings> resetUserPretpSettings();
  /// Per-user auto-trade overrides (Phase 2).
  Future<AutoTradeSettings> fetchUserAutoTradeSettings();
  Future<AutoTradeSettings> updateUserAutoTradeSettings(
    AutoTradeSettings partial,
  );
  /// Per-user invalidation overrides (OWNER_BRIEF B17, 2026-05-17).
  /// Three preset modes (loose / standard / tight) + advanced knobs.
  /// Engine-side TradeMonitor is owner-only auto-trade today; per-user
  /// values are consumed by the app-side OrderExecutor when Phase 4
  /// per-user execution lands.
  Future<InvalidationSettings> fetchUserInvalidationSettings();
  Future<InvalidationSettings> updateUserInvalidationSettings(
    InvalidationSettings partial,
  );

  /// Reset the user's invalidation overrides to engine defaults
  /// (``DELETE /api/settings/user/invalidation``).  Returns the rebuilt view
  /// with ``usingDefaults == true``.  Idempotent.
  Future<InvalidationSettings> resetUserInvalidationSettings();
  /// User profile (Phase 3) — drives SignupPage + Settings → Profile.
  Future<Profile> fetchProfile();
  Future<Profile> updateProfile(Profile partial, {bool acceptTerms = false});
  /// Per-trade visibility feed — paginated paper-trade records ordered
  /// most-recent-first.  Drives :class:`PaperTradesPage`.  ``sinceTs``
  /// + ``symbol`` are pass-through filters the engine applies before
  /// pagination.
  Future<TradeListResponse> fetchTrades({
    String mode = 'paper',
    int limit = 50,
    int offset = 0,
    String? sinceTs,
    String? symbol,
    bool includeOpen = false,
  });
  /// Reset the paper ledger to a fresh $1000 starting equity.  The
  /// engine archives prior trade history (the audit ledger keeps the
  /// raw rows) but the live ``/api/trades?mode=paper`` view starts
  /// empty.  Owner-confirmed via dialog before this fires.
  ///
  /// Owner-only on the engine — non-owner users get a 403. For per-user
  /// "clear my history" use :meth:`resetMinePaperHistory` instead.
  Future<PaperResetResponse> resetPaperBalance();

  /// Per-user "clear my paper history" — opens a fresh subscription
  /// window so the user's view of ``GET /api/trades`` returns empty
  /// until new trades close inside the new window. Engine state is
  /// untouched; other users' views are unaffected.
  ///
  /// User-callable for every tier (paid, free, owner). Replaces the
  /// owner-only ``/reset`` flow in the in-app Reset Balance action so
  /// fresh-signup users don't get 403'd.
  Future<PaperResetMineResponse> resetMinePaperHistory();

  /// Clear the engine's auto-pause flag for this user (engine PR #479,
  /// 2026-05-24). The engine auto-pauses a user's dispatcher after N
  /// consecutive Binance ``-2019`` (insufficient margin) rejections —
  /// stopping the Recent Activity spam. Calling this resumes
  /// dispatching; the user should call it AFTER topping up their
  /// Futures wallet, otherwise the next signal will just re-pause.
  ///
  /// Returns ``true`` when an active pause was cleared, ``false`` on
  /// the idempotent no-op path (user wasn't paused — happens if the
  /// user tapped Resume after the operator already cleared the pause
  /// or after the engine restarted).
  Future<bool> resumeMineAutoTrade();

  /// Connect a Binance API key for server-side execution (engine B18 +
  /// PR-2 ``/api/binance/connect``).  Posts the key to the engine,
  /// which validates against Binance (withdraw=off, futures=on, IP
  /// whitelist on, futures wallet accessible), encrypts via Cloud KMS,
  /// and stores in Firestore.
  ///
  /// Returns [BinanceConnectSuccess] on validation success.  Throws
  /// [BinanceConnectError] on validation failure with the typed
  /// error code + the engine VPS IP (when applicable) so the caller
  /// can render targeted fix-up UI (deep-link to Binance API
  /// Management, show "add this IP to whitelist" with copy-button,
  /// etc.).
  Future<BinanceConnectSuccess> connectBinanceServerSide({
    required String apiKey,
    required String apiSecret,
  });

  /// Fetch the user's current Binance-connect state — does a
  /// Firestore key blob exist for this Firebase uid?
  /// (``GET /api/binance/connect/status``).  Drives the Server-side
  /// execution settings page's revisit UI so users don't always see
  /// the connect form after they've already connected.  Returns
  /// ``BinanceConnectStatus.notConnected`` on a fresh user.
  Future<BinanceConnectStatus> fetchBinanceConnectStatus();

  /// Hard-disconnect: delete the encrypted Binance key blob in
  /// Firestore (``DELETE /api/binance/connect``).  Idempotent — no
  /// error when already disconnected.  Existing positions on Binance
  /// are NOT closed; users must close them on Binance directly (the
  /// engine loses its signed-call path once the blob is gone).
  Future<void> disconnectBinanceServerSide();

  /// Fetch the user's auto-trade enablement state (engine PR-14
  /// follow-up — ``GET /api/auto-trade/user-status``).  Drives the
  /// Trade-tab "your auto-trade is disabled" banner.  Cached 5s
  /// server-side via KillSwitchClient so polling on tab refresh is
  /// cheap.  Engine returns a safe default + 200 even under
  /// Firestore outages, so this method only raises on
  /// network/5xx — status-level state is always reflected in the
  /// returned dataclass.
  Future<AutoTradeUserStatus> getAutoTradeUserStatus();

  /// Composite runtime status for the Live-tab "Auto-trade armed"
  /// card (``GET /api/auto-trade/runtime-status``).  Returns each of
  /// the four FSM gates separately so the UI can render per-gate
  /// green/red checks + the symbol allowlist as a footnote.
  /// Default-safe: when the engine hasn't wired the server-side
  /// execution stack, every gate returns False (the card renders
  /// "not configured" guidance rather than 5xx).
  Future<AutoTradeRuntimeStatus> getAutoTradeRuntimeStatus();

  /// Per-(user, symbol) management mode for the Signals-tab full/entry
  /// choice (``GET /api/settings/user/symbol-management``).  Returns a
  /// ``{SYMBOL: mode}`` map; any symbol NOT in the map is full-managed
  /// (the default) — so an empty map means "everything full".
  Future<Map<String, String>> fetchSymbolManagement();

  /// Set one symbol's management mode (``PUT …/symbol-management``).
  /// ``full`` = engine manages entry + SL + pre-TP + TP + invalidation;
  /// ``entry`` = engine places entry + protective SL only, user manages
  /// the rest.  Returns the rebuilt map.  Takes effect on the next signal
  /// dispatch for that symbol.
  Future<Map<String, String>> setSymbolManagement(String symbol, String mode);

  /// Verify a Google Play subscription purchase server-side (B16 —
  /// ``POST /api/billing/play/verify``).  The app sends the opaque
  /// ``purchaseToken`` + ``productId`` after Play Billing confirms a
  /// purchase; the engine validates it against the Play Developer API
  /// and persists the entitlement (the engine is the source of truth —
  /// nothing here is client-trusted).  Returns the resulting tier +
  /// expiry so the UI can unlock immediately.  Raises on network / 4xx
  /// (caller surfaces a retry).
  Future<PlayVerifyResult> verifyPlayPurchase({
    required String productId,
    required String purchaseToken,
  });

  /// Fetch the user's open server-side positions
  /// (``GET /api/auto-trade/positions``).  The engine reads
  /// Firestore at ``users/{firebase_uid}/positions/`` and returns
  /// only non-terminal states — the Live tab is meant to show what's
  /// open right now.  Historical PnL flows through the trade-records
  /// surface (TBD).
  Future<List<ServerSidePosition>> getAutoTradePositions();

  /// Fetch the user's recent dispatch events
  /// (``GET /api/auto-trade/recent-events``).  One row per order-
  /// placement attempt the engine made on this account — placed +
  /// rejected — newest first.  Drives the Trade-tab "Recent activity"
  /// card so the user can see *why* a signal didn't open (most
  /// commonly: empty Futures wallet → ``-2019`` rejection).  Server-
  /// side cap is 100; pass [limit] = 20 for the standard card view.
  Future<List<DispatchEvent>> getRecentDispatchEvents({int limit});

  /// Fetch the client's region info (``GET /api/region``).  Used by
  /// the auto-trade region gate (Play Store launch A6, 2026-05-20)
  /// to hide auto-trade UI in restricted jurisdictions.  Public
  /// endpoint — callable before sign-in.  Soft-fails to
  /// ``country_code = "unknown"`` + ``is_blocked = false`` when the
  /// server can't derive a region from CDN headers.
  Future<RegionInfo> fetchRegion();

  /// Pre-warm in-memory caches so the first tab-switch after sign-in
  /// renders synchronously instead of waiting on a network round-trip
  /// (2026-05-21 — Play Store launch follow-up).
  ///
  /// **Doctrine — fire-and-forget.**  Returns immediately.  Each
  /// underlying fetch runs concurrently in the background, populating
  /// the ``SwrCache`` as a side effect.  Failures are swallowed
  /// silently because:
  ///
  /// * If a fetch fails here, the same fetch will retry when the UI
  ///   actually subscribes — so the user gets the SAME error path as
  ///   before, just no benefit of pre-warming.
  /// * The caller (NavShell / AuthGate) MUST NOT block UI on this —
  ///   it's a UX nicety, not a correctness gate.
  ///
  /// **What gets warmed:**
  ///
  /// * ``PulseBundle`` — Live tab landing surface (8+ sub-fetches)
  /// * ``TradeEngineSnapshot`` — Trade tab engine slice
  /// * ``RegionInfo`` — Auto-trade region gate
  ///
  /// Default implementation is a no-op (mock + test paths).
  /// HttpRepository overrides to actually fire the network calls.
  Future<void> prewarmCaches() async {
    // No-op default — mock + test repos don't need pre-warming since
    // their fetches are synchronous-ish in-memory.
  }

  /// Delete the authenticated user's account
  /// (``DELETE /api/account``).  Required by Google Play's User
  /// Data policy — apps that let users create an account must let
  /// users delete it from within the app.  The backend orchestrates:
  /// Firestore Binance-key blob revocation → SQLite user row
  /// delete (cascades per-user override tables) → user-roster
  /// cache invalidation.  Throws [DeleteAccountException] on
  /// known failure modes (key_blob_delete_failed,
  /// user_row_delete_failed, server_misconfiguration_user_store).
  /// Returns normally on 204.
  Future<void> deleteAccount();

  /// Flatten the paper book — close every open paper position at its
  /// entry price (engine PR #403).  Pairs with ``resetPaperBalance`` to
  /// implement the two-step user flow: close-all → reset.  The reset
  /// endpoint refuses while open positions exist (B12 lifecycle guard,
  /// mirrored from the live-mode preservation doctrine), and the
  /// 409 error explicitly directs users here.
  Future<PaperCloseAllResponse> closeAllPaperPositions();
  Future<bool> healthCheck();
}

// ---------------------------------------------------------------------------
// MockRepository — wraps the constants in ``mock_data.dart``.
// ---------------------------------------------------------------------------

class MockRepository implements LuminRepository {
  const MockRepository();

  @override
  bool get isLive => false;

  @override
  Future<MockEngineSnapshot> fetchPulse() async => mockEngine;

  @override
  Future<List<MockTicker>> fetchTickers() async => mockTickers;

  @override
  Future<List<MockSignal>> fetchSignals({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  }) async {
    // setupClass is ignored in mock mode — the 4-signal fixture isn't
    // worth filtering and Live mode is the canonical path for drill-down.
    final all = mockSignals;
    Iterable<MockSignal> filtered;
    switch (status) {
      case 'open':
        filtered = all.where((s) => s.status == 'ACTIVE');
        break;
      case 'closed':
        filtered = all.where((s) => s.status != 'ACTIVE');
        break;
      default:
        filtered = all;
    }
    return filtered.take(limit).toList();
  }

  /// Mock impl: no caching needed (the source is in-memory anyway).
  /// Implements the abstract API as a single-event stream so the page
  /// code path is uniform across Live and Mock scopes.
  @override
  Stream<List<MockSignal>> watchSignals({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  }) =>
      Stream.fromFuture(fetchSignals(
        status: status,
        limit: limit,
        setupClass: setupClass,
      ));

  /// Mock impl: no-op.  ``implements LuminRepository`` requires this
  /// even though the abstract has a default body — Dart doesn't
  /// inherit method bodies across ``implements``.
  @override
  void invalidateSignalsCache({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  }) {}

  /// Mock impl: same fanout-then-emit as the abstract default — no
  /// caching needed since the underlying fetches are in-memory anyway.
  @override
  Stream<PulseBundle> watchPulseBundle() async* {
    yield await assemblePulseBundle(this);
  }

  @override
  void invalidatePulseBundleCache() {}

  @override
  Stream<TradeEngineSnapshot> watchTradeEngineSnapshot() async* {
    yield await assembleTradeEngineSnapshot(this);
  }

  @override
  void invalidateTradeEngineSnapshotCache() {}

  // Mock overrides for the per-tab SWR watches added 2026-05-22.
  // ``MockRepository implements LuminRepository`` and ``implements``
  // doesn't inherit method bodies — so even the abstract's concrete
  // default body has to be re-declared here.  Each wraps the
  // existing in-memory ``getX`` / ``fetchX`` as a single-event
  // stream; ``invalidateXCache`` is a no-op (no underlying cache).
  @override
  Stream<List<AgentStat>> watchAgents() async* {
    yield await fetchAgents();
  }

  @override
  void invalidateAgentsCache() {}

  @override
  Stream<TradeListResponse> watchPaperTradesFirstPage({int limit = 50}) async* {
    yield await fetchTrades(
      mode: 'paper', limit: limit, offset: 0, includeOpen: true,
    );
  }

  @override
  void invalidatePaperTradesCache({int limit = 50}) {}

  @override
  Stream<AutoTradeUserStatus> watchAutoTradeUserStatus() async* {
    yield await getAutoTradeUserStatus();
  }

  @override
  void invalidateAutoTradeUserStatusCache() {}

  @override
  Stream<AutoTradeRuntimeStatus> watchAutoTradeRuntimeStatus() async* {
    yield await getAutoTradeRuntimeStatus();
  }

  @override
  void invalidateAutoTradeRuntimeStatusCache() {}

  @override
  Stream<List<ServerSidePosition>> watchAutoTradePositions() async* {
    yield await getAutoTradePositions();
  }

  @override
  void invalidateAutoTradePositionsCache() {}

  @override
  Stream<List<DispatchEvent>> watchRecentDispatchEvents({int limit = 20}) async* {
    yield await getRecentDispatchEvents(limit: limit);
  }

  @override
  void invalidateRecentDispatchEventsCache({int limit = 20}) {}

  @override
  Stream<UserPnlSnapshot> watchUserPnlSnapshot() async* {
    yield await assembleUserPnlSnapshot(this);
  }

  @override
  void invalidateUserPnlSnapshotCache() {}

  /// Mock pre-warm — no-op.  Mock fetches are synchronous-ish in-
  /// memory; there's nothing to pre-fetch.  Required because
  /// ``MockRepository implements LuminRepository`` and ``implements``
  /// does not inherit method bodies, even default ones.
  @override
  Future<void> prewarmCaches() async {}

  @override
  Future<List<MockPosition>> fetchPositions() async => mockPositions;

  @override
  Future<List<MockActivityEvent>> fetchActivity({
    int limit = 50,
    String? setupClass,
  }) async =>
      mockActivity.take(limit).toList();

  @override
  Future<AutoModeStatus> fetchAutoMode() async => const AutoModeStatus(
        mode: 'paper',
        openPositions: 1,
        dailyPnlUsd: 12.84,
        dailyLossPct: 0.0,
        dailyKillTripped: false,
        manualPaused: false,
        currentEquityUsd: 1012.84,
        simulatedPnlUsd: 12.84,
      );

  @override
  Future<AutoModeStatus> setAutoMode(String mode) async =>
      // Mock can't actually switch — return a status with the requested mode
      // so the UI feedback feels right.
      AutoModeStatus(
        mode: mode,
        openPositions: 0,
        dailyPnlUsd: 0.0,
        dailyLossPct: 0.0,
        dailyKillTripped: false,
        manualPaused: false,
        currentEquityUsd: 1000.0,
      );

  @override
  Future<PnlHistory> fetchPnlHistory({int days = 30, String? mode}) async {
    // Synthesise a realistic-looking 30-day series so the chart widget
    // has something to render in offline / preview mode.  Pattern: a
    // few wins, a few losses, with a slight positive drift.  No live
    // engine is necessary to demo the surface.
    final now = DateTime.now().toUtc();
    final series = <PnlPoint>[];
    final pattern = <double>[
      0, 0, 4.2, 0, -2.1, 0, 8.5, 0, 0, -1.8,
      3.7, 0, 0, 6.0, -4.2, 0, 0, 2.1, 5.8, 0,
      0, -3.1, 0, 7.2, 0, 0, 1.5, -1.9, 0, 4.0,
    ];
    for (int offset = days - 1; offset >= 0; offset--) {
      final date = now.subtract(Duration(days: offset));
      final iso =
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final v = offset < pattern.length ? pattern[pattern.length - 1 - offset] : 0.0;
      series.add(PnlPoint(date: iso, pnlUsd: v));
    }
    final weekly = series
        .skip(series.length - 7)
        .map((p) => p.pnlUsd)
        .fold<double>(0.0, (a, b) => a + b);
    final monthly = series
        .map((p) => p.pnlUsd)
        .fold<double>(0.0, (a, b) => a + b);
    return PnlHistory(
      mode: mode ?? 'paper',
      days: days,
      items: series,
      weeklyPnlUsd: weekly,
      monthlyPnlUsd: monthly,
    );
  }

  @override
  Future<List<AgentStat>> fetchAgents() async {
    // Synthesise 15 agents with zero lifecycle counters — preview mode
    // doesn't simulate fired-signal history.
    final names = <String, String>{
      'SR_FLIP_RETEST': 'The Architect',
      'LIQUIDITY_SWEEP_REVERSAL': 'The Counter-Puncher',
      'FAILED_AUCTION_RECLAIM': 'The Reclaimer',
      'QUIET_COMPRESSION_BREAK': 'The Coil Hunter',
      'VOLUME_SURGE_BREAKOUT': 'The Tracker',
      'BREAKDOWN_SHORT': 'The Crusher',
      'FUNDING_EXTREME_SIGNAL': 'The Contrarian',
      'WHALE_MOMENTUM': 'The Whale Hunter',
      'LIQUIDATION_REVERSAL': 'The Cascade Catcher',
      'CONTINUATION_LIQUIDITY_SWEEP': 'The Continuation Specialist',
      'DIVERGENCE_CONTINUATION': 'The Divergence Reader',
      'TREND_PULLBACK_EMA': 'The Pullback Sniper',
      'POST_DISPLACEMENT_CONTINUATION': 'The Aftermath Trader',
      'OPENING_RANGE_BREAKOUT': 'The Range Breaker',
      'MA_CROSS_TREND_SHIFT': 'The Trend Shifter',
    };
    return names.entries
        .map((e) => AgentStat(
              evaluator: e.key,
              setupClass: e.key,
              displayName: e.value,
              enabled: true,
              attempts: 0,
              generated: 0,
              noSignal: 0,
            ))
        .toList();
  }

  @override
  Future<bool> healthCheck() async => true;

  // Pre-TP settings — mock returns a minimal default view; PUT round-trips
  // the partial payload so previews behave realistically without a backend.
  // ``static`` because ``MockRepository`` declares a ``const`` constructor
  // (used at ``app_config.dart:111`` as ``const MockRepository()``); a non-
  // final instance field would make the class not const-constructable.
  static PretpSettings _mockPretp = const PretpSettings(
    enabled: true,
    regimeAllowlist: ['QUIET', 'RANGING', 'VOLATILE'],
    thresholdPct: 0.35,
    atrMultiplier: 0.5,
    feeFloorPct: 0.20,
    minAgeSec: 30,
    maxAgeSec: 1800,
  );

  @override
  Future<PretpSettings> fetchPretpSettings() async => _mockPretp;

  @override
  Future<PretpSettings> updatePretpSettings(PretpSettings partial) async {
    _mockPretp = PretpSettings(
      enabled: partial.enabled ?? _mockPretp.enabled,
      regimeAllowlist: partial.regimeAllowlist ?? _mockPretp.regimeAllowlist,
      setupAllowlist: partial.setupAllowlist ?? _mockPretp.setupAllowlist,
      thresholdPct: partial.thresholdPct ?? _mockPretp.thresholdPct,
      atrMultiplier: partial.atrMultiplier ?? _mockPretp.atrMultiplier,
      feeFloorPct: partial.feeFloorPct ?? _mockPretp.feeFloorPct,
      minAgeSec: partial.minAgeSec ?? _mockPretp.minAgeSec,
      maxAgeSec: partial.maxAgeSec ?? _mockPretp.maxAgeSec,
    );
    return _mockPretp;
  }

  // Auto-trade settings — same static-field pattern as ``_mockPretp`` so the
  // class stays const-constructable.
  static AutoTradeSettings _mockAutoTrade = const AutoTradeSettings(
    mode: 'paper',
    positionSizePct: 2.0,
    leverageCap: 10.0,
    maxConcurrentPositions: 3,
  );

  @override
  Future<AutoTradeSettings> fetchAutoTradeSettings() async => _mockAutoTrade;

  @override
  Future<AutoTradeSettings> updateAutoTradeSettings(
    AutoTradeSettings partial,
  ) async {
    _mockAutoTrade = AutoTradeSettings(
      mode: partial.mode ?? _mockAutoTrade.mode,
      positionSizePct:
          partial.positionSizePct ?? _mockAutoTrade.positionSizePct,
      leverageCap: partial.leverageCap ?? _mockAutoTrade.leverageCap,
      maxConcurrentPositions: partial.maxConcurrentPositions ??
          _mockAutoTrade.maxConcurrentPositions,
    );
    return _mockAutoTrade;
  }

  // Per-user overrides (Phase 2) — single in-memory store covers all
  // mocked users since the offline mode doesn't have a real user_id.
  // ``using_defaults`` flips off as soon as the user touches anything.
  static PretpSettings _mockUserPretp = const PretpSettings(usingDefaults: true);
  static AutoTradeSettings _mockUserAutoTrade =
      const AutoTradeSettings(usingDefaults: true);

  @override
  Future<PretpSettings> fetchUserPretpSettings() async => _mockUserPretp;

  @override
  Future<PretpSettings> updateUserPretpSettings(PretpSettings partial) async {
    _mockUserPretp = PretpSettings(
      enabled: partial.enabled ?? _mockUserPretp.enabled ?? _mockPretp.enabled,
      regimeAllowlist:
          partial.regimeAllowlist ?? _mockUserPretp.regimeAllowlist,
      setupAllowlist:
          partial.setupAllowlist ?? _mockUserPretp.setupAllowlist,
      thresholdPct: partial.thresholdPct ??
          _mockUserPretp.thresholdPct ??
          _mockPretp.thresholdPct,
      grabFraction: partial.grabFraction ??
          _mockUserPretp.grabFraction ??
          _mockPretp.grabFraction,
      atrMultiplier: partial.atrMultiplier ??
          _mockUserPretp.atrMultiplier ??
          _mockPretp.atrMultiplier,
      feeFloorPct: partial.feeFloorPct ??
          _mockUserPretp.feeFloorPct ??
          _mockPretp.feeFloorPct,
      minAgeSec:
          partial.minAgeSec ?? _mockUserPretp.minAgeSec ?? _mockPretp.minAgeSec,
      maxAgeSec:
          partial.maxAgeSec ?? _mockUserPretp.maxAgeSec ?? _mockPretp.maxAgeSec,
      protectManualEntries: partial.protectManualEntries ??
          _mockUserPretp.protectManualEntries ??
          _mockPretp.protectManualEntries,
      usingDefaults: false,
    );
    return _mockUserPretp;
  }

  @override
  Future<PretpSettings> resetUserPretpSettings() async {
    _mockUserPretp = const PretpSettings(usingDefaults: true);
    return _mockUserPretp;
  }

  @override
  Future<AutoTradeSettings> fetchUserAutoTradeSettings() async =>
      _mockUserAutoTrade;

  @override
  Future<AutoTradeSettings> updateUserAutoTradeSettings(
    AutoTradeSettings partial,
  ) async {
    _mockUserAutoTrade = AutoTradeSettings(
      mode: partial.mode ?? _mockUserAutoTrade.mode ?? _mockAutoTrade.mode,
      positionSizePct: partial.positionSizePct ??
          _mockUserAutoTrade.positionSizePct ??
          _mockAutoTrade.positionSizePct,
      leverageCap: partial.leverageCap ??
          _mockUserAutoTrade.leverageCap ??
          _mockAutoTrade.leverageCap,
      maxConcurrentPositions: partial.maxConcurrentPositions ??
          _mockUserAutoTrade.maxConcurrentPositions ??
          _mockAutoTrade.maxConcurrentPositions,
      usingDefaults: false,
    );
    return _mockUserAutoTrade;
  }

  // Per-user invalidation overrides (OWNER_BRIEF B17).  Mock store mirrors
  // the ``_mockUserPretp`` pattern — single in-memory record, ``usingDefaults``
  // flips off on first touch, fields cascade through engine defaults.
  static InvalidationSettings _mockUserInvalidation = const InvalidationSettings(
    usingDefaults: true,
  );
  // Engine defaults baseline used by the mock when no override is set — keeps
  // the mocked Settings page rendering live-looking values until a real backend
  // call hydrates them.
  static const InvalidationSettings _mockInvalidationDefaults =
      InvalidationSettings(
    mode: 'standard',
    trailingMfeRThreshold: 0.30,
    trailingRetracePct: 0.50,
    emaCrossoverEnabled: true,
    regimeShiftEnabled: true,
    trailingKillEnabled: false,
    momentumThresholdMult: 1.0,
  );

  @override
  Future<InvalidationSettings> fetchUserInvalidationSettings() async =>
      _mockUserInvalidation;

  @override
  Future<InvalidationSettings> updateUserInvalidationSettings(
    InvalidationSettings partial,
  ) async {
    _mockUserInvalidation = InvalidationSettings(
      mode: partial.mode ??
          _mockUserInvalidation.mode ??
          _mockInvalidationDefaults.mode,
      minAgeSec: partial.minAgeSec ?? _mockUserInvalidation.minAgeSec,
      momentumThresholdMult: partial.momentumThresholdMult ??
          _mockUserInvalidation.momentumThresholdMult ??
          _mockInvalidationDefaults.momentumThresholdMult,
      emaCrossoverEnabled: partial.emaCrossoverEnabled ??
          _mockUserInvalidation.emaCrossoverEnabled ??
          _mockInvalidationDefaults.emaCrossoverEnabled,
      regimeShiftEnabled: partial.regimeShiftEnabled ??
          _mockUserInvalidation.regimeShiftEnabled ??
          _mockInvalidationDefaults.regimeShiftEnabled,
      trailingKillEnabled: partial.trailingKillEnabled ??
          _mockUserInvalidation.trailingKillEnabled ??
          _mockInvalidationDefaults.trailingKillEnabled,
      trailingMfeRThreshold: partial.trailingMfeRThreshold ??
          _mockUserInvalidation.trailingMfeRThreshold ??
          _mockInvalidationDefaults.trailingMfeRThreshold,
      trailingRetracePct: partial.trailingRetracePct ??
          _mockUserInvalidation.trailingRetracePct ??
          _mockInvalidationDefaults.trailingRetracePct,
      usingDefaults: false,
    );
    return _mockUserInvalidation;
  }

  @override
  Future<InvalidationSettings> resetUserInvalidationSettings() async {
    _mockUserInvalidation = const InvalidationSettings(usingDefaults: true);
    return _mockUserInvalidation;
  }

  // Profile (Phase 3) — in mock mode we keep a tiny static profile so
  // SignupPage previews work offline.  ``needsOnboarding`` flips false
  // once ``updateProfile`` lands a display name + ``acceptTerms``.
  static Profile _mockProfile = const Profile(
    userId: 0,
    phoneE164: '+10000000000',
    tier: 'free',
    needsOnboarding: true,
  );

  @override
  Future<Profile> fetchProfile() async => _mockProfile;

  @override
  Future<Profile> updateProfile(
    Profile partial, {
    bool acceptTerms = false,
  }) async {
    final stillNeeds = _mockProfile.needsOnboarding &&
        !((partial.displayName != null) && acceptTerms);
    _mockProfile = Profile(
      userId: _mockProfile.userId,
      phoneE164: _mockProfile.phoneE164,
      tier: _mockProfile.tier,
      paidUntil: _mockProfile.paidUntil,
      displayName: partial.displayName ?? _mockProfile.displayName,
      countryCode: partial.countryCode ?? _mockProfile.countryCode,
      timezone: partial.timezone ?? _mockProfile.timezone,
      currency: partial.currency ?? _mockProfile.currency,
      termsAcceptedAt:
          acceptTerms ? DateTime.now().toIso8601String() : _mockProfile.termsAcceptedAt,
      onboardedAt: stillNeeds
          ? _mockProfile.onboardedAt
          : (_mockProfile.onboardedAt ?? DateTime.now().toIso8601String()),
      needsOnboarding: stillNeeds,
    );
    return _mockProfile;
  }

  // ---- Paper trade ledger -----------------------------------------------
  //
  // 15 sample records spanning the distribution the owner asked for so the
  // PaperTradesPage list + detail surfaces render realistically in offline
  // mode.  Static so ``const MockRepository()`` stays valid; mutable so
  // ``resetPaperBalance`` can wipe the ledger and the page sees the empty
  // state without a process restart.
  static List<TradeRecord> _mockTrades = _buildMockTrades();

  static List<TradeRecord> _buildMockTrades() {
    final now = DateTime.now().toUtc();
    DateTime ago({int days = 0, int hours = 0, int minutes = 0}) => now.subtract(
        Duration(days: days, hours: hours, minutes: minutes));
    // Helpers — keep math close so a glance at one row tells the reader
    // entry/qty/leverage drive notional/margin which drives ROI.
    TradeRecord rec({
      required String signalId,
      required String symbol,
      required String side,
      required double entry,
      required double qty,
      required double leverage,
      required double positionSizePct,
      required DateTime createdAt,
      String? closeReason,
      double? closePrice,
      double? netPnlUsd,
      double? feesUsd,
      double? roiPctOnMargin,
      DateTime? closedAt,
      List<PartialFill> partialFills = const [],
    }) {
      final notional = entry * qty;
      final margin = notional / leverage;
      final gross =
          netPnlUsd != null && feesUsd != null ? netPnlUsd + feesUsd : null;
      return TradeRecord(
        signalId: signalId,
        symbol: symbol,
        side: side,
        entry: entry,
        qty: qty,
        leverage: leverage,
        positionSizePct: positionSizePct,
        notionalUsd: notional,
        marginUsd: margin,
        partialFills: partialFills,
        createdAt: createdAt,
        closeReason: closeReason,
        closePrice: closePrice,
        grossPnlUsd: gross,
        feesUsd: feesUsd,
        netPnlUsd: netPnlUsd,
        roiPctOnMargin: roiPctOnMargin,
        closedAt: closedAt,
      );
    }

    return <TradeRecord>[
      // 2 open trades — closedAt null, no PnL fields.
      rec(
        signalId: 'SIG-2901',
        symbol: 'ETHUSDT',
        side: 'long',
        entry: 2329.0,
        qty: 0.043,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(minutes: 18),
      ),
      rec(
        signalId: 'SIG-2900',
        symbol: 'WLDUSDT',
        side: 'short',
        entry: 2.412,
        qty: 41.5,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(hours: 2, minutes: 4),
      ),
      // 3 PROFIT_LOCKED — modest to strong wins.
      rec(
        signalId: 'SIG-2899',
        symbol: 'BTCUSDT',
        side: 'long',
        entry: 78240.0,
        qty: 0.00128,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(hours: 5),
        closeReason: 'tp3',
        closePrice: 79644.0,
        netPnlUsd: 17.84,
        feesUsd: 0.40,
        roiPctOnMargin: 17.8,
        closedAt: ago(hours: 3, minutes: 20),
        partialFills: [
          PartialFill(
            tpLevel: 1,
            fraction: 0.33,
            fillPrice: 78680.0,
            pnlUsd: 1.86,
            feeUsd: 0.13,
            ts: ago(hours: 4, minutes: 30),
          ),
          PartialFill(
            tpLevel: 2,
            fraction: 0.33,
            fillPrice: 79050.0,
            pnlUsd: 3.42,
            feeUsd: 0.13,
            ts: ago(hours: 4),
          ),
          PartialFill(
            tpLevel: 3,
            fraction: 0.34,
            fillPrice: 79644.0,
            pnlUsd: 12.56,
            feeUsd: 0.14,
            ts: ago(hours: 3, minutes: 20),
          ),
        ],
      ),
      rec(
        signalId: 'SIG-2898',
        symbol: 'SOLUSDT',
        side: 'long',
        entry: 142.85,
        qty: 0.700,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 1, hours: 2),
        closeReason: 'tp2',
        closePrice: 146.40,
        netPnlUsd: 24.10,
        feesUsd: 0.40,
        roiPctOnMargin: 24.1,
        closedAt: ago(days: 1),
        partialFills: [
          PartialFill(
            tpLevel: 1,
            fraction: 0.50,
            fillPrice: 144.50,
            pnlUsd: 5.78,
            feeUsd: 0.20,
            ts: ago(days: 1, hours: 1, minutes: 30),
          ),
          PartialFill(
            tpLevel: 2,
            fraction: 0.50,
            fillPrice: 146.40,
            pnlUsd: 18.32,
            feeUsd: 0.20,
            ts: ago(days: 1),
          ),
        ],
      ),
      rec(
        signalId: 'SIG-2897',
        symbol: 'INJUSDT',
        side: 'long',
        entry: 24.18,
        qty: 4.15,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 1, hours: 14),
        closeReason: 'tp1',
        closePrice: 24.40,
        netPnlUsd: 8.80,
        feesUsd: 0.36,
        roiPctOnMargin: 8.8,
        closedAt: ago(days: 1, hours: 13),
        partialFills: [
          PartialFill(
            tpLevel: 1,
            fraction: 1.0,
            fillPrice: 24.40,
            pnlUsd: 9.16,
            feeUsd: 0.36,
            ts: ago(days: 1, hours: 13),
          ),
        ],
      ),
      // 9 BREAKEVEN_EXIT — small +/− after fees.  Mix of close reasons.
      rec(
        signalId: 'SIG-2896',
        symbol: 'BNBUSDT',
        side: 'long',
        entry: 612.40,
        qty: 0.163,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 2, hours: 1),
        closeReason: 'pre_tp_grab',
        closePrice: 612.85,
        netPnlUsd: 0.21,
        feesUsd: 0.20,
        roiPctOnMargin: 0.2,
        closedAt: ago(days: 2),
      ),
      rec(
        signalId: 'SIG-2895',
        symbol: 'TIAUSDT',
        side: 'short',
        entry: 4.812,
        qty: 20.78,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 2, hours: 3),
        closeReason: 'pre_tp_grab',
        closePrice: 4.803,
        netPnlUsd: -0.32,
        feesUsd: 0.20,
        roiPctOnMargin: -0.3,
        closedAt: ago(days: 2, hours: 2, minutes: 12),
      ),
      rec(
        signalId: 'SIG-2894',
        symbol: 'ETHUSDT',
        side: 'short',
        entry: 2338.0,
        qty: 0.043,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 2, hours: 6),
        closeReason: 'invalidated',
        closePrice: 2337.6,
        netPnlUsd: -0.18,
        feesUsd: 0.20,
        roiPctOnMargin: -0.2,
        closedAt: ago(days: 2, hours: 5, minutes: 40),
      ),
      rec(
        signalId: 'SIG-2893',
        symbol: 'WLDUSDT',
        side: 'long',
        entry: 2.404,
        qty: 41.6,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 3, hours: 1),
        closeReason: 'pre_tp_grab',
        closePrice: 2.409,
        netPnlUsd: 0.08,
        feesUsd: 0.20,
        roiPctOnMargin: 0.1,
        closedAt: ago(days: 3),
      ),
      rec(
        signalId: 'SIG-2892',
        symbol: 'BTCUSDT',
        side: 'short',
        entry: 78130.0,
        qty: 0.00128,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 3, hours: 4),
        closeReason: 'expired',
        closePrice: 78165.0,
        netPnlUsd: -0.24,
        feesUsd: 0.20,
        roiPctOnMargin: -0.2,
        closedAt: ago(days: 3, hours: 3),
      ),
      rec(
        signalId: 'SIG-2891',
        symbol: 'SOLUSDT',
        side: 'short',
        entry: 144.20,
        qty: 0.693,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 3, hours: 8),
        closeReason: 'pre_tp_grab',
        closePrice: 143.90,
        netPnlUsd: 0.15,
        feesUsd: 0.20,
        roiPctOnMargin: 0.2,
        closedAt: ago(days: 3, hours: 7, minutes: 18),
      ),
      rec(
        signalId: 'SIG-2890',
        symbol: 'INJUSDT',
        side: 'short',
        entry: 24.40,
        qty: 4.10,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 4, hours: 2),
        closeReason: 'invalidated',
        closePrice: 24.42,
        netPnlUsd: -0.28,
        feesUsd: 0.20,
        roiPctOnMargin: -0.3,
        closedAt: ago(days: 4, hours: 1, minutes: 30),
      ),
      rec(
        signalId: 'SIG-2889',
        symbol: 'BNBUSDT',
        side: 'short',
        entry: 625.10,
        qty: 0.160,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 4, hours: 6),
        closeReason: 'pre_tp_grab',
        closePrice: 624.65,
        netPnlUsd: 0.18,
        feesUsd: 0.20,
        roiPctOnMargin: 0.2,
        closedAt: ago(days: 4, hours: 5),
      ),
      rec(
        signalId: 'SIG-2888',
        symbol: 'TIAUSDT',
        side: 'long',
        entry: 4.795,
        qty: 20.85,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 5),
        closeReason: 'cancelled',
        closePrice: 4.795,
        netPnlUsd: -0.20,
        feesUsd: 0.20,
        roiPctOnMargin: -0.2,
        closedAt: ago(days: 4, hours: 23, minutes: 40),
      ),
      // 4 INVALIDATED — modest negatives.
      rec(
        signalId: 'SIG-2887',
        symbol: 'WLDUSDT',
        side: 'long',
        entry: 2.420,
        qty: 41.3,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 5, hours: 3),
        closeReason: 'invalidated',
        closePrice: 2.401,
        netPnlUsd: -2.10,
        feesUsd: 0.20,
        roiPctOnMargin: -2.1,
        closedAt: ago(days: 5, hours: 2),
      ),
      rec(
        signalId: 'SIG-2886',
        symbol: 'ETHUSDT',
        side: 'short',
        entry: 2342.0,
        qty: 0.043,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 5, hours: 8),
        closeReason: 'invalidated',
        closePrice: 2349.0,
        netPnlUsd: -3.20,
        feesUsd: 0.20,
        roiPctOnMargin: -3.2,
        closedAt: ago(days: 5, hours: 7, minutes: 4),
      ),
      rec(
        signalId: 'SIG-2885',
        symbol: 'SOLUSDT',
        side: 'long',
        entry: 141.85,
        qty: 0.705,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 6, hours: 1),
        closeReason: 'invalidated',
        closePrice: 141.20,
        netPnlUsd: -3.84,
        feesUsd: 0.20,
        roiPctOnMargin: -3.8,
        closedAt: ago(days: 6),
      ),
      rec(
        signalId: 'SIG-2884',
        symbol: 'INJUSDT',
        side: 'short',
        entry: 24.55,
        qty: 4.07,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 6, hours: 4),
        closeReason: 'invalidated',
        closePrice: 24.78,
        netPnlUsd: -3.10,
        feesUsd: 0.20,
        roiPctOnMargin: -3.1,
        closedAt: ago(days: 6, hours: 3, minutes: 20),
      ),
      // 2 SL_HIT — larger negatives.
      rec(
        signalId: 'SIG-2883',
        symbol: 'BTCUSDT',
        side: 'long',
        entry: 77900.0,
        qty: 0.00129,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 6, hours: 14),
        closeReason: 'sl_hit',
        closePrice: 77100.0,
        netPnlUsd: -8.30,
        feesUsd: 0.40,
        roiPctOnMargin: -8.3,
        closedAt: ago(days: 6, hours: 12),
      ),
      rec(
        signalId: 'SIG-2882',
        symbol: 'BNBUSDT',
        side: 'short',
        entry: 612.80,
        qty: 0.163,
        leverage: 10.0,
        positionSizePct: 2.0,
        createdAt: ago(days: 7, hours: 1),
        closeReason: 'sl_hit',
        closePrice: 625.30,
        netPnlUsd: -12.40,
        feesUsd: 0.40,
        roiPctOnMargin: -12.4,
        closedAt: ago(days: 7),
      ),
    ];
  }

  @override
  Future<TradeListResponse> fetchTrades({
    String mode = 'paper',
    int limit = 50,
    int offset = 0,
    String? sinceTs,
    String? symbol,
    bool includeOpen = false,
  }) async {
    // Filter pass mirrors the engine's behaviour so the page paginates
    // against the same total it would see in live mode.  ``includeOpen``
    // is engine-side concept (rows without ``closed_at`` are filtered by
    // default); the mock fixture already only contains closed rows, so
    // the flag is a no-op here.  The HTTP impl forwards it to the server.
    final filtered = _mockTrades.where((t) {
      if (symbol != null && symbol.isNotEmpty && t.symbol != symbol) {
        return false;
      }
      if (sinceTs != null && sinceTs.isNotEmpty) {
        final since = DateTime.tryParse(sinceTs);
        if (since != null && t.createdAt.isBefore(since)) return false;
      }
      return true;
    }).toList();
    final slice = filtered.skip(offset).take(limit).toList();
    return TradeListResponse(items: slice, total: filtered.length);
  }

  @override
  Future<PaperResetResponse> resetPaperBalance() async {
    _mockTrades = <TradeRecord>[];
    return PaperResetResponse(
      resetAt: DateTime.now().toUtc(),
      startingEquityUsd: 1000.0,
    );
  }

  @override
  Future<PaperResetMineResponse> resetMinePaperHistory() async {
    _mockTrades = <TradeRecord>[];
    return PaperResetMineResponse(newStartedAt: DateTime.now().toUtc());
  }

  @override
  Future<bool> resumeMineAutoTrade() async {
    // Mock mode has no real engine pause-state — successful resume
    // every time so the UI flow can be exercised in dev builds.
    return true;
  }

  @override
  Future<BinanceConnectSuccess> connectBinanceServerSide({
    required String apiKey,
    required String apiSecret,
  }) async {
    // MockRepository fakes a successful connect — useful for UI dev
    // without a live engine.  Returns the same shape as a real engine
    // response.  Validation flags all-true so the success-state UI
    // is exercisable in mock mode.
    return BinanceConnectSuccess(
      keyPublicIdFirst8: apiKey.length >= 8 ? apiKey.substring(0, 8) : apiKey,
      withdrawDisabledOk: true,
      futuresEnabledOk: true,
      ipWhitelistOk: true,
    );
  }

  @override
  Future<AutoTradeUserStatus> getAutoTradeUserStatus() async {
    // Mock: globally enabled, user not disabled.  Exercises the
    // happy-path UI (no banner).  Tests that need the banner to
    // render pass through HttpRepository with a mock api_client.
    return const AutoTradeUserStatus(
      autoTradeGloballyEnabled: true,
      autoTradeUserDisabled: false,
    );
  }

  @override
  Future<BinanceConnectStatus> fetchBinanceConnectStatus() async {
    // Mock: not connected — same surface a fresh user would see in
    // live mode.  Exercises the connect-form rendering branch.
    return BinanceConnectStatus.notConnected;
  }

  @override
  Future<void> disconnectBinanceServerSide() async {
    // Mock: no-op; idempotent disconnect.
  }

  @override
  Future<AutoTradeRuntimeStatus> getAutoTradeRuntimeStatus() async {
    // Mock: all gates configured + green, exercising the armed-card
    // happy-path branch in offline dev.
    return const AutoTradeRuntimeStatus(
      autoTradeGloballyEnabled: true,
      autoTradeUserDisabled: false,
      binanceKeyConnected: true,
      userMode: 'live',
      allowedSymbols: ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'BNBUSDT'],
      effectiveAllowedSymbols: [
        'BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'BNBUSDT',
      ],
      allowedPaths: [
        'SR_FLIP_RETEST',
        'LIQUIDITY_SWEEP_REVERSAL',
        'DIVERGENCE_CONTINUATION',
        'FAILED_AUCTION_RECLAIM',
        'VOLUME_SURGE_BREAKOUT',
        'BREAKDOWN_SHORT',
        'MOVER_TREND_PULLBACK',
      ],
      regimeOptions: ['TRENDING', 'RANGING', 'CHOPPY'],
      armed: true,
    );
  }

  // In-memory per-symbol management map for offline/preview mode.
  // ``static`` so it can hold mutable state in the const MockRepository
  // (mirrors ``_mockUserPretp``).
  static final Map<String, String> _mockSymbolManagement = <String, String>{};

  @override
  Future<Map<String, String>> fetchSymbolManagement() async =>
      Map<String, String>.from(_mockSymbolManagement);

  @override
  Future<Map<String, String>> setSymbolManagement(
    String symbol, String mode,
  ) async {
    final sym = symbol.toUpperCase();
    if (mode == 'full') {
      _mockSymbolManagement.remove(sym);
    } else {
      _mockSymbolManagement[sym] = mode;
    }
    return Map<String, String>.from(_mockSymbolManagement);
  }

  @override
  Future<PlayVerifyResult> verifyPlayPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    // Mock/preview: pretend the purchase verified and granted paid.
    return PlayVerifyResult(
      ok: true,
      tier: 'paid',
      paidUntil: DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
      subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
    );
  }

  @override
  Future<List<ServerSidePosition>> getAutoTradePositions() async {
    // Mock: no open positions.  UI renders the empty-state copy
    // ("Auto-trade armed — waiting for the next whitelisted signal").
    return const <ServerSidePosition>[];
  }

  @override
  Future<List<DispatchEvent>> getRecentDispatchEvents({int limit = 20}) async {
    // Mock: one placed + one rejected (margin-insufficient) so the
    // Trade-tab Recent Activity card has visual content while
    // running against the fake repository in widget tests and
    // local dev without a connected Binance key.
    final now = DateTime.now().toUtc();
    return [
      DispatchEvent(
        eventId: 'mock-placed-1',
        signalId: 'sig-1',
        symbol: 'BTCUSDT',
        direction: 'LONG',
        outcome: 'placed',
        timestamp: now.subtract(const Duration(minutes: 3)),
        entryPrice: 29000.0,
        totalQty: 0.017,
      ),
      DispatchEvent(
        eventId: 'mock-rejected-1',
        signalId: 'sig-2',
        symbol: 'PROMUSDT',
        direction: 'SHORT',
        outcome: 'rejected',
        timestamp: now.subtract(const Duration(minutes: 11)),
        entryPrice: 0.1278,
        totalQty: 0.0,
        rejectClass: 'OrderRejectedByBinance',
        rejectDetail: 'Binance returned 400 (code=-2019 msg=\'Margin is insufficient.\')',
        rejectBinanceCode: -2019,
        rejectBinanceMsg: 'Margin is insufficient.',
      ),
    ];
  }

  @override
  Future<PaperCloseAllResponse> closeAllPaperPositions() async {
    // The mock fixture never has live open positions, so this is a
    // no-op that returns zero counts.  The UI flow is exercised against
    // the HTTP impl in the real app.
    return const PaperCloseAllResponse(
      closedCount: 0,
      realisedPnlTotal: 0.0,
    );
  }

  @override
  Future<RegionInfo> fetchRegion() async {
    // Mock: India, not blocked.  Matches the most common dev / QA
    // case (Indian-owner test devices).  Switch this constant when
    // exercising the blocked-region UI flow in widget tests.
    return const RegionInfo(
      countryCode: 'IN',
      source: 'cf-header',
      isBlocked: false,
      blockedRegions: ['BD', 'CN', 'US'],
    );
  }

  @override
  Future<void> deleteAccount() async {
    // Mock: no-op.  The HTTP impl drives the real deletion; the
    // mock just lets widget tests + offline dev hit the same code
    // path without a network round-trip.
  }
}

// ---------------------------------------------------------------------------
// HttpRepository — talks to FastAPI backend.
// ---------------------------------------------------------------------------

class HttpRepository implements LuminRepository {
  HttpRepository(this.client);

  final LuminApiClient client;

  /// Per-instance SWR cache.  In-memory only — survives tab switches +
  /// lifecycle pauses but not cold start.  AppConfigScope drops the
  /// whole HttpRepository on Live↔Mock toggle / sign-out so the cache
  /// dies with it; no explicit ``clear()`` plumbing required.
  final SwrCache _swr = SwrCache();

  @override
  bool get isLive => true;

  String _signalsKey({
    required String status,
    required int limit,
    String? setupClass,
  }) =>
      'signals:$status:$limit:${setupClass ?? "_"}';

  /// Override the abstract default so ``/api/signals`` traffic dedups
  /// across AutoTradeWatcher + Pulse + Signals subscribers — they all
  /// see the same cached payload for the TTL window instead of each
  /// firing a separate round-trip.
  @override
  Stream<List<MockSignal>> watchSignals({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  }) {
    final key = _signalsKey(status: status, limit: limit, setupClass: setupClass);
    return _swr.watch<List<MockSignal>>(
      key,
      fetch: () => fetchSignals(status: status, limit: limit, setupClass: setupClass),
      ttl: const Duration(seconds: 30),
      persistKey: 'swr_signals_${status}_$limit',
      toJson: (items) => jsonEncode(items.map((s) => s.toMap()).toList()),
      fromJson: (str) {
        try {
          final list = jsonDecode(str) as List;
          return list
              .map((j) => MockSignal.fromMap(j as Map<String, dynamic>))
              .toList();
        } catch (_) {
          return null;
        }
      },
    );
  }

  @override
  void invalidateSignalsCache({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  }) {
    _swr.invalidate(
      _signalsKey(status: status, limit: limit, setupClass: setupClass),
    );
  }

  static const _kPulseBundleKey = 'pulse_bundle';
  static const _kTradeEngineKey = 'trade_engine_snapshot';
  static const _kAgentsKey = 'agents';
  static const _kAutoTradeUserStatusKey = 'auto_trade_user_status';
  static const _kAutoTradeRuntimeStatusKey = 'auto_trade_runtime_status';
  static const _kAutoTradePositionsKey = 'auto_trade_positions';
  static const _kUserPnlSnapshotKey = 'user_pnl_snapshot';
  static String _recentDispatchEventsKey(int limit) =>
      'recent_dispatch_events:$limit';
  static String _paperTradesFirstPageKey(int limit) =>
      'paper_trades_first_page:$limit';

  /// SWR-cached bundle.  Single cache entry for the whole bundle —
  /// tab re-entry within TTL renders synchronously from cache while
  /// a background refresh fires.  Concurrent subscribers (the user
  /// scrolling around + pull-to-refresh) share one fetch via the
  /// SwrCache's in-flight dedup.
  @override
  Stream<PulseBundle> watchPulseBundle() {
    return _swr.watch<PulseBundle>(
      _kPulseBundleKey,
      fetch: () => assemblePulseBundle(this),
    );
  }

  @override
  void invalidatePulseBundleCache() {
    _swr.invalidate(_kPulseBundleKey);
  }

  /// Phase 2c — SWR for the Trade page's engine slice.  Binance slice
  /// stays page-local (needs user-context for the secure-storage
  /// key lookup); only the engine side benefits from caching.
  @override
  Stream<TradeEngineSnapshot> watchTradeEngineSnapshot() {
    return _swr.watch<TradeEngineSnapshot>(
      _kTradeEngineKey,
      fetch: () => assembleTradeEngineSnapshot(this),
    );
  }

  @override
  void invalidateTradeEngineSnapshotCache() {
    _swr.invalidate(_kTradeEngineKey);
  }

  // ---- Per-tab SWR-cached watches (2026-05-22) -------------------------
  //
  // Wraps the four user-scoped + one engine-global fetches that
  // TradePage used to hit directly in `didChangeDependencies`.
  // Caching here lets `prewarmCaches` warm all of them at sign-in so
  // the first tap on the Trade or Agents tab is instant instead of
  // sequentially waiting on 4 fresh HTTP round-trips.

  @override
  Stream<List<AgentStat>> watchAgents() {
    return _swr.watch<List<AgentStat>>(
      _kAgentsKey,
      fetch: () => fetchAgents(),
    );
  }

  @override
  void invalidateAgentsCache() => _swr.invalidate(_kAgentsKey);

  @override
  Stream<TradeListResponse> watchPaperTradesFirstPage({int limit = 50}) {
    return _swr.watch<TradeListResponse>(
      _paperTradesFirstPageKey(limit),
      fetch: () => fetchTrades(
        mode: 'paper', limit: limit, offset: 0, includeOpen: true,
      ),
      ttl: const Duration(seconds: 30),
      persistKey: 'swr_paper_trades_$limit',
      toJson: (r) => r.toJsonString(),
      fromJson: TradeListResponse.fromJsonString,
    );
  }

  @override
  void invalidatePaperTradesCache({int limit = 50}) =>
      _swr.invalidate(_paperTradesFirstPageKey(limit));

  @override
  Stream<AutoTradeUserStatus> watchAutoTradeUserStatus() {
    return _swr.watch<AutoTradeUserStatus>(
      _kAutoTradeUserStatusKey,
      fetch: () => getAutoTradeUserStatus(),
    );
  }

  @override
  void invalidateAutoTradeUserStatusCache() =>
      _swr.invalidate(_kAutoTradeUserStatusKey);

  @override
  Stream<AutoTradeRuntimeStatus> watchAutoTradeRuntimeStatus() {
    return _swr.watch<AutoTradeRuntimeStatus>(
      _kAutoTradeRuntimeStatusKey,
      fetch: () => getAutoTradeRuntimeStatus(),
    );
  }

  @override
  void invalidateAutoTradeRuntimeStatusCache() =>
      _swr.invalidate(_kAutoTradeRuntimeStatusKey);

  @override
  Stream<List<ServerSidePosition>> watchAutoTradePositions() {
    return _swr.watch<List<ServerSidePosition>>(
      _kAutoTradePositionsKey,
      fetch: () => getAutoTradePositions(),
    );
  }

  @override
  void invalidateAutoTradePositionsCache() {
    _swr.invalidate(_kAutoTradePositionsKey);
    // UserPnl reads from positions — invalidate both together so the
    // Pulse card refreshes alongside the Trade tab on the same pull.
    _swr.invalidate(_kUserPnlSnapshotKey);
  }

  @override
  Stream<List<DispatchEvent>> watchRecentDispatchEvents({int limit = 20}) {
    return _swr.watch<List<DispatchEvent>>(
      _recentDispatchEventsKey(limit),
      fetch: () => getRecentDispatchEvents(limit: limit),
    );
  }

  @override
  void invalidateRecentDispatchEventsCache({int limit = 20}) =>
      _swr.invalidate(_recentDispatchEventsKey(limit));

  @override
  Stream<UserPnlSnapshot> watchUserPnlSnapshot() {
    return _swr.watch<UserPnlSnapshot>(
      _kUserPnlSnapshotKey,
      fetch: () => assembleUserPnlSnapshot(this),
    );
  }

  @override
  void invalidateUserPnlSnapshotCache() =>
      _swr.invalidate(_kUserPnlSnapshotKey);

  /// Pre-warm SWR caches in the background.  Called by the auth gate
  /// the moment a user becomes signed-in so the Live + Trade tabs
  /// land already-warm by the time the user navigates to them
  /// (typically ~1-3 seconds after sign-in completes).
  ///
  /// Returns immediately.  Each fetch runs concurrently in its own
  /// microtask via the SwrCache's existing in-flight dedup — if the
  /// user happens to open the Live tab during the prewarm, they
  /// share the same fetch and don't issue a duplicate request.
  ///
  /// All errors swallowed: the same fetch will retry when the UI
  /// actually subscribes if it fails here.  Pre-warm is a UX
  /// optimisation, never a correctness gate.
  @override
  Future<void> prewarmCaches() async {
    // PulseBundle — Live tab landing surface (8+ sub-fetches in
    // assemblePulseBundle).  Fire-and-forget in a microtask.
    Future.microtask(() async {
      try {
        await _swr
            .watch<PulseBundle>(
              _kPulseBundleKey,
              fetch: () => assemblePulseBundle(this),
            )
            .last;
      } catch (_) {
        // Swallow — the UI's own subscribe will retry.
      }
    });

    // TradeEngineSnapshot — Trade tab engine slice.
    Future.microtask(() async {
      try {
        await _swr
            .watch<TradeEngineSnapshot>(
              _kTradeEngineKey,
              fetch: () => assembleTradeEngineSnapshot(this),
            )
            .last;
      } catch (_) {
        // Swallow.
      }
    });

    // Signals list — first tap on the Signals tab previously waited
    // for a cold network RTT (200-800ms+ depending on engine state +
    // geo).  Same key the page subscribes to (`signals:all:100:_`)
    // and the PulseBundle reuses via `assemblePulseBundle`, so the
    // dedup hands all three consumers (Pulse bundle, Signals page,
    // AutoTradeWatcher) one shared cache entry.
    Future.microtask(() async {
      try {
        await watchSignals(status: 'all', limit: 100).last;
      } catch (_) {
        // Swallow.
      }
    });

    // Agents — engine-global agent stats list.  First tap on Agents
    // previously waited for a cold round-trip; the prewarm makes
    // the list cards land instantly when the user navigates.
    Future.microtask(() async {
      try {
        await watchAgents().last;
      } catch (_) {}
    });

    // Trade tab — four parallel per-user fetches that previously fired
    // sequentially in `didChangeDependencies` on first tab visit.
    // Prewarming them in parallel here shifts that 4×RTT delay off
    // the critical path (the user's first Trade tap).  Each is
    // user-scoped via Firebase ID token; the SwrCache.clear() on
    // sign-out keeps them from bleeding across identities.
    Future.microtask(() async {
      try {
        await watchAutoTradeUserStatus().last;
      } catch (_) {}
    });
    Future.microtask(() async {
      try {
        await watchAutoTradeRuntimeStatus().last;
      } catch (_) {}
    });
    Future.microtask(() async {
      try {
        await watchAutoTradePositions().last;
      } catch (_) {}
    });
    Future.microtask(() async {
      try {
        await watchRecentDispatchEvents(limit: 20).last;
      } catch (_) {}
    });

    // Per-user PnL snapshot — drives the Pulse "TODAY'S P&L" card.
    // Shares the underlying `getAutoTradePositions` fetch with the
    // Trade tab prewarm above (SwrCache in-flight dedup hands them
    // the same network call).
    Future.microtask(() async {
      try {
        await watchUserPnlSnapshot().last;
      } catch (_) {}
    });

    // Paper trades first page — Trade tab Paper section shows instantly
    // on return visit instead of re-loading from the network.
    Future.microtask(() async {
      try {
        await watchPaperTradesFirstPage(limit: 50).last;
      } catch (_) {}
    });

    // RegionInfo — auto-trade gate.  fetchRegion already soft-fails
    // internally (returns "unknown" + not-blocked on any error), so
    // the try/catch here is purely defensive.
    Future.microtask(() async {
      try {
        await fetchRegion();
      } catch (_) {
        // Swallow.
      }
    });
  }

  @override
  Future<MockEngineSnapshot> fetchPulse() async {
    final j = (await client.get('/api/pulse')) as Map<String, dynamic>;
    return MockEngineSnapshot(
      status: j['status'] as String? ?? 'Healthy',
      regime: j['regime'] as String? ?? 'RANGING',
      regimePctTrending:
          (j['regime_pct_trending'] as num?)?.toDouble() ?? 0.0,
      todayPnlUsd: (j['today_pnl_usd'] as num?)?.toDouble() ?? 0.0,
      todayPnlPct: (j['today_pnl_pct'] as num?)?.toDouble() ?? 0.0,
      dailyLossBudgetUsd:
          (j['daily_loss_budget_usd'] as num?)?.toDouble() ?? 0.0,
      dailyLossUsedUsd:
          (j['daily_loss_used_usd'] as num?)?.toDouble() ?? 0.0,
      openPositions: (j['open_positions'] as num?)?.toInt() ?? 0,
      signalsToday: (j['signals_today'] as num?)?.toInt() ?? 0,
      uptime: _formatUptime((j['uptime_seconds'] as num?)?.toDouble() ?? 0.0),
    );
  }

  @override
  Future<List<MockTicker>> fetchTickers() async {
    final j =
        (await client.get('/api/pulse/tickers')) as Map<String, dynamic>;
    final items = (j['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return items
        .map((m) => MockTicker(
              symbol: m['symbol'] as String? ?? '',
              price: (m['price'] as num?)?.toDouble() ?? 0.0,
              changePct24h: (m['change_pct_24h'] as num?)?.toDouble() ?? 0.0,
            ))
        .toList();
  }

  @override
  Future<List<MockSignal>> fetchSignals({
    String status = 'all',
    int limit = 50,
    String? setupClass,
  }) async {
    final query = <String, dynamic>{'status': status, 'limit': limit};
    if (setupClass != null && setupClass.isNotEmpty) {
      query['setup_class'] = setupClass;
    }
    final j = (await client.get('/api/signals', query: query))
        as Map<String, dynamic>;
    final items = (j['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return items.map(_signalFromJson).toList();
  }

  @override
  Future<List<MockPosition>> fetchPositions() async {
    final j = (await client.get('/api/positions')) as Map<String, dynamic>;
    final items = (j['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return items.map(_positionFromJson).toList();
  }

  @override
  Future<List<MockActivityEvent>> fetchActivity({
    int limit = 50,
    String? setupClass,
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (setupClass != null && setupClass.isNotEmpty) {
      query['setup_class'] = setupClass;
    }
    final j = (await client.get('/api/activity', query: query))
        as Map<String, dynamic>;
    final items = (j['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return items.map(_activityFromJson).toList();
  }

  @override
  Future<AutoModeStatus> fetchAutoMode() async {
    final j = (await client.get('/api/auto-mode')) as Map<String, dynamic>;
    return AutoModeStatus.fromJson(j);
  }

  @override
  Future<AutoModeStatus> setAutoMode(String mode) async {
    await client.post('/api/auto-mode', body: {'mode': mode});
    // Re-fetch so the UI sees the post-change risk-gate state in one shot.
    return fetchAutoMode();
  }

  @override
  Future<PnlHistory> fetchPnlHistory({int days = 30, String? mode}) async {
    final query = <String, dynamic>{'days': days};
    if (mode != null && mode.isNotEmpty) {
      query['mode'] = mode;
    }
    final j =
        (await client.get('/api/pnl/history', query: query)) as Map<String, dynamic>;
    final items = (j['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return PnlHistory(
      mode: j['mode'] as String? ?? 'off',
      days: (j['days'] as num?)?.toInt() ?? days,
      items: items
          .map((m) => PnlPoint(
                date: m['date'] as String? ?? '',
                pnlUsd: (m['pnl_usd'] as num?)?.toDouble() ?? 0.0,
              ))
          .toList(),
      weeklyPnlUsd: (j['weekly_pnl_usd'] as num?)?.toDouble() ?? 0.0,
      monthlyPnlUsd: (j['monthly_pnl_usd'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  Future<List<AgentStat>> fetchAgents() async {
    final j = (await client.get('/api/agents')) as Map<String, dynamic>;
    final items = (j['items'] as List? ?? []).cast<Map<String, dynamic>>();
    return items.map(AgentStat.fromJson).toList();
  }

  @override
  Future<bool> healthCheck() async {
    try {
      final j = await client.get('/api/health');
      return j is Map && j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PretpSettings> fetchPretpSettings() async {
    final j = (await client.get('/api/settings/pretp')) as Map<String, dynamic>;
    return PretpSettings.fromJson(j);
  }

  @override
  Future<PretpSettings> updatePretpSettings(PretpSettings partial) async {
    final j = (await client.put(
      '/api/settings/pretp',
      body: partial.toJsonPartial(),
    )) as Map<String, dynamic>;
    return PretpSettings.fromJson(j);
  }

  @override
  Future<AutoTradeSettings> fetchAutoTradeSettings() async {
    final j = (await client.get('/api/settings/auto-trade')) as Map<String, dynamic>;
    return AutoTradeSettings.fromJson(j);
  }

  @override
  Future<AutoTradeSettings> updateAutoTradeSettings(
    AutoTradeSettings partial,
  ) async {
    final j = (await client.put(
      '/api/settings/auto-trade',
      body: partial.toJsonPartial(),
    )) as Map<String, dynamic>;
    return AutoTradeSettings.fromJson(j);
  }

  @override
  Future<PretpSettings> fetchUserPretpSettings() async {
    final j = (await client.get('/api/settings/user/pretp'))
        as Map<String, dynamic>;
    return PretpSettings.fromJson(j);
  }

  @override
  Future<PretpSettings> updateUserPretpSettings(PretpSettings partial) async {
    final j = (await client.put(
      '/api/settings/user/pretp',
      body: partial.toJsonPartial(),
    )) as Map<String, dynamic>;
    return PretpSettings.fromJson(j);
  }

  @override
  Future<PretpSettings> resetUserPretpSettings() async {
    final j = (await client.delete('/api/settings/user/pretp'))
        as Map<String, dynamic>;
    return PretpSettings.fromJson(j);
  }

  /// Disk-cache key for the last successful auto-trade settings response.
  /// Persisting the RAW server map (not a re-serialised model) lets us
  /// replay it through [AutoTradeSettings.fromJson] on a network failure
  /// without needing a full model `toJson` — the GET response IS the
  /// canonical shape.
  static const _kAutoTradeSettingsCacheKey = 'cache_user_auto_trade_settings';

  @override
  Future<AutoTradeSettings> fetchUserAutoTradeSettings() async {
    try {
      final j = (await client.get('/api/settings/user/auto-trade'))
          as Map<String, dynamic>;
      // Persist the raw response so a later slow/deploy-window failure can
      // render the user's real settings instead of a "Could not load
      // settings" error screen (the Signals-tab treatment for the
      // settings page, which previously had no cache at all).
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAutoTradeSettingsCacheKey, jsonEncode(j));
      } catch (_) {
        // SharedPreferences unavailable — degrade silently; the live
        // response is still returned below.
      }
      return AutoTradeSettings.fromJson(j);
    } on ApiError catch (e) {
      // Only fall back for transport-level failures (timeout / network =
      // statusCode 0, or a 5xx engine blip mid-restart).  A real 4xx
      // (e.g. 404 for an anonymous device JWT) still propagates so the
      // page renders its genuine empty/anon state, not stale data.
      if (e.statusCode == 0 || e.statusCode >= 500) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(_kAutoTradeSettingsCacheKey);
          if (raw != null) {
            final j = jsonDecode(raw) as Map<String, dynamic>;
            return AutoTradeSettings.fromJson(j);
          }
        } catch (_) {
          // Fall through to rethrow when no usable cached copy exists.
        }
      }
      rethrow;
    }
  }

  @override
  Future<AutoTradeSettings> updateUserAutoTradeSettings(
    AutoTradeSettings partial,
  ) async {
    final j = (await client.put(
      '/api/settings/user/auto-trade',
      body: partial.toJsonPartial(),
    )) as Map<String, dynamic>;
    return AutoTradeSettings.fromJson(j);
  }

  @override
  Future<InvalidationSettings> fetchUserInvalidationSettings() async {
    final j = (await client.get('/api/settings/user/invalidation'))
        as Map<String, dynamic>;
    return InvalidationSettings.fromJson(j);
  }

  @override
  Future<InvalidationSettings> updateUserInvalidationSettings(
    InvalidationSettings partial,
  ) async {
    final j = (await client.put(
      '/api/settings/user/invalidation',
      body: partial.toJsonPartial(),
    )) as Map<String, dynamic>;
    return InvalidationSettings.fromJson(j);
  }

  @override
  Future<InvalidationSettings> resetUserInvalidationSettings() async {
    final j = (await client.delete('/api/settings/user/invalidation'))
        as Map<String, dynamic>;
    return InvalidationSettings.fromJson(j);
  }

  @override
  Future<Profile> fetchProfile() async {
    final j = (await client.get('/api/profile')) as Map<String, dynamic>;
    return Profile.fromJson(j);
  }

  @override
  Future<Profile> updateProfile(
    Profile partial, {
    bool acceptTerms = false,
  }) async {
    final j = (await client.put(
      '/api/profile',
      body: partial.toJsonPartial(acceptTerms: acceptTerms),
    )) as Map<String, dynamic>;
    return Profile.fromJson(j);
  }

  @override
  Future<TradeListResponse> fetchTrades({
    String mode = 'paper',
    int limit = 50,
    int offset = 0,
    String? sinceTs,
    String? symbol,
    bool includeOpen = false,
  }) async {
    final query = <String, dynamic>{
      'mode': mode,
      'limit': limit,
      'offset': offset,
    };
    if (sinceTs != null && sinceTs.isNotEmpty) query['since_ts'] = sinceTs;
    if (symbol != null && symbol.isNotEmpty) query['symbol'] = symbol;
    // Owner 2026-05-17 — the Paper tab needs to surface OPEN paper positions
    // alongside closed history.  The engine defaults this to ``false`` (per
    // ``src/api/paper_trade_routes.py``); the Paper tab passes ``true`` so
    // the list isn't artificially empty when trades are still active.
    if (includeOpen) query['include_open'] = 'true';
    final j = (await client.get('/api/trades', query: query))
        as Map<String, dynamic>;
    return TradeListResponse.fromJson(j);
  }

  @override
  Future<PaperResetResponse> resetPaperBalance() async {
    final j = (await client.post('/api/auto-mode/paper/reset'))
        as Map<String, dynamic>;
    // Paper ledger just got wiped engine-side — the trade-engine snapshot
    // (carrying ``autoMode.dailyPnlUsd``, ``dailyLossPct``) and the pulse
    // bundle (carrying ``today_pnl_usd``) both reference the same paper
    // ledger.  Drop both from SWR so the next subscribe forces a fresh
    // RTT; otherwise the Trade card keeps showing the pre-reset PnL for
    // up to 60s and the user reads "I reset but it's still red."
    _swr.invalidate(_kTradeEngineKey);
    _swr.invalidate(_kPulseBundleKey);
    return PaperResetResponse.fromJson(j);
  }

  @override
  Future<PaperResetMineResponse> resetMinePaperHistory() async {
    final j = (await client.post('/api/auto-mode/paper/reset-mine'))
        as Map<String, dynamic>;
    // The user's visibility window just rolled forward, so any cached
    // trades-list pages are no longer valid (rows from the prior window
    // are now invisible). Invalidate the same SWR keys as the engine-wide
    // reset so the next subscribe forces a fresh fetch.
    _swr.invalidate(_kTradeEngineKey);
    _swr.invalidate(_kPulseBundleKey);
    return PaperResetMineResponse.fromJson(j);
  }

  @override
  Future<bool> resumeMineAutoTrade() async {
    final j = (await client.post('/api/auto-mode/resume-mine'))
        as Map<String, dynamic>;
    // The user's pause flag just cleared — the next watchUserAutoTrade
    // subscribe must refetch so the banner disappears immediately
    // instead of staying visible for up to the SWR TTL.
    _swr.invalidate(_kAutoTradeUserStatusKey);
    // Recent Activity will start updating again once the next signal
    // fires; invalidate so the "paused" derived state on the Trade
    // tab clears immediately rather than on the next polling tick.
    _swr.invalidate(_kTradeEngineKey);
    return (j['resumed'] as bool?) ?? false;
  }

  @override
  Future<BinanceConnectSuccess> connectBinanceServerSide({
    required String apiKey,
    required String apiSecret,
  }) async {
    // Use postRaw so we can inspect the X-Connect-Error-Code +
    // X-Engine-VPS-IP headers on 4xx (the engine's PR-2 contract
    // for targeted fix-up UI).  Avoid logging the request body —
    // it carries the user's plaintext API secret which must not
    // hit any log sink.
    final resp = await client.postRaw(
      '/api/binance/connect',
      body: {
        'api_key': apiKey,
        'api_secret': apiSecret,
      },
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = resp.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(resp.body) as Map<String, dynamic>;
      return BinanceConnectSuccess.fromJson(body);
    }
    // Failure path — parse the engine's typed error + headers.
    String detail = 'Binance connect failed (HTTP ${resp.statusCode})';
    try {
      final j = jsonDecode(resp.body);
      if (j is Map && j['detail'] != null) {
        detail = '${j['detail']}';
      }
    } catch (_) {/* keep default detail */}
    final code = resp.headers['x-connect-error-code'] ?? 'UNKNOWN';
    final engineIp = resp.headers['x-engine-vps-ip'];
    throw BinanceConnectError(
      code: code,
      detail: detail,
      httpStatus: resp.statusCode,
      engineVpsIp: engineIp,
    );
  }

  @override
  Future<AutoTradeUserStatus> getAutoTradeUserStatus() async {
    final j = (await client.get('/api/auto-trade/user-status'))
        as Map<String, dynamic>;
    return AutoTradeUserStatus.fromJson(j);
  }

  @override
  Future<BinanceConnectStatus> fetchBinanceConnectStatus() async {
    final j = (await client.get('/api/binance/connect/status'))
        as Map<String, dynamic>;
    return BinanceConnectStatus.fromJson(j);
  }

  @override
  Future<void> disconnectBinanceServerSide() async {
    await client.delete('/api/binance/connect');
  }

  @override
  Future<AutoTradeRuntimeStatus> getAutoTradeRuntimeStatus() async {
    final j = (await client.get('/api/auto-trade/runtime-status'))
        as Map<String, dynamic>;
    return AutoTradeRuntimeStatus.fromJson(j);
  }

  Map<String, String> _coerceManagementMap(Object? raw) {
    if (raw is! Map) return <String, String>{};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v is String) out[k.toUpperCase()] = v;
    });
    return out;
  }

  @override
  Future<Map<String, String>> fetchSymbolManagement() async {
    final j = await client.get('/api/settings/user/symbol-management');
    return _coerceManagementMap(j);
  }

  @override
  Future<Map<String, String>> setSymbolManagement(
    String symbol, String mode,
  ) async {
    final j = await client.put(
      '/api/settings/user/symbol-management',
      body: {'symbol': symbol, 'mode': mode},
    );
    return _coerceManagementMap(j);
  }

  @override
  Future<PlayVerifyResult> verifyPlayPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    final j = (await client.post(
      '/api/billing/play/verify',
      body: {'product_id': productId, 'purchase_token': purchaseToken},
    )) as Map<String, dynamic>;
    return PlayVerifyResult.fromJson(j);
  }

  @override
  Future<List<ServerSidePosition>> getAutoTradePositions() async {
    final j = (await client.get('/api/auto-trade/positions'))
        as Map<String, dynamic>;
    final rawList = j['positions'];
    if (rawList is! List) return const <ServerSidePosition>[];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(ServerSidePosition.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<DispatchEvent>> getRecentDispatchEvents({int limit = 20}) async {
    // Server caps internally at 100; we hint at the desired window
    // via the query param so the network round-trip stays small
    // even on accounts with very chatty rejection histories.
    final j = (await client.get(
      '/api/auto-trade/recent-events?limit=$limit',
    )) as Map<String, dynamic>;
    final rawList = j['events'];
    if (rawList is! List) return const <DispatchEvent>[];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(DispatchEvent.fromJson)
        .toList(growable: false);
  }

  @override
  Future<PaperCloseAllResponse> closeAllPaperPositions() async {
    final j = (await client.post('/api/auto-mode/paper/close-all'))
        as Map<String, dynamic>;
    // Close-all realises every open paper position at mark — that flows
    // through ``daily_pnl_usd`` immediately.  Invalidate the same keys
    // as ``resetPaperBalance`` so the Trade card reflects the new
    // realised PnL on the next subscribe rather than serving stale.
    _swr.invalidate(_kTradeEngineKey);
    _swr.invalidate(_kPulseBundleKey);
    return PaperCloseAllResponse.fromJson(j);
  }

  // ---- json → mock-class adapters --------------------------------------

  MockSignal _signalFromJson(Map<String, dynamic> j) => MockSignal(
        id: j['signal_id'] as String? ?? '',
        symbol: j['symbol'] as String? ?? '',
        direction: j['direction'] as String? ?? 'LONG',
        setupName: (j['setup_class'] as String? ?? '').replaceAll('_', ' '),
        agentName: j['agent_name'] as String? ?? '',
        entry: (j['entry'] as num?)?.toDouble() ?? 0.0,
        sl: (j['stop_loss'] as num?)?.toDouble() ?? 0.0,
        tp1: (j['tp1'] as num?)?.toDouble() ?? 0.0,
        tp2: (j['tp2'] as num?)?.toDouble() ?? 0.0,
        tp3: (j['tp3'] as num?)?.toDouble() ?? 0.0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        tier: j['quality_tier'] as String? ?? 'B',
        status: j['status'] as String? ?? 'ACTIVE',
        pnlPct: (j['pnl_pct'] as num?)?.toDouble() ?? 0.0,
        minutesAgo: (j['minutes_ago'] as num?)?.toInt() ?? 0,
        holdMins: (j['hold_mins'] as num?)?.toInt(),
        currentPrice: (j['current_price'] as num?)?.toDouble() ?? 0.0,
        preTpTriggerPrice:
            (j['pre_tp_trigger_price'] as num?)?.toDouble() ?? 0.0,
        preTpThresholdPct:
            (j['pre_tp_threshold_pct'] as num?)?.toDouble() ?? 0.0,
        preTpHit: j['pre_tp_hit'] as bool? ?? false,
        maxFavorableExcursionPct:
            (j['max_favorable_excursion_pct'] as num?)?.toDouble() ?? 0.0,
      );

  MockPosition _positionFromJson(Map<String, dynamic> j) => MockPosition(
        symbol: j['symbol'] as String? ?? '',
        direction: j['direction'] as String? ?? 'LONG',
        entry: (j['entry'] as num?)?.toDouble() ?? 0.0,
        currentPrice: (j['current_price'] as num?)?.toDouble() ?? 0.0,
        qty: (j['qty'] as num?)?.toDouble() ?? 0.0,
        pnlUsd: (j['pnl_usd'] as num?)?.toDouble() ?? 0.0,
        pnlPct: (j['pnl_pct'] as num?)?.toDouble() ?? 0.0,
        minutesOpen: (j['minutes_open'] as num?)?.toInt() ?? 0,
      );

  MockActivityEvent _activityFromJson(Map<String, dynamic> j) {
    final kind = j['kind'] as String? ?? 'OPEN';
    return MockActivityEvent(
      kind: kind,
      title: j['title'] as String? ?? '',
      subtitle: j['subtitle'] as String? ?? '',
      minutesAgo: (j['minutes_ago'] as num?)?.toInt() ?? 0,
      color: _colorForKind(kind),
    );
  }

  /// Brand-token mapping for activity event glyphs.  Mirrors the colours
  /// used by ``mock_data.dart`` so the live feed renders identically to
  /// the offline preview.
  static Color _colorForKind(String kind) {
    switch (kind) {
      case 'OPEN':
        return LuminColors.accent;
      case 'PRE_TP':
        return LuminColors.warn;
      case 'TP1':
      case 'TP2':
      case 'TP3':
        return LuminColors.success;
      case 'SL':
        return LuminColors.loss;
      case 'INVAL':
        return LuminColors.textMuted;
      default:
        return LuminColors.accent;
    }
  }

  static String _formatUptime(double seconds) {
    if (seconds <= 0) return '0s';
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    if (d > 0) return '${d}d ${h}h';
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Future<RegionInfo> fetchRegion() async {
    // Public endpoint — no auth header needed.  Soft-fail open:
    // any non-200 / network error collapses to the unblocked
    // unknown response so a transient backend outage doesn't
    // brick the auto-trade UI for legitimate users.
    try {
      final j = (await client.get('/api/region')) as Map<String, dynamic>;
      return RegionInfo.fromJson(j);
    } catch (_) {
      return const RegionInfo(
        countryCode: 'unknown',
        source: 'unknown',
        isBlocked: false,
        blockedRegions: [],
      );
    }
  }

  @override
  Future<void> deleteAccount() async {
    // Backend orchestrates blob-revoke → user-row-delete → cache-
    // invalidate.  On 204 we're done.  On 503 the ``detail`` body
    // carries one of the failure tags from
    // src/api/account_routes.py — translate to a typed exception
    // so the UI can show step-specific copy.
    try {
      await client.delete('/api/account');
    } on ApiError catch (e) {
      // The api_client's _decodeError stringifies the JSON body's
      // ``detail`` field; we match against the known tags.
      final tag = e.message.trim();
      final friendly = switch (tag) {
        'key_blob_delete_failed' =>
            'Could not revoke your Binance API key on our server. '
                'Please retry; if it keeps failing, contact support.',
        'user_row_delete_failed' =>
            'Your Binance key was revoked but the account row could '
                'not be removed. Please retry; the next attempt will '
                'pick up where this one stopped.',
        'server_misconfiguration_user_store' =>
            'Server misconfiguration. Please contact support — '
                'this is not something you can resolve from the app.',
        'user_lookup_failed' =>
            'Could not look up your account. Please retry shortly.',
        _ => 'Account deletion failed: ${e.message}',
      };
      throw DeleteAccountException(tag.isEmpty ? 'unknown' : tag, friendly);
    }
  }

}

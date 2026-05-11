/// Repository abstraction — the single seam between UI and data source.
///
/// Pages call ``LuminRepository`` methods.  The concrete implementation
/// (``MockRepository`` for offline/preview, ``HttpRepository`` for live
/// engine) is chosen at app startup based on user preference.  Adding a
/// new data source (websocket, on-device cache, …) means writing a new
/// implementation; no page has to change.
import 'package:flutter/material.dart';

import '../shared/tokens.dart';
import 'api_client.dart';
import 'mock_data.dart';

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
    this.usingDefaults,
  });

  /// "off" | "paper" | "live".
  final String? mode;
  final double? positionSizePct;
  final double? leverageCap;
  final int? maxConcurrentPositions;

  /// Only present on ``/api/settings/user/auto-trade`` responses.
  final bool? usingDefaults;

  factory AutoTradeSettings.fromJson(Map<String, dynamic> j) => AutoTradeSettings(
        mode: j['mode'] as String?,
        positionSizePct: (j['position_size_pct'] as num?)?.toDouble(),
        leverageCap: (j['leverage_cap'] as num?)?.toDouble(),
        maxConcurrentPositions:
            (j['max_concurrent_positions'] as num?)?.toInt(),
        usingDefaults: j['using_defaults'] as bool?,
      );

  Map<String, dynamic> toJsonPartial() {
    final out = <String, dynamic>{};
    if (mode != null) out['mode'] = mode;
    if (positionSizePct != null) out['position_size_pct'] = positionSizePct;
    if (leverageCap != null) out['leverage_cap'] = leverageCap;
    if (maxConcurrentPositions != null) {
      out['max_concurrent_positions'] = maxConcurrentPositions;
    }
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
  /// Per-user auto-trade overrides (Phase 2).
  Future<AutoTradeSettings> fetchUserAutoTradeSettings();
  Future<AutoTradeSettings> updateUserAutoTradeSettings(
    AutoTradeSettings partial,
  );
  /// User profile (Phase 3) — drives SignupPage + Settings → Profile.
  Future<Profile> fetchProfile();
  Future<Profile> updateProfile(Profile partial, {bool acceptTerms = false});
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
      usingDefaults: false,
    );
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
}

// ---------------------------------------------------------------------------
// HttpRepository — talks to FastAPI backend.
// ---------------------------------------------------------------------------

class HttpRepository implements LuminRepository {
  HttpRepository(this.client);

  final LuminApiClient client;

  @override
  bool get isLive => true;

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
  Future<AutoTradeSettings> fetchUserAutoTradeSettings() async {
    final j = (await client.get('/api/settings/user/auto-trade'))
        as Map<String, dynamic>;
    return AutoTradeSettings.fromJson(j);
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
        currentPrice: (j['current_price'] as num?)?.toDouble() ?? 0.0,
        preTpTriggerPrice:
            (j['pre_tp_trigger_price'] as num?)?.toDouble() ?? 0.0,
        preTpThresholdPct:
            (j['pre_tp_threshold_pct'] as num?)?.toDouble() ?? 0.0,
        preTpHit: j['pre_tp_hit'] as bool? ?? false,
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

}

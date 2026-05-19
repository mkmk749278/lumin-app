/// Pre-TP grab settings — per-user overrides (Phase 2).
///
/// Pre-TP grab moves SL to breakeven once price has captured a configurable
/// fraction of the path to TP1 (covers fees + safety margin).  This page
/// loads the **current user's** overrides via ``GET /api/settings/user/pretp``
/// (or the engine defaults if the user has none yet) and persists toggles
/// via ``PUT``.  The engine itself doesn't yet consume per-user values —
/// Phase 3 wires execution; until then this page is honest about storage-
/// only behaviour via the banner at the top.
///
/// The operator's engine-wide defaults live on a separate page (Settings →
/// Engine defaults, owner-only entry), pointed at ``/api/settings/pretp``.
import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';

/// UI-side regime buckets.  The backend uses 5 labels (TRENDING_UP /
/// TRENDING_DOWN / RANGING / VOLATILE / QUIET); the page collapses them
/// into 3 buckets so the toggles match the user's mental model.  The
/// backend accepts UI tokens directly and expands them on read.
const _kTrendingTokens = {'TRENDING_UP', 'TRENDING_DOWN'};
const _kChoppyTokens = {'VOLATILE', 'QUIET'};

class PreTpSettingsPage extends StatefulWidget {
  const PreTpSettingsPage({super.key});

  @override
  State<PreTpSettingsPage> createState() => _PreTpSettingsPageState();
}

class _PreTpSettingsPageState extends State<PreTpSettingsPage> {
  // Local edit state — populated from ``fetchUserPretpSettings`` on init,
  // mutated by user toggles, written back via ``updateUserPretpSettings``.
  bool _enabled = true;
  // Grab fraction (OWNER_BRIEF B17, 2026-05-17 doctrine): fraction of the
  // position closed at market when pre-TP threshold hits.  Engine default
  // 0.50; hard floor 0.30 (no user can collapse to the pre-2026-05-17
  // SL-to-BE-only behaviour); ceiling 1.00 (fully bank, leave nothing
  // riding).  The slider's UI bounds mirror these B17 constraints — the
  // backend clamps defensively too, so even an out-of-range PUT lands
  // safely, but enforcing in the slider gives immediate visual feedback.
  double _grabPct = 0.50;
  double _atrMult = 0.30;
  double _feeFloor = 0.12;

  /// OWNER_BRIEF B17 (2026-05-17) — when ON, the AutoTradeWatcher keeps
  /// polling for pre-TP partial closes on manually-taken entries even
  /// when auto-trade ``mode == 'off'``.  Default ON delivers capital
  /// preservation to manual operators without an explicit opt-in.
  /// OFF respects "off means off" for users who want pure manual
  /// control with no background broker activity.
  bool _protectManualEntries = true;

  bool _regimeTrending = true;
  bool _regimeRanging = true;
  bool _regimeChoppy = false;

  // Setup allowlist — defaults shown until backend wiring lands.
  // Engine read-path is pending; values still round-trip via PUT.
  final Map<String, bool> _setups = {
    'TPE (Trend Pullback)': true,
    'DIV_CONT (Divergence)': true,
    'CLS (Continuation)': true,
    'PDC (Post-Displacement)': true,
    'WHALE (Whale Momentum)': true,
    'FUNDING (Funding Extreme)': true,
    'LIQ_REVERSAL (Liquidation)': true,
    'LSR (Liquidity Sweep)': true,
    'FAR (Failed Auction)': true,
    'SR_FLIP (S/R Flip)': true,
    'QCB (Quiet Compression)': true,
    'VSB (Volume Surge)': true,
    'BDS (Breakdown Short)': true,
    'ORB (Opening Range)': false,
  };

  bool _loaded = false;
  bool _saving = false;
  String? _loadError;

  /// True when the server reports the user has no overrides yet — every
  /// rendered value is the engine default.  Drives the "Custom" badge
  /// vs. "Engine defaults" hint at the top of the page.
  bool _usingDefaults = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _load();
    }
  }

  Future<void> _load() async {
    final repo = AppConfigScope.of(context).repo;
    try {
      final s = await repo.fetchUserPretpSettings();
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled ?? _enabled;
        _atrMult = s.atrMultiplier ?? _atrMult;
        _feeFloor = s.feeFloorPct ?? _feeFloor;
        // OWNER_BRIEF B17 — clamp to [0.30, 1.00] in case an older server
        // returned an out-of-range value (defense in depth; the server-side
        // clamp in `_coerce_pretp` should already guarantee this).
        if (s.grabFraction != null) {
          _grabPct = s.grabFraction!.clamp(0.30, 1.00);
        }
        if (s.protectManualEntries != null) {
          _protectManualEntries = s.protectManualEntries!;
        }
        _usingDefaults = s.usingDefaults ?? true;
        if (s.regimeAllowlist != null) {
          final tokens = s.regimeAllowlist!.toSet();
          _regimeTrending = tokens.intersection(_kTrendingTokens).isNotEmpty;
          _regimeRanging = tokens.contains('RANGING');
          _regimeChoppy = tokens.intersection(_kChoppyTokens).isNotEmpty;
        }
        if (s.setupAllowlist != null) {
          // The backend allowlist uses canonical setup_class names;
          // the UI's labels carry parenthetical descriptions.  Match
          // by the leading token before the space.
          final allowed = s.setupAllowlist!.toSet();
          for (final key in _setups.keys.toList()) {
            final token = key.split(' ').first;
            // Map UI token → backend canonical name.  Conservative: only
            // flip OFF when explicitly absent from the server allowlist;
            // unknown server tokens keep the UI default.
            final mapped = _uiTokenToBackend[token] ?? token;
            if (allowed.isNotEmpty) {
              _setups[key] = allowed.contains(mapped);
            }
          }
        }
        _loaded = true;
        _loadError = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = '$e';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = AppConfigScope.of(context).repo;
    final regimeAllowlist = <String>[
      if (_regimeTrending) ...['TRENDING_UP', 'TRENDING_DOWN'],
      if (_regimeRanging) 'RANGING',
      if (_regimeChoppy) ...['VOLATILE', 'QUIET'],
    ];
    final setupAllowlist = <String>[
      for (final entry in _setups.entries)
        if (entry.value)
          _uiTokenToBackend[entry.key.split(' ').first] ??
              entry.key.split(' ').first,
    ];
    final partial = PretpSettings(
      enabled: _enabled,
      regimeAllowlist: regimeAllowlist,
      setupAllowlist: setupAllowlist,
      atrMultiplier: _atrMult,
      feeFloorPct: _feeFloor,
      grabFraction: _grabPct,
      protectManualEntries: _protectManualEntries,
    );
    try {
      final saved = await repo.updateUserPretpSettings(partial);
      if (!mounted) return;
      setState(() => _usingDefaults = saved.usingDefaults ?? false);
      // 2026-05-19: AutoTradeWatcher removal — pre-TP doctrine now
      // executes server-side via the Position FSM (engine PR-7) on
      // every fill regardless of app state.  No on-device poll loop
      // to kick on Save.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pre-TP settings saved'),
          duration: Duration(seconds: 2),
        ),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: ${e.message}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    final isLive = scope.repo.isLive;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-TP grab'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _loaded && _loadError == null ? _save : null,
              tooltip: 'Save',
            ),
        ],
      ),
      body: _bodyFor(isLive),
    );
  }

  Widget _bodyFor(bool isLive) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(LuminSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: LuminColors.textMuted, size: 36),
              const SizedBox(height: LuminSpacing.md),
              Text(
                'Could not load settings',
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: LuminSpacing.md),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _loaded = false;
                    _loadError = null;
                  });
                  _load();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        if (!isLive) const PreviewBadge(),
        _scopeBanner(),
        _masterCard(),
        const SizedBox(height: LuminSpacing.md),
        _manualEntryProtectionCard(),
        const SizedBox(height: LuminSpacing.md),
        _thresholdsCard(),
        const SizedBox(height: LuminSpacing.md),
        _regimeCard(),
        const SizedBox(height: LuminSpacing.md),
        _setupsCard(),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
  }

  /// Honest banner explaining the current scope of these settings.
  /// Phase 2 ships storage + endpoints but the engine doesn't yet
  /// consume per-user values at signal-evaluation time — that's
  /// Phase 3 (the user's app fires their own order using these
  /// values).  Until then we say so plainly rather than imply effect.
  Widget _scopeBanner() {
    final usingDefaults = _usingDefaults;
    final accent = usingDefaults ? LuminColors.textMuted : LuminColors.accent;
    final label = usingDefaults
        ? 'Using engine defaults.'
        : 'Custom — your overrides.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg,
        LuminSpacing.sm,
        LuminSpacing.lg,
        LuminSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.md,
          vertical: LuminSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(LuminRadii.sm),
          border: Border.all(color: accent.withOpacity(0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              usingDefaults ? Icons.info_outline : Icons.tune,
              color: accent,
              size: 16,
            ),
            const SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Saved to your profile. Engine-side pre-TP fires a real '
                    'partial close on the owner\'s auto-trade today; per-user '
                    'execution ships when your Binance keys are wired (Phase 4).',
                    style: TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _masterCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            const Icon(Icons.shield_moon_outlined, color: LuminColors.accent, size: 18),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pre-TP grab',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _enabled
                        ? 'Auto-moves SL to breakeven once price captures the threshold'
                        : 'Disabled — SL stays at original position until TP/SL hit',
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _enabled,
              activeColor: LuminColors.accent,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ],
        ),
      ),
    );
  }

  /// OWNER_BRIEF B17 (2026-05-17) — pre-TP coverage for manual entries.
  ///
  /// When ON, the AutoTradeWatcher keeps polling for pre-TP partial
  /// closes on manually-taken entries even when auto-trade is OFF.
  /// Closes the capital-preservation loop for the manual-operator
  /// cohort (hand-picked entries via Take Signal) — without this, a
  /// manual user gets entry + SL + TP1 placed but eats the full SL
  /// when price reverses post-MFE.  Default ON.
  ///
  /// Disabled (greyed) when the master Pre-TP toggle is off — there's
  /// no pre-TP behaviour to extend if the master switch is off.
  Widget _manualEntryProtectionCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.security_outlined,
                  color: _enabled
                      ? LuminColors.accent
                      : LuminColors.textMuted,
                  size: 18,
                ),
                const SizedBox(width: LuminSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Protect manual entries',
                        style: TextStyle(
                          color: _enabled
                              ? LuminColors.textPrimary
                              : LuminColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _protectManualEntries
                            ? 'Pre-TP partials apply to Take-Signal entries '
                                'even when Auto-trade is off.'
                            : 'Manual entries get entry + SL + TP1 only — '
                                'no pre-TP partial close.',
                        style: const TextStyle(
                          color: LuminColors.textSecondary,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _protectManualEntries,
                  activeColor: LuminColors.accent,
                  onChanged: _enabled
                      ? (v) => setState(() => _protectManualEntries = v)
                      : null,
                ),
              ],
            ),
            // Subscriber-facing explanation of the asymmetry.  Same math
            // doctrine as the grab-fraction preview: be transparent about
            // why this default is ON.
            const SizedBox(height: LuminSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(left: LuminSpacing.lg + 8),
              child: Text(
                _protectManualEntries
                    ? 'Watcher stays running in protect-only mode; one '
                        'broker call when a pre-TP threshold fires. No '
                        'new entries are opened.'
                    : 'No background broker activity. Manual entries '
                        'run their original SL/TP only.',
                style: const TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thresholdsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'THRESHOLDS',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            _slider(
              label: 'Grab fraction',
              // OWNER_BRIEF B17: range [0.30, 1.00].  30% floor prevents
              // pre-2026-05-17 SL-to-BE-only collapse; 100% fully banks
              // the partial.  14 divisions = 5% steps across the range.
              value: '${(_grabPct * 100).toStringAsFixed(0)}%',
              slider: Slider(
                value: _grabPct,
                min: 0.30,
                max: 1.00,
                divisions: 14,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: _enabled ? (v) => setState(() => _grabPct = v) : null,
              ),
            ),
            // Preview: explain what the chosen fraction does in plain text.
            // Cleared-up doctrine post-2026-05-17 — pre-TP is a REAL partial
            // close, not just a SL-to-BE move.  Showing the math here so
            // subscribers can pick a fraction with eyes open.
            Padding(
              padding: const EdgeInsets.only(
                left: LuminSpacing.sm,
                bottom: LuminSpacing.md,
              ),
              child: Text(
                'At pre-TP: ${(_grabPct * 100).toStringAsFixed(0)}% closed at market, '
                '${((1.0 - _grabPct) * 100).toStringAsFixed(0)}% rides to TP1 '
                'with SL at entry (breakeven).',
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            _slider(
              label: 'ATR floor multiplier',
              value: '${_atrMult.toStringAsFixed(2)}x',
              slider: Slider(
                value: _atrMult,
                min: 0.10,
                max: 1.00,
                divisions: 18,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: _enabled ? (v) => setState(() => _atrMult = v) : null,
              ),
            ),
            _slider(
              label: 'Fee floor (min profit before BE)',
              value: '${_feeFloor.toStringAsFixed(2)}%',
              slider: Slider(
                value: _feeFloor,
                min: 0.05,
                max: 0.50,
                divisions: 9,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: _enabled ? (v) => setState(() => _feeFloor = v) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _regimeCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'REGIME ALLOWLIST',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            _regimeRow('Trending', _regimeTrending,
                (v) => setState(() => _regimeTrending = v)),
            _regimeRow('Ranging', _regimeRanging,
                (v) => setState(() => _regimeRanging = v)),
            _regimeRow('Choppy', _regimeChoppy,
                (v) => setState(() => _regimeChoppy = v)),
          ],
        ),
      ),
    );
  }

  Widget _regimeRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          Switch(
            value: value,
            activeColor: LuminColors.accent,
            onChanged: _enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _setupsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SETUP ALLOWLIST',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            for (final entry in _setups.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Switch(
                      value: entry.value,
                      activeColor: LuminColors.accent,
                      onChanged: _enabled
                          ? (v) => setState(() => _setups[entry.key] = v)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slider({required String label, required String value, required Widget slider}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: _enabled ? LuminColors.textPrimary : LuminColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: _enabled ? LuminColors.accent : LuminColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          slider,
        ],
      ),
    );
  }
}

/// UI label tokens → backend ``setup_class`` canonical names.  The page
/// labels carry parenthetical descriptions ("TPE (Trend Pullback)") so
/// we strip to the leading token before lookup.
const Map<String, String> _uiTokenToBackend = {
  'TPE': 'TREND_PULLBACK_EMA',
  'DIV_CONT': 'DIVERGENCE_CONTINUATION',
  'CLS': 'CONTINUATION_LIQUIDITY_SWEEP',
  'PDC': 'POST_DISPLACEMENT_CONTINUATION',
  'WHALE': 'WHALE_MOMENTUM',
  'FUNDING': 'FUNDING_EXTREME_SIGNAL',
  'LIQ_REVERSAL': 'LIQUIDATION_REVERSAL',
  'LSR': 'LIQUIDITY_SWEEP_REVERSAL',
  'FAR': 'FAILED_AUCTION_RECLAIM',
  'SR_FLIP': 'SR_FLIP_RETEST',
  'QCB': 'QUIET_COMPRESSION_BREAK',
  'VSB': 'VOLUME_SURGE_BREAKOUT',
  'BDS': 'BREAKDOWN_SHORT',
  'ORB': 'OPENING_RANGE_BREAKOUT',
  'MA_CROSS': 'MA_CROSS_TREND_SHIFT',
};

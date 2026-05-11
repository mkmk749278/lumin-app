/// Pre-TP grab settings — early-profit-taking knobs.
///
/// Pre-TP grab moves SL to breakeven once price has captured a configurable
/// fraction of the path to TP1 (covers fees + safety margin).  This page
/// loads the engine's resolved view from ``GET /api/settings/pretp`` and
/// persists user toggles via ``PUT`` on save.
import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/owner_only_banner.dart';
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
  // Local edit state — populated from ``fetchPretpSettings`` on init,
  // mutated by user toggles, written back via ``updatePretpSettings``.
  bool _enabled = true;
  double _grabPct = 0.50;
  double _atrMult = 0.30;
  double _feeFloor = 0.12;

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
      final s = await repo.fetchPretpSettings();
      if (!mounted) return;
      setState(() {
        _enabled = s.enabled ?? _enabled;
        _atrMult = s.atrMultiplier ?? _atrMult;
        _feeFloor = s.feeFloorPct ?? _feeFloor;
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
    );
    try {
      await repo.updatePretpSettings(partial);
      if (!mounted) return;
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
    // Engine PR #355 gates PUT /api/settings/pretp to OWNER_TIER.  Hide
    // the Save action + disable form inputs when the cached JWT's tier
    // is anything other than owner.  ``null`` tier (mock mode, pre-Phase-2
    // token) shows controls — the engine 403 remains the backstop.
    final tier = scope.tier;
    final canEdit = tier == null || tier == 'owner';
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
          else if (canEdit)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _loaded && _loadError == null ? _save : null,
              tooltip: 'Save',
            ),
        ],
      ),
      body: _bodyFor(isLive, canEdit: canEdit),
    );
  }

  Widget _bodyFor(bool isLive, {bool canEdit = true}) {
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
    final list = ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        if (!isLive) const PreviewBadge(),
        if (!canEdit) const OwnerOnlyBanner(),
        _masterCard(),
        const SizedBox(height: LuminSpacing.md),
        _thresholdsCard(),
        const SizedBox(height: LuminSpacing.md),
        _regimeCard(),
        const SizedBox(height: LuminSpacing.md),
        _setupsCard(),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
    // Non-owner tiers see all the fields read-only.  AbsorbPointer
    // blocks every tap / scroll / drag below it; combined with the
    // hidden Save button in the AppBar and the OwnerOnlyBanner at the
    // top of the list, the page becomes a clear read-only view of the
    // current engine config.  The visual `Opacity` reinforces the
    // disabled state without altering the existing colour tokens.
    if (canEdit) return list;
    return Opacity(
      opacity: 0.65,
      child: AbsorbPointer(absorbing: true, child: list),
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
              label: 'Grab fraction (of TP1 distance)',
              value: '${(_grabPct * 100).toStringAsFixed(0)}%',
              slider: Slider(
                value: _grabPct,
                min: 0.20,
                max: 0.80,
                divisions: 12,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: _enabled ? (v) => setState(() => _grabPct = v) : null,
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

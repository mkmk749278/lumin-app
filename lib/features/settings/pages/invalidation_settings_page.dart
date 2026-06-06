/// Invalidation settings — per-user overrides (OWNER_BRIEF B17, 2026-05-17).
///
/// Three preset aggressiveness modes (Loose / Standard / Tight) cover the
/// common cases; an Advanced section exposes the underlying knobs for users
/// who want fine control without committing to a preset.  Loads the current
/// user's overrides via ``GET /api/settings/user/invalidation`` (or the
/// engine defaults if the user has none yet) and persists via ``PUT``.
///
/// Engine-side TradeMonitor is owner-only auto-trade today and uses the
/// engine default mode (``INVALIDATION_MODE_DEFAULT``).  Per-user values
/// stored here are consumed by the app-side OrderExecutor in Phase 4 when
/// users have their own Binance keys.  The honest banner at the top
/// surfaces this distinction.
import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';

class InvalidationSettingsPage extends StatefulWidget {
  const InvalidationSettingsPage({super.key});

  @override
  State<InvalidationSettingsPage> createState() =>
      _InvalidationSettingsPageState();
}

class _InvalidationSettingsPageState extends State<InvalidationSettingsPage> {
  // Preset mode — defaults to "standard" per B17.  Switches the preset
  // cards' selected state and the suggested values of the advanced knobs.
  String _mode = 'standard';

  // Advanced-section knobs.  Pre-populated with B17 defaults; nulled fields
  // on the wire mean "use engine default" — see ``_save`` for the partial
  // payload logic.
  bool _emaCrossoverEnabled = true;
  bool _regimeShiftEnabled = true;
  bool _trailingKillEnabled = false; // Activated automatically by "tight" mode
  double _trailingMfeR = 0.30;
  double _trailingRetracePct = 0.50;
  // momentum_threshold_mult + min_age_sec exposed only when the user has
  // touched them via the advanced section; otherwise we leave them null
  // on the PUT so the server resolves to engine defaults.
  double? _momentumMult;

  bool _advancedExpanded = false;
  bool _loaded = false;
  bool _saving = false;
  bool _resetting = false;
  String? _loadError;

  /// True when the server reports the user has no overrides yet.
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
      final s = await repo.fetchUserInvalidationSettings();
      if (!mounted) return;
      setState(() {
        _mode = s.mode ?? _mode;
        _emaCrossoverEnabled =
            s.emaCrossoverEnabled ?? _emaCrossoverEnabled;
        _regimeShiftEnabled = s.regimeShiftEnabled ?? _regimeShiftEnabled;
        _trailingKillEnabled =
            s.trailingKillEnabled ?? (_mode == 'tight');
        _trailingMfeR = s.trailingMfeRThreshold ?? _trailingMfeR;
        _trailingRetracePct = s.trailingRetracePct ?? _trailingRetracePct;
        _momentumMult = s.momentumThresholdMult;
        _usingDefaults = s.usingDefaults ?? true;
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

  /// Applying a preset mode sets the advanced knobs to that preset's
  /// canonical values, then user-touched advanced knobs persist on top.
  /// The PUT carries ``mode`` plus any explicitly-set advanced knob; the
  /// server resolves NULL knobs to the preset's defaults internally.
  void _applyPreset(String mode) {
    setState(() {
      _mode = mode;
      switch (mode) {
        case 'loose':
          _emaCrossoverEnabled = false;
          _regimeShiftEnabled = false;
          _trailingKillEnabled = false;
          break;
        case 'tight':
          _emaCrossoverEnabled = true;
          _regimeShiftEnabled = true;
          _trailingKillEnabled = true;
          break;
        case 'standard':
        default:
          _emaCrossoverEnabled = true;
          _regimeShiftEnabled = true;
          _trailingKillEnabled = false;
          break;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = AppConfigScope.of(context).repo;
    final partial = InvalidationSettings(
      mode: _mode,
      emaCrossoverEnabled: _emaCrossoverEnabled,
      regimeShiftEnabled: _regimeShiftEnabled,
      trailingKillEnabled: _trailingKillEnabled,
      trailingMfeRThreshold: _trailingMfeR,
      trailingRetracePct: _trailingRetracePct,
      momentumThresholdMult: _momentumMult,
    );
    try {
      final saved = await repo.updateUserInvalidationSettings(partial);
      if (!mounted) return;
      setState(() => _usingDefaults = saved.usingDefaults ?? false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalidation settings saved'),
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

  /// Confirm + reset the user's invalidation overrides to engine defaults.
  /// Clears the override row server-side (DELETE) so the page returns to the
  /// "Using engine defaults" state.
  Future<void> _confirmReset() async {
    if (_resetting || _saving) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: const Text(
          'Reset to engine defaults?',
          style: TextStyle(
            color: LuminColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Discards your custom invalidation settings and restores the '
          'engine defaults (Standard mode). You can customise again anytime.',
          style: TextStyle(
            color: LuminColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: LuminColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.accent,
              foregroundColor: LuminColors.bgDeep,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _resetting = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      await repo.resetUserInvalidationSettings();
      if (!mounted) return;
      setState(() {
        _loaded = false;
        _loadError = null;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset to engine defaults'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    final isLive = scope.repo.isLive;
    final busy = _saving || _resetting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invalidation'),
        actions: [
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            if (!_usingDefaults && _loaded && _loadError == null)
              IconButton(
                icon: const Icon(Icons.restart_alt),
                onPressed: _confirmReset,
                tooltip: 'Reset to engine defaults',
              ),
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _loaded && _loadError == null ? _save : null,
              tooltip: 'Save',
            ),
          ],
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
              const Text(
                'Could not load settings',
                style: TextStyle(
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
        _doctrineCard(),
        const SizedBox(height: LuminSpacing.md),
        _modeCard('loose', 'Loose',
            'Only the SL itself closes a signal. No early-exit on '
            'regime flip, EMA crossover, or momentum loss. Use when you '
            'want signals to develop fully.'),
        _modeCard('standard', 'Standard',
            'Engine baseline — regime flip, EMA crossover, and momentum-'
            'loss kills all active. Plus MFE protection: a signal that '
            'already banked a pre-TP partial won\'t be killed on a wobble.'),
        _modeCard('tight', 'Tight',
            'Standard plus ATR-trailing kill at MFE ≥ 0.3R. Closes the '
            'residual when price retraces 50% of the favourable peak — '
            'prevents winners-turning-losers from sliding to full SL.'),
        const SizedBox(height: LuminSpacing.md),
        _advancedCard(),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
  }

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
                    'Saved to your profile. Engine-side invalidation runs on '
                    "the owner's auto-trade today (uses the engine default "
                    'mode); per-user execution lands when your Binance keys '
                    'are wired (Phase 4).',
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

  /// Top-of-page primer explaining the capital-preservation doctrine —
  /// frames "tight" as the recommended-for-most-users option since
  /// post-2026-05-17 doctrine prioritises capital preservation over
  /// chasing the full TP1 ladder.
  Widget _doctrineCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: LuminColors.accent,
                  size: 18,
                ),
                SizedBox(width: LuminSpacing.md),
                Text(
                  'Capital preservation',
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: LuminSpacing.sm),
            Text(
              'Invalidation closes a signal early when the thesis breaks — '
              'before it can ride all the way to full SL. Doctrine: a full '
              'SL costs ~7.9% on margin at 10x; an early kill at small loss '
              'or breakeven preserves capital for the next setup. Pick a '
              'mode that matches how protective you want the engine to be.',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeCard(String mode, String title, String description) {
    final selected = _mode == mode;
    final borderColor =
        selected ? LuminColors.accent : LuminColors.cardBorder;
    final indicatorColor =
        selected ? LuminColors.accent : LuminColors.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg,
        0,
        LuminSpacing.lg,
        LuminSpacing.sm,
      ),
      child: InkWell(
        onTap: () => _applyPreset(mode),
        borderRadius: BorderRadius.circular(LuminRadii.md),
        child: Container(
          padding: const EdgeInsets.all(LuminSpacing.md),
          decoration: BoxDecoration(
            color: LuminColors.bgCard,
            borderRadius: BorderRadius.circular(LuminRadii.md),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: indicatorColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: LuminSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
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
      ),
    );
  }

  /// Advanced-section overrides.  Collapsed by default — users who pick a
  /// preset don't need to see the underlying knobs.  When expanded, the
  /// individual gates can be flipped and the trailing-kill bounds tuned.
  Widget _advancedCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune,
                    color: LuminColors.textMuted,
                    size: 16,
                  ),
                  const SizedBox(width: LuminSpacing.md),
                  const Expanded(
                    child: Text(
                      'ADVANCED',
                      style: TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _advancedExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: LuminColors.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
            if (_advancedExpanded) ...[
              const SizedBox(height: LuminSpacing.sm),
              const Text(
                'Override individual gates without changing the preset. '
                'Saved values persist across mode switches.',
                style: TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: LuminSpacing.md),
              _toggleRow(
                'EMA crossover kill',
                'Close when EMA9/EMA21 crosses against direction.',
                _emaCrossoverEnabled,
                (v) => setState(() => _emaCrossoverEnabled = v),
              ),
              _toggleRow(
                'Regime shift kill',
                'Close when the regime flips opposite to direction.',
                _regimeShiftEnabled,
                (v) => setState(() => _regimeShiftEnabled = v),
              ),
              _toggleRow(
                'ATR-trailing kill',
                'Close on retrace from MFE peak (tight-mode signature).',
                _trailingKillEnabled,
                (v) => setState(() => _trailingKillEnabled = v),
              ),
              const SizedBox(height: LuminSpacing.sm),
              _slider(
                label: 'Trailing arm threshold (R)',
                value:
                    '${_trailingMfeR.toStringAsFixed(2)}R',
                helper:
                    'MFE must reach this many SL-distances before the '
                    'trailing kill arms.',
                slider: Slider(
                  value: _trailingMfeR,
                  min: 0.10,
                  max: 1.00,
                  divisions: 18,
                  activeColor: LuminColors.accent,
                  inactiveColor: LuminColors.cardBorder,
                  onChanged: _trailingKillEnabled
                      ? (v) => setState(() => _trailingMfeR = v)
                      : null,
                ),
              ),
              _slider(
                label: 'Retrace fraction of peak',
                value: '${(_trailingRetracePct * 100).toStringAsFixed(0)}%',
                helper:
                    'Fires when price retraces this fraction of the MFE '
                    'peak back toward entry.',
                slider: Slider(
                  value: _trailingRetracePct,
                  min: 0.20,
                  max: 0.90,
                  divisions: 14,
                  activeColor: LuminColors.accent,
                  inactiveColor: LuminColors.cardBorder,
                  onChanged: _trailingKillEnabled
                      ? (v) =>
                          setState(() => _trailingRetracePct = v)
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(
    String label,
    String description,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: LuminSpacing.sm),
          Switch(
            value: value,
            activeColor: LuminColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required String value,
    required Widget slider,
    String? helper,
  }) {
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
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: LuminColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          slider,
          if (helper != null)
            Padding(
              padding: const EdgeInsets.only(left: LuminSpacing.sm),
              child: Text(
                helper,
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

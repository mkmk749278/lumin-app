/// Auto-trade settings — per-user overrides.
///
/// Two independent toggles: Live and Paper.
/// Both can be active simultaneously (mode='both'): live orders fire on Binance
/// AND the paper simulator runs in parallel for comparison.
///
/// Loads overrides from ``GET /api/settings/user/auto-trade`` and persists
/// via ``PUT``.  The page also surfaces the auto-pause state inline so users
/// don't have to navigate to the Trade tab to see why orders aren't dispatching.
import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/free_tier_gate.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';
import '../../launch/region_gate.dart';
import 'eligibility_preference_page.dart';
import 'symbol_preference_page.dart';

class AutoTradeSettingsPage extends StatefulWidget {
  const AutoTradeSettingsPage({super.key});

  @override
  State<AutoTradeSettingsPage> createState() => _AutoTradeSettingsPageState();
}

class _AutoTradeSettingsPageState extends State<AutoTradeSettingsPage> {
  // Independent mode flags — both can be true simultaneously (mode='both').
  bool _liveEnabled = false;
  bool _paperEnabled = false;

  double _positionSizePct = 2.0;
  double _leverageCap = 10.0;
  int _maxConcurrent = 3;
  double _notionalUsd = 500.0;

  // Full settings response — carries pausedReason, pausedAt.
  AutoTradeSettings? _settings;

  bool _loaded = false;
  bool _saving = false;
  bool _resuming = false;
  bool _resetting = false;
  bool _resettingPaper = false;
  String? _loadError;
  bool _usingDefaults = true;

  // Controller for the notional text field — must be a single instance
  // so it isn't leaked on every rebuild.
  late final TextEditingController _notionalCtrl;

  /// Derive the mode string from the two independent flags.
  String get _computedMode {
    if (_liveEnabled && _paperEnabled) return 'both';
    if (_liveEnabled) return 'live';
    if (_paperEnabled) return 'paper';
    return 'off';
  }

  @override
  void initState() {
    super.initState();
    _notionalCtrl = TextEditingController(text: _notionalUsd.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _notionalCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    final repo = AppConfigScope.of(context).repo;
    try {
      final s = await repo.fetchUserAutoTradeSettings();
      if (!mounted) return;
      final mode = s.mode?.toLowerCase() ?? 'off';
      setState(() {
        _settings = s;
        _liveEnabled = mode == 'live' || mode == 'both';
        _paperEnabled = mode == 'paper' || mode == 'both';
        _positionSizePct = s.positionSizePct ?? _positionSizePct;
        _leverageCap = s.leverageCap ?? _leverageCap;
        _maxConcurrent = s.maxConcurrentPositions ?? _maxConcurrent;
        _notionalUsd = s.notionalUsd ?? _notionalUsd;
        _notionalCtrl.text = _notionalUsd.toStringAsFixed(0);
        _notionalCtrl.selection = TextSelection.collapsed(offset: _notionalCtrl.text.length);
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

  /// Toggle the live switch.  Fires a real-money confirmation dialog before
  /// enabling.  Paper toggle bypasses the dialog.
  /// Saves the mode immediately (matching Trade-tab behaviour) so the
  /// engine picks up the change on the next signal without the user also
  /// having to tap the Save ✓ button.
  Future<void> _toggleLive(bool newValue) async {
    if (newValue) {
      final ok = await _confirmLiveFlip();
      if (ok != true) return;
    }
    setState(() => _liveEnabled = newValue);
    await _saveModeOnly();
  }

  /// Save only the execution mode, leaving sizing fields untouched.
  /// Called on every live/paper toggle so the engine sees the change
  /// immediately.  The Save ✓ button still persists all fields together.
  Future<void> _saveModeOnly() async {
    if (!mounted) return;
    final repo = AppConfigScope.of(context).repo;
    try {
      final saved = await repo.updateUserAutoTradeSettings(
        AutoTradeSettings(mode: _computedMode),
      );
      if (!mounted) return;
      setState(() => _settings = saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mode save failed: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = AppConfigScope.of(context).repo;
    final partial = AutoTradeSettings(
      mode: _computedMode,
      positionSizePct: _positionSizePct,
      leverageCap: _leverageCap,
      maxConcurrentPositions: _maxConcurrent,
      notionalUsd: _notionalUsd,
    );
    try {
      final saved = await repo.updateUserAutoTradeSettings(partial);
      if (!mounted) return;
      setState(() {
        _usingDefaults = saved.usingDefaults ?? false;
        // Refresh pause state from the server response.
        _settings = saved;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auto-trade settings saved'),
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

  Future<void> _resume() async {
    if (_resuming) return;
    setState(() => _resuming = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final cleared = await repo.resumeMineAutoTrade();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cleared
                ? 'Resumed. Next signal will dispatch.'
                : 'Already active — nothing to clear.',
          ),
          backgroundColor: LuminColors.success,
          duration: const Duration(seconds: 3),
        ),
      );
      // Reload to reflect the cleared pause state.
      setState(() {
        _loaded = false;
        _loadError = null;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resume failed: $e'),
          backgroundColor: LuminColors.loss,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    final isLive = scope.repo.isLive;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto-trade'),
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
      // Hands-off auto-execution is the Auto tier (B16). The engine also
      // enforces this server-side (signal_dispatch only auto-trades AUTO
      // users), so this gate is the UX layer — non-auto users see an
      // upgrade card instead of controls that wouldn't fire for them.
      body: canAuto(scope.tier)
          ? RegionGate(child: _bodyFor(isLive))
          : _autoUpsell(context),
    );
  }

  /// Shown to users below the Auto tier — explains that hands-off
  /// auto-execution is the ₹2000/mo Auto plan and routes to plans.
  Widget _autoUpsell(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(LuminSpacing.lg),
      children: [
        LuminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.smart_toy_rounded,
                  color: LuminColors.accent, size: 32),
              const SizedBox(height: LuminSpacing.sm),
              const Text(
                'Hands-off auto-trade',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: LuminSpacing.xs),
              const Text(
                'Auto-execution places every eligible signal on your '
                'connected exchange with no manual effort — the Auto plan. '
                'On the free and Assist plans you can still take any signal '
                'yourself; Auto runs it for you.',
                style: TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: LuminSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: LuminColors.accent,
                    foregroundColor: LuminColors.bgDeep,
                    padding: const EdgeInsets.symmetric(
                        vertical: LuminSpacing.md),
                  ),
                  onPressed: () => showUpgradeSheet(context),
                  child: const Text(
                    'See plans',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bodyFor(bool isLive) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    // When a load error occurred but we have previously-loaded data
    // (_settings is not null), render the settings in a stale state so
    // the user can still see and toggle their mode.  A warning banner
    // makes clear the data may be out of date.  If we have no data at
    // all (first open, no disk cache, engine unreachable) fall through
    // to the full-page error.
    if (_loadError != null && _settings == null) {
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
        if (_loadError != null)
          _StaleDataBanner(onRetry: () {
            setState(() {
              _loaded = false;
              _loadError = null;
            });
            _load();
          }),
        _scopeBanner(),
        _modeCard(),
        const SizedBox(height: LuminSpacing.md),
        _sizingCard(),
        const SizedBox(height: LuminSpacing.md),
        _eligibilityCard(),
        if (_paperEnabled) ...[
          const SizedBox(height: LuminSpacing.md),
          _paperEligibilityCard(),
        ],
        const SizedBox(height: LuminSpacing.md),
        _safetyNote(),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
  }

  Widget _scopeBanner() {
    final usingDefaults = _usingDefaults;
    final accent = usingDefaults ? LuminColors.textMuted : LuminColors.accent;
    final label = usingDefaults ? 'Using engine defaults.' : 'Custom — your overrides.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg, LuminSpacing.sm, LuminSpacing.lg, LuminSpacing.md,
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
                    'Saved to your profile. Settings take effect on the '
                    'next signal dispatch.',
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

  Widget _modeCard() {
    final isPaused = _settings?.isAutoPaused ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EXECUTION MODE',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            // ── Live toggle ──────────────────────────────────────────────
            _ModeToggleRow(
              icon: Icons.bolt,
              iconColor: LuminColors.loss,
              label: 'Live Trading',
              description: 'Real orders on Binance Futures — real money.',
              enabled: _liveEnabled,
              statusWidget: _liveStatusChip(isPaused),
              onChanged: _toggleLive,
            ),
            // Inline pause banner — only shown when live is on and paused.
            if (_liveEnabled && isPaused) ...[
              const SizedBox(height: LuminSpacing.sm),
              _PauseBanner(
                reason: _settings?.pausedReason,
                resuming: _resuming,
                onResume: _resume,
              ),
            ],
            const SizedBox(height: LuminSpacing.md),
            const Divider(color: LuminColors.cardBorder, height: 1),
            const SizedBox(height: LuminSpacing.md),
            // ── Paper toggle ─────────────────────────────────────────────
            _ModeToggleRow(
              icon: Icons.science_outlined,
              iconColor: LuminColors.warn,
              label: 'Paper Simulation',
              description: 'Simulated fills — no real money, zero risk.',
              enabled: _paperEnabled,
              statusWidget: _paperStatusChip(),
              onChanged: (v) async {
                setState(() => _paperEnabled = v);
                await _saveModeOnly();
              },
            ),
            const SizedBox(height: LuminSpacing.sm),
            // Active mode summary line
            _modeSummary(),
          ],
        ),
      ),
    );
  }

  Widget _liveStatusChip(bool isPaused) {
    if (!_liveEnabled) {
      return _StatusChip(label: 'Off', color: LuminColors.textMuted);
    }
    if (isPaused) {
      return _StatusChip(label: '⚠ Paused', color: LuminColors.warn, filled: true);
    }
    return _StatusChip(label: '● Armed', color: LuminColors.success, filled: true);
  }

  Widget _paperStatusChip() {
    if (!_paperEnabled) {
      return _StatusChip(label: 'Off', color: LuminColors.textMuted);
    }
    return _StatusChip(label: '● Active', color: LuminColors.accent, filled: true);
  }

  Widget _modeSummary() {
    final parts = <String>[];
    if (_liveEnabled) parts.add('Live');
    if (_paperEnabled) parts.add('Paper');
    final modeLabel = parts.isEmpty ? 'Off' : parts.join(' + ');
    return Text(
      'Mode: $modeLabel',
      style: const TextStyle(
        color: LuminColors.textSecondary,
        fontSize: 11,
        height: 1.4,
      ),
    );
  }

  /// "What auto-trades for me" — the eligibility filters (symbols,
  /// paths, regimes).  Each row opens its own picker; a single Reset
  /// action clears all three back to engine defaults (all eligible).
  Widget _eligibilityCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _paperEnabled
                        ? 'WHAT LIVE-TRADES FOR ME'
                        : 'WHAT AUTO-TRADES FOR ME',
                    style: const TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _resetting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _resetEligibility,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Reset to default',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: LuminSpacing.xs),
            const Text(
              'Narrow which signals place live orders for you. '
              'Defaults to everything eligible.',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            _eligibilityRow(
              icon: Icons.filter_list_alt,
              label: 'Symbols',
              subtitle: _eligibilitySummary(
                _settings?.symbolPreference, 'pairs'),
              onTap: () => _openPicker(const SymbolPreferencePage()),
            ),
            const Divider(color: LuminColors.cardBorder, height: 1),
            _eligibilityRow(
              icon: Icons.account_tree_outlined,
              label: 'Paths',
              subtitle: _eligibilitySummary(
                _settings?.pathPreference, 'setups'),
              onTap: () => _openPicker(const PathPreferencePage()),
            ),
            const Divider(color: LuminColors.cardBorder, height: 1),
            _eligibilityRow(
              icon: Icons.show_chart,
              label: 'Regimes',
              subtitle: _eligibilitySummary(
                _settings?.regimePreference, 'regimes'),
              onTap: () => _openPicker(const RegimePreferencePage()),
            ),
          ],
        ),
      ),
    );
  }

  /// PAPER counterpart of ``_eligibilityCard`` — only shown when paper (or
  /// both) mode is on.  Edits the independent ``paper_*_preference`` triple
  /// consumed by the per-user paper-book simulation, so a user can paper-
  /// test a different symbol/path/regime set than they live-trade.
  Widget _paperEligibilityCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'WHAT PAPER-TRADES FOR ME',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _resettingPaper
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _resetPaperEligibility,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Reset to default',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: LuminSpacing.xs),
            const Text(
              'Narrow which signals the engine simulates in your paper book. '
              'Separate from your live filters above.',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            _eligibilityRow(
              icon: Icons.filter_list_alt,
              label: 'Symbols',
              subtitle: _eligibilitySummary(
                _settings?.paperSymbolPreference, 'pairs'),
              onTap: () => _openPicker(const PaperSymbolPreferencePage()),
            ),
            const Divider(color: LuminColors.cardBorder, height: 1),
            _eligibilityRow(
              icon: Icons.account_tree_outlined,
              label: 'Paths',
              subtitle: _eligibilitySummary(
                _settings?.paperPathPreference, 'setups'),
              onTap: () => _openPicker(const PaperPathPreferencePage()),
            ),
            const Divider(color: LuminColors.cardBorder, height: 1),
            _eligibilityRow(
              icon: Icons.show_chart,
              label: 'Regimes',
              subtitle: _eligibilitySummary(
                _settings?.paperRegimePreference, 'regimes'),
              onTap: () => _openPicker(const PaperRegimePreferencePage()),
            ),
          ],
        ),
      ),
    );
  }

  /// One-line summary of a preference list for the eligibility rows.
  String _eligibilitySummary(List<String>? pref, String noun) {
    if (pref == null) return 'All $noun (default)';
    if (pref.isEmpty) return 'Blocked — none';
    return '${pref.length} selected';
  }

  Widget _eligibilityRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LuminSpacing.sm),
        child: Row(
          children: [
            Icon(icon, color: LuminColors.accent, size: 18),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: LuminColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  /// Push a picker and refresh the summaries when it returns.
  Future<void> _openPicker(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    // Re-pull so the row summaries reflect the just-saved selection.
    setState(() {
      _loaded = false;
      _loadError = null;
    });
    await _load();
  }

  /// Reset all three eligibility filters to engine defaults (all
  /// eligible) by clearing the stored rows.  Sends explicit nulls so the
  /// engine drops the columns — the symbol/path/regime analogue of the
  /// Pre-TP / Invalidation "Reset to engine defaults" action.
  Future<void> _resetEligibility() async {
    if (_resetting) return;
    setState(() => _resetting = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final saved = await repo.updateUserAutoTradeSettings(
        const AutoTradeSettings(
          symbolPreference: null,
          symbolPreferenceSet: true,
          pathPreference: null,
          pathPreferenceSet: true,
          regimePreference: null,
          regimePreferenceSet: true,
        ),
      );
      if (!mounted) return;
      setState(() => _settings = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eligibility reset — all signals can auto-trade'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset failed: $e'),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  /// Reset the PAPER eligibility triple to engine defaults (all eligible)
  /// by clearing the ``paper_*_preference`` rows.  Independent of the live
  /// reset above.
  Future<void> _resetPaperEligibility() async {
    if (_resettingPaper) return;
    setState(() => _resettingPaper = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final saved = await repo.updateUserAutoTradeSettings(
        const AutoTradeSettings(
          paperSymbolPreference: null,
          paperSymbolPreferenceSet: true,
          paperPathPreference: null,
          paperPathPreferenceSet: true,
          paperRegimePreference: null,
          paperRegimePreferenceSet: true,
        ),
      );
      if (!mounted) return;
      setState(() => _settings = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paper eligibility reset — all signals simulate'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset failed: $e'),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) setState(() => _resettingPaper = false);
    }
  }

  Widget _sizingCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SIZING',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            _slider(
              label: 'Position size',
              value: '${_positionSizePct.toStringAsFixed(1)}% of equity',
              slider: Slider(
                value: _positionSizePct,
                min: 0.5,
                max: 10.0,
                divisions: 19,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: (v) => setState(() => _positionSizePct = v),
              ),
            ),
            _slider(
              label: 'Leverage cap',
              value: '${_leverageCap.toStringAsFixed(0)}x',
              slider: Slider(
                value: _leverageCap,
                min: 1,
                max: 30,
                divisions: 29,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: (v) => setState(() => _leverageCap = v),
              ),
            ),
            _slider(
              label: 'Max concurrent positions',
              value: '$_maxConcurrent',
              slider: Slider(
                value: _maxConcurrent.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: (v) => setState(() => _maxConcurrent = v.round()),
              ),
            ),
            _notionalSliderWithInput(),
          ],
        ),
      ),
    );
  }

  /// Notional slider with an inline text field for direct dollar-amount entry.
  Widget _notionalSliderWithInput() {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Position notional (live)',
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 80,
                height: 32,
                child: TextField(
                  controller: _notionalCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: LuminColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '\$',
                    prefixStyle: TextStyle(
                      color: LuminColors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: LuminColors.cardBorder),
                      borderRadius: BorderRadius.all(Radius.circular(LuminRadii.sm)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: LuminColors.accent),
                      borderRadius: BorderRadius.all(Radius.circular(LuminRadii.sm)),
                    ),
                  ),
                  onChanged: (raw) {
                    final parsed = double.tryParse(raw);
                    if (parsed == null) return;
                    final clamped = parsed.clamp(5.0, 2000.0);
                    final snapped = (clamped / 5).round() * 5.0;
                    setState(() => _notionalUsd = snapped);
                  },
                ),
              ),
            ],
          ),
          Slider(
            value: _notionalUsd,
            min: 5,
            max: 2000,
            divisions: 80,
            activeColor: LuminColors.accent,
            inactiveColor: LuminColors.cardBorder,
            onChanged: (v) => setState(() {
              _notionalUsd = (v / 5).round() * 5.0;
              _notionalCtrl.text = _notionalUsd.toStringAsFixed(0);
              _notionalCtrl.selection = TextSelection.collapsed(offset: _notionalCtrl.text.length);
            }),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required String value,
    required Widget slider,
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
        ],
      ),
    );
  }

  Widget _safetyNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.warn.withOpacity(0.08),
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(color: LuminColors.warn.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.shield_outlined, color: LuminColors.warn, size: 16),
            SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Text(
                'Live mode requires API keys connected. '
                'B12 caps leverage at 30×. '
                'Set notional ≤ (Futures wallet ÷ leverage) to avoid -2019.',
                style: TextStyle(
                  color: LuminColors.warn,
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

  Future<bool?> _confirmLiveFlip() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: LuminColors.loss, size: 20),
            SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Text(
                'Enable LIVE auto-trade?',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lumin will place real Binance Futures orders on every signal '
              'automatically — no per-signal confirmation.',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            SizedBox(height: LuminSpacing.sm),
            Text(
              '• Sized by your Position notional × leverage cap\n'
              '• One order per signal (idempotent)\n'
              '• Tap Save then come back to disable',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: LuminColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.loss,
              foregroundColor: LuminColors.bgDeep,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Enable LIVE',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

/// A toggle row for one execution mode (Live or Paper).
class _ModeToggleRow extends StatelessWidget {
  const _ModeToggleRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.description,
    required this.enabled,
    required this.statusWidget,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String description;
  final bool enabled;
  final Widget statusWidget;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: enabled ? iconColor : LuminColors.textMuted, size: 20),
            const SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled ? LuminColors.textPrimary : LuminColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            statusWidget,
            const SizedBox(width: LuminSpacing.sm),
            Switch(
              value: enabled,
              onChanged: onChanged,
              activeColor: iconColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            description,
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Banner shown when the last settings fetch failed but previously-loaded
/// data is being displayed.  Gives context that the values may be stale
/// and offers an inline retry button.
class _StaleDataBanner extends StatelessWidget {
  const _StaleDataBanner({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg, LuminSpacing.md, LuminSpacing.lg, 0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.md,
          vertical: LuminSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: LuminColors.warn.withOpacity(0.08),
          borderRadius: BorderRadius.circular(LuminRadii.sm),
          border: Border.all(color: LuminColors.warn.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: LuminColors.warn, size: 14),
            const SizedBox(width: LuminSpacing.sm),
            const Expanded(
              child: Text(
                'Showing last saved state — could not reach engine.',
                style: TextStyle(
                  color: LuminColors.warn,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Retry',
                style: TextStyle(color: LuminColors.warn, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact status chip — coloured pill label.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    this.filled = false,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(LuminRadii.pill),
        border: Border.all(
          color: filled ? color.withOpacity(0.50) : Colors.transparent,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Inline pause-reason banner shown below the Live toggle when paused.
class _PauseBanner extends StatelessWidget {
  const _PauseBanner({
    required this.reason,
    required this.resuming,
    required this.onResume,
  });

  final String? reason;
  final bool resuming;
  final VoidCallback onResume;

  String get _bodyText {
    if (reason == 'insufficient_margin') {
      return 'Engine paused after 3+ rejected orders — Futures wallet was '
          'empty. Top up your Futures wallet, then tap Resume.';
    }
    return 'Engine paused: ${reason ?? "unknown"}. Tap Resume once resolved.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.warn.withOpacity(0.08),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: LuminColors.warn.withOpacity(0.40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pause_circle_outline, color: LuminColors.warn, size: 16),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Orders paused',
                  style: TextStyle(
                    color: LuminColors.warn,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _bodyText,
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: LuminSpacing.sm),
          resuming
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: LuminColors.warn,
                  ),
                )
              : TextButton(
                  onPressed: onResume,
                  style: TextButton.styleFrom(
                    foregroundColor: LuminColors.warn,
                    padding: const EdgeInsets.symmetric(
                        horizontal: LuminSpacing.sm, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Resume',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

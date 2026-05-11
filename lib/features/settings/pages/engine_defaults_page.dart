/// Engine defaults — owner-only editor for the engine-wide
/// pre-TP + auto-trade configuration that drives the live signal
/// stream.  Phase 2 split: per-user settings live on the existing
/// PreTpSettingsPage / AutoTradeSettingsPage; this page is the
/// operator's view of what the **engine itself** consumes.
///
/// Writes go to ``PUT /api/settings/pretp`` and
/// ``PUT /api/settings/auto-trade`` — both gated to ``OWNER_TIER`` by
/// engine PR #355.  Non-owner users never see the Settings → Engine
/// defaults row (gated in ``SettingsPage``).
///
/// Deliberately a slim entry point: the existing per-user pages
/// already carry all the field-level UI; here we offer a compact
/// summary + a single "View current values" expand for each.  The
/// owner can drill down by going through the same per-user pages
/// to see field-by-field; this page is the editor for the engine
/// view.
import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';

class EngineDefaultsPage extends StatefulWidget {
  const EngineDefaultsPage({super.key});

  @override
  State<EngineDefaultsPage> createState() => _EngineDefaultsPageState();
}

class _EngineDefaultsPageState extends State<EngineDefaultsPage> {
  PretpSettings? _pretp;
  AutoTradeSettings? _auto;
  bool _loaded = false;
  String? _loadError;
  bool _savingPretpEnabled = false;
  bool _savingAutoMode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    final repo = AppConfigScope.of(context).repo;
    try {
      final results = await Future.wait([
        repo.fetchPretpSettings(),
        repo.fetchAutoTradeSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _pretp = results[0] as PretpSettings;
        _auto = results[1] as AutoTradeSettings;
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

  Future<void> _togglePretpEnabled(bool value) async {
    if (_savingPretpEnabled) return;
    setState(() => _savingPretpEnabled = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final saved = await repo.updatePretpSettings(
        PretpSettings(enabled: value),
      );
      if (!mounted) return;
      setState(() => _pretp = saved);
    } on ApiError catch (e) {
      _toast('Save failed: ${e.message}');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _savingPretpEnabled = false);
    }
  }

  Future<void> _setEngineMode(String mode) async {
    if (_savingAutoMode) return;
    setState(() => _savingAutoMode = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final saved = await repo.updateAutoTradeSettings(
        AutoTradeSettings(mode: mode),
      );
      if (!mounted) return;
      setState(() => _auto = saved);
    } on ApiError catch (e) {
      _toast('Save failed: ${e.message}');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _savingAutoMode = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    final isLive = scope.repo.isLive;
    return Scaffold(
      appBar: AppBar(title: const Text('Engine defaults')),
      body: _body(isLive),
    );
  }

  Widget _body(bool isLive) {
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
              const Icon(
                Icons.cloud_off,
                color: LuminColors.textMuted,
                size: 36,
              ),
              const SizedBox(height: LuminSpacing.md),
              const Text(
                'Could not load engine defaults',
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
        _pretpCard(),
        const SizedBox(height: LuminSpacing.md),
        _autoTradeCard(),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
  }

  Widget _scopeBanner() {
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
          color: LuminColors.warn.withOpacity(0.10),
          borderRadius: BorderRadius.circular(LuminRadii.sm),
          border: Border.all(color: LuminColors.warn.withOpacity(0.30)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: LuminColors.warn,
              size: 16,
            ),
            const SizedBox(width: LuminSpacing.sm),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Engine-wide controls.',
                    style: TextStyle(
                      color: LuminColors.warn,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Changes here affect what the engine fires for every '
                    'subscriber. Per-user overrides are on the Auto-trade '
                    'and Pre-TP pages.',
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

  Widget _pretpCard() {
    final pretp = _pretp;
    final enabled = pretp?.enabled ?? false;
    final threshold = pretp?.thresholdPct;
    final atr = pretp?.atrMultiplier;
    final fee = pretp?.feeFloorPct;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.shield_moon_outlined,
                  color: LuminColors.accent,
                  size: 18,
                ),
                const SizedBox(width: LuminSpacing.sm),
                const Expanded(
                  child: Text(
                    'Pre-TP grab (engine)',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_savingPretpEnabled)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: enabled,
                    onChanged: _togglePretpEnabled,
                    activeColor: LuminColors.accent,
                  ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            _kv('Threshold', _fmtPct(threshold)),
            _kv('ATR multiplier', atr == null ? '—' : '${atr.toStringAsFixed(2)}x'),
            _kv('Fee floor', _fmtPct(fee)),
            const SizedBox(height: LuminSpacing.xs),
            const Text(
              'Field-level edits (regime allowlist, ATR, fee floor) — use the '
              'Pre-TP page; values you set there belong to YOUR profile only. '
              'To change engine-wide thresholds, edit the engine env vars.',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _autoTradeCard() {
    final auto = _auto;
    final mode = auto?.mode ?? 'off';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_mode, color: LuminColors.accent, size: 18),
                SizedBox(width: LuminSpacing.sm),
                Expanded(
                  child: Text(
                    'Auto-execution mode (engine)',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            Row(
              children: [
                for (final m in const ['off', 'paper', 'live'])
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: m == 'live' ? 0 : LuminSpacing.sm,
                      ),
                      child: _modePill(m, mode),
                    ),
                  ),
              ],
            ),
            if (_savingAutoMode) ...[
              const SizedBox(height: LuminSpacing.md),
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
            const SizedBox(height: LuminSpacing.sm),
            _kv(
              'Position size',
              auto?.positionSizePct == null
                  ? '—'
                  : '${auto!.positionSizePct!.toStringAsFixed(2)}%',
            ),
            _kv(
              'Leverage cap',
              auto?.leverageCap == null
                  ? '—'
                  : '${auto!.leverageCap!.toStringAsFixed(0)}x',
            ),
            _kv(
              'Max concurrent',
              auto?.maxConcurrentPositions == null
                  ? '—'
                  : '${auto!.maxConcurrentPositions}',
            ),
            const SizedBox(height: LuminSpacing.xs),
            const Text(
              'Mode flip here changes what the engine itself runs (paper sim, '
              'live broker, or off). Field-level edits (sizing, leverage) — '
              'use the Auto-trade page; those belong to YOUR profile.',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modePill(String mode, String currentMode) {
    final selected = mode == currentMode;
    final colour = switch (mode) {
      'live' => LuminColors.loss,
      'paper' => LuminColors.warn,
      _ => LuminColors.textMuted,
    };
    return InkWell(
      onTap: _savingAutoMode ? null : () => _setEngineMode(mode),
      borderRadius: BorderRadius.circular(LuminRadii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: LuminSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? colour.withOpacity(0.15) : LuminColors.bgElevated,
          borderRadius: BorderRadius.circular(LuminRadii.sm),
          border: Border.all(
            color: selected ? colour.withOpacity(0.50) : LuminColors.cardBorder,
          ),
        ),
        child: Center(
          child: Text(
            mode.toUpperCase(),
            style: TextStyle(
              color: selected ? colour : LuminColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            v,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtPct(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(2)}%';
}

/// Auto-trade settings — execution-mode + sizing controls.
///
/// Loads the engine's effective state from ``GET /api/settings/auto-trade``
/// on init and persists changes via ``PUT`` on save.  Mode change routes
/// through the same engine path as the Trade tab's mode toggle so flipping
/// from this page actually switches the engine's auto-execution mode.
import 'package:flutter/material.dart';

import '../../../data/api_client.dart';
import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/owner_only_banner.dart';
import '../../../shared/widgets/preview_badge.dart';

class AutoTradeSettingsPage extends StatefulWidget {
  const AutoTradeSettingsPage({super.key});

  @override
  State<AutoTradeSettingsPage> createState() => _AutoTradeSettingsPageState();
}

class _AutoTradeSettingsPageState extends State<AutoTradeSettingsPage> {
  // 0 = Off, 1 = Paper, 2 = Live — local UI representation.
  int _mode = 1;
  double _positionSizePct = 2.0;
  double _leverageCap = 10.0;     // 1x..30x — B12 hard cap
  int _maxConcurrent = 3;

  bool _loaded = false;
  bool _saving = false;
  String? _loadError;

  static const _kModeIndexToString = {0: 'off', 1: 'paper', 2: 'live'};
  static const _kModeStringToIndex = {'off': 0, 'paper': 1, 'live': 2};

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
      final s = await repo.fetchAutoTradeSettings();
      if (!mounted) return;
      setState(() {
        if (s.mode != null) {
          _mode = _kModeStringToIndex[s.mode!.toLowerCase()] ?? _mode;
        }
        _positionSizePct = s.positionSizePct ?? _positionSizePct;
        _leverageCap = s.leverageCap ?? _leverageCap;
        _maxConcurrent = s.maxConcurrentPositions ?? _maxConcurrent;
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
    final partial = AutoTradeSettings(
      mode: _kModeIndexToString[_mode],
      positionSizePct: _positionSizePct,
      leverageCap: _leverageCap,
      maxConcurrentPositions: _maxConcurrent,
    );
    try {
      await repo.updateAutoTradeSettings(partial);
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    final isLive = scope.repo.isLive;
    // Engine PR #355 + #356 gate PUT /api/settings/auto-trade +
    // POST /api/auto-mode to OWNER_TIER.  Hide Save + disable form
    // inputs when tier != owner.
    final tier = scope.tier;
    final canEdit = tier == null || tier == 'owner';
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
    final list = ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        if (!isLive) const PreviewBadge(),
        if (!canEdit) const OwnerOnlyBanner(),
        _modeCard(),
        const SizedBox(height: LuminSpacing.md),
        _sizingCard(),
        const SizedBox(height: LuminSpacing.md),
        _safetyNote(),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
    // Read-only render for non-owner tiers: AbsorbPointer blocks all
    // input below the AppBar; Opacity visually signals disabled state.
    // Engine 403 remains the source-of-truth backstop.
    if (canEdit) return list;
    return Opacity(
      opacity: 0.65,
      child: AbsorbPointer(absorbing: true, child: list),
    );
  }

  Widget _modeCard() {
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
            Row(
              children: [
                _modeBtn(0, 'Off', Icons.power_settings_new, LuminColors.textMuted),
                const SizedBox(width: LuminSpacing.sm),
                _modeBtn(1, 'Paper', Icons.science_outlined, LuminColors.warn),
                const SizedBox(width: LuminSpacing.sm),
                _modeBtn(2, 'Live', Icons.bolt, LuminColors.loss),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            Text(
              _modeDesc(_mode),
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeBtn(int idx, String label, IconData icon, Color color) {
    final selected = _mode == idx;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(LuminRadii.md),
          onTap: () => setState(() => _mode = idx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.15) : LuminColors.bgElevated,
              borderRadius: BorderRadius.circular(LuminRadii.md),
              border: Border.all(
                color: selected ? color.withOpacity(0.50) : LuminColors.cardBorder,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? color : LuminColors.textSecondary, size: 22),
                const SizedBox(height: LuminSpacing.xs),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : LuminColors.textSecondary,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _modeDesc(int m) {
    switch (m) {
      case 0:
        return 'Auto-trade disabled. Signals still publish to Telegram.';
      case 1:
        return 'Paper mode — fills are simulated, no real orders. Zero risk.';
      case 2:
        return 'Live — real orders on Binance Futures. Risk gates active.';
      default:
        return '';
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
                'Live mode requires API keys + paper-mode validation. '
                'B12 caps leverage at 30x.',
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
}

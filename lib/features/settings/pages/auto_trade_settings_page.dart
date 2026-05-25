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
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';
import '../../launch/region_gate.dart';

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
  String? _loadError;
  bool _usingDefaults = true;

  /// Derive the mode string from the two independent flags.
  String get _computedMode {
    if (_liveEnabled && _paperEnabled) return 'both';
    if (_liveEnabled) return 'live';
    if (_paperEnabled) return 'paper';
    return 'off';
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
  Future<void> _toggleLive(bool newValue) async {
    if (newValue) {
      final ok = await _confirmLiveFlip();
      if (ok != true) return;
    }
    setState(() => _liveEnabled = newValue);
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
      body: RegionGate(child: _bodyFor(isLive)),
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
        _modeCard(),
        const SizedBox(height: LuminSpacing.md),
        _sizingCard(),
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
              onChanged: (v) => setState(() => _paperEnabled = v),
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
    final controller = TextEditingController(
      text: _notionalUsd.toStringAsFixed(0),
    );
    // Keep cursor at end after external setState rebuilds.
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
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
                  controller: controller,
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

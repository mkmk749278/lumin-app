/// Auto-trade settings — execution-mode + sizing controls.
///
/// Mirrors the Trade tab's mode toggle (Off / Paper / Live) but adds the
/// sizing dials that the Trade tab doesn't expose: position-size %, leverage
/// cap, and max concurrent positions. State is session-only until the
/// backend wires up `/api/auto-mode`.
import 'package:flutter/material.dart';

import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';

class AutoTradeSettingsPage extends StatefulWidget {
  const AutoTradeSettingsPage({super.key});

  @override
  State<AutoTradeSettingsPage> createState() => _AutoTradeSettingsPageState();
}

class _AutoTradeSettingsPageState extends State<AutoTradeSettingsPage> {
  // 0 = Off, 1 = Paper, 2 = Live
  int _mode = 1;
  double _positionSizePct = 2.0; // % of equity per trade
  double _leverageCap = 10.0;     // 1x..30x — B12 hard cap
  int _maxConcurrent = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto-trade'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
            tooltip: 'Save',
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const PreviewBadge(),
          _modeCard(),
          const SizedBox(height: LuminSpacing.md),
          _sizingCard(),
          const SizedBox(height: LuminSpacing.md),
          _safetyNote(),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
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

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved (session only — backend wiring pending)'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

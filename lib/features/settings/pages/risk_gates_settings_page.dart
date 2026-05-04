/// Risk gates settings — circuit-breaker thresholds.
///
/// These mirror engine-side risk constants — daily-loss kill, leverage cap,
/// equity floor.  When tripped, auto-trade halts until manual reset.
import 'package:flutter/material.dart';

import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';

class RiskGatesSettingsPage extends StatefulWidget {
  const RiskGatesSettingsPage({super.key});

  @override
  State<RiskGatesSettingsPage> createState() => _RiskGatesSettingsPageState();
}

class _RiskGatesSettingsPageState extends State<RiskGatesSettingsPage> {
  double _dailyLossKillPct = 5.0;   // % of equity
  double _maxLeverage = 10.0;        // capped at 30x by B12
  double _minEquityFloorUsd = 100.0;
  bool _haltOnConsecutiveLosses = true;
  int _consecutiveLossesLimit = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Risk gates'),
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
          _gatesCard(),
          const SizedBox(height: LuminSpacing.md),
          _streakCard(),
          const SizedBox(height: LuminSpacing.md),
          _disclaimer(),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  Widget _gatesCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CIRCUIT BREAKERS',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            _slider(
              label: 'Daily-loss kill',
              value: '${_dailyLossKillPct.toStringAsFixed(1)}% of equity',
              slider: Slider(
                value: _dailyLossKillPct,
                min: 1.0,
                max: 15.0,
                divisions: 28,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: (v) => setState(() => _dailyLossKillPct = v),
              ),
              hint: 'Auto-halt for 24h once daily PnL ≤ –${_dailyLossKillPct.toStringAsFixed(1)}%',
            ),
            _slider(
              label: 'Max leverage',
              value: '${_maxLeverage.toStringAsFixed(0)}x',
              slider: Slider(
                value: _maxLeverage,
                min: 1,
                max: 30,
                divisions: 29,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: (v) => setState(() => _maxLeverage = v),
              ),
              hint: 'Hard-capped at 30x per B12',
            ),
            _slider(
              label: 'Min equity floor',
              value: '\$${_minEquityFloorUsd.toStringAsFixed(0)}',
              slider: Slider(
                value: _minEquityFloorUsd,
                min: 50,
                max: 1000,
                divisions: 19,
                activeColor: LuminColors.accent,
                inactiveColor: LuminColors.cardBorder,
                onChanged: (v) => setState(() => _minEquityFloorUsd = v),
              ),
              hint: 'Halt if account equity drops below this',
            ),
          ],
        ),
      ),
    );
  }

  Widget _streakCard() {
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
                    'Halt on consecutive losses',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Switch(
                  value: _haltOnConsecutiveLosses,
                  activeColor: LuminColors.accent,
                  onChanged: (v) => setState(() => _haltOnConsecutiveLosses = v),
                ),
              ],
            ),
            if (_haltOnConsecutiveLosses) ...[
              const SizedBox(height: LuminSpacing.md),
              _slider(
                label: 'Streak limit',
                value: '$_consecutiveLossesLimit losses',
                slider: Slider(
                  value: _consecutiveLossesLimit.toDouble(),
                  min: 2,
                  max: 10,
                  divisions: 8,
                  activeColor: LuminColors.accent,
                  inactiveColor: LuminColors.cardBorder,
                  onChanged: (v) =>
                      setState(() => _consecutiveLossesLimit = v.round()),
                ),
                hint: 'Halt auto-trade after this many losses in a row',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required String value,
    required Widget slider,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminSpacing.md),
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
          if (hint != null)
            Text(
              hint,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 11,
                height: 1.3,
              ),
            ),
        ],
      ),
    );
  }

  Widget _disclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.loss.withOpacity(0.08),
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(color: LuminColors.loss.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.warning_amber_rounded, color: LuminColors.loss, size: 16),
            SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Text(
                'Risk gates protect capital but cannot eliminate loss. '
                'Crypto futures can liquidate in seconds during volatile moves.',
                style: TextStyle(
                  color: LuminColors.loss,
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

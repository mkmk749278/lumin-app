/// Pre-TP grab settings — early-profit-taking knobs.
///
/// Pre-TP grab moves SL to breakeven once price has captured a configurable
/// fraction of the path to TP1 (covers fees + safety margin).  This page
/// exposes the knobs that the engine reads from `config.PRE_TP_*`.
import 'package:flutter/material.dart';

import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';

class PreTpSettingsPage extends StatefulWidget {
  const PreTpSettingsPage({super.key});

  @override
  State<PreTpSettingsPage> createState() => _PreTpSettingsPageState();
}

class _PreTpSettingsPageState extends State<PreTpSettingsPage> {
  bool _enabled = true;
  double _grabPct = 0.50;     // fraction of TP1 distance
  double _atrMult = 0.30;     // ATR-floor multiplier
  double _feeFloor = 0.12;    // % — minimum profit before BE move

  // Regime allowlist
  bool _regimeTrending = true;
  bool _regimeRanging = true;
  bool _regimeChoppy = false;

  // Setup blacklist (false = blacklisted)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-TP grab'),
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
          _masterCard(),
          const SizedBox(height: LuminSpacing.md),
          _thresholdsCard(),
          const SizedBox(height: LuminSpacing.md),
          _regimeCard(),
          const SizedBox(height: LuminSpacing.md),
          _setupsCard(),
          const SizedBox(height: LuminSpacing.xl),
        ],
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

  void _save() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved (session only — backend wiring pending)'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

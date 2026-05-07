/// Agents settings — per-evaluator enable/disable toggles.
///
/// 15 evaluator paths, each owned by an agent persona.  Disabling an agent
/// suppresses its setup at the channel-router level (no Telegram dispatch,
/// no auto-trade entry).  Mirrors `config.AGENT_ENABLED_*` flags.
import 'package:flutter/material.dart';

import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';
import '../../../shared/widgets/preview_badge.dart';

class AgentsSettingsPage extends StatefulWidget {
  const AgentsSettingsPage({super.key});

  @override
  State<AgentsSettingsPage> createState() => _AgentsSettingsPageState();
}

class _AgentsSettingsPageState extends State<AgentsSettingsPage> {
  // (display name, setup code, enabled-by-default)
  final List<List<dynamic>> _agents = [
    ['The Architect', 'SR_FLIP_RETEST', true],
    ['The Counter-Puncher', 'LIQUIDITY_SWEEP_REVERSAL', true],
    ['The Reclaimer', 'FAILED_AUCTION_RECLAIM', true],
    ['The Coil Hunter', 'QUIET_COMPRESSION_BREAK', true],
    ['The Tracker', 'VOLUME_SURGE_BREAKOUT', true],
    ['The Crusher', 'BREAKDOWN_SHORT', true],
    ['The Contrarian', 'FUNDING_EXTREME_SIGNAL', true],
    ['The Whale Hunter', 'WHALE_MOMENTUM', true],
    ['The Cascade Catcher', 'LIQUIDATION_REVERSAL', true],
    ['The Continuation Specialist', 'CONTINUATION_LIQUIDITY_SWEEP', true],
    ['The Divergence Reader', 'DIVERGENCE_CONTINUATION', true],
    ['The Pullback Sniper', 'TREND_PULLBACK_EMA', true],
    ['The Aftermath Trader', 'POST_DISPLACEMENT_CONTINUATION', true],
    ['The Range Breaker', 'OPENING_RANGE_BREAKOUT', true],
  ];

  @override
  Widget build(BuildContext context) {
    final activeCount = _agents.where((a) => a[2] as bool).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
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
          _summaryCard(activeCount),
          const SizedBox(height: LuminSpacing.md),
          _bulkActionsCard(),
          const SizedBox(height: LuminSpacing.md),
          _agentsCard(),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  Widget _summaryCard(int activeCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: LuminColors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(LuminRadii.md),
              ),
              alignment: Alignment.center,
              child: Text(
                '$activeCount',
                style: const TextStyle(
                  color: LuminColors.accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: LuminSpacing.md),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active agents',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'of 15 evaluators',
                    style: TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
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

  Widget _bulkActionsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: _bulkBtn('Enable all', LuminColors.success, () {
              setState(() {
                for (final a in _agents) {
                  a[2] = true;
                }
              });
            }),
          ),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: _bulkBtn('Disable all', LuminColors.loss, () {
              setState(() {
                for (final a in _agents) {
                  a[2] = false;
                }
              });
            }),
          ),
        ],
      ),
    );
  }

  Widget _bulkBtn(String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LuminRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(LuminRadii.md),
            border: Border.all(color: color.withOpacity(0.30)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _agentsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'EVALUATORS',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            for (int i = 0; i < _agents.length; i++) ...[
              _agentRow(i),
              if (i < _agents.length - 1)
                const Divider(
                  color: LuminColors.cardBorder,
                  height: 1,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _agentRow(int idx) {
    final name = _agents[idx][0] as String;
    final code = _agents[idx][1] as String;
    final enabled = _agents[idx][2] as bool;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LuminSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: enabled
                        ? LuminColors.textPrimary
                        : LuminColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  code,
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 10,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeColor: LuminColors.accent,
            onChanged: (v) => setState(() => _agents[idx][2] = v),
          ),
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

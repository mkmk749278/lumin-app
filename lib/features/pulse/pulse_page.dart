/// Pulse — engine status dashboard.
///
/// Real-looking dashboard built against [mockEngine] + [mockSignals].
/// When the FastAPI backend lands, swap the mock-data imports for a
/// repository call — UI components don't change.
import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import '../../shared/widgets/stat_pill.dart';

class PulsePage extends StatelessWidget {
  const PulsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pulse')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const PreviewBadge(),
          _EngineStatusCard(),
          const SizedBox(height: LuminSpacing.md),
          _RegimeAndPnlRow(),
          const SizedBox(height: LuminSpacing.md),
          _DailyLossBudgetCard(),
          const SizedBox(height: LuminSpacing.md),
          _RecentSignalsCard(),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }
}

class _EngineStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isHealthy = mockEngine.status == 'Healthy';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isHealthy ? LuminColors.success : LuminColors.warn,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isHealthy ? LuminColors.success : LuminColors.warn)
                        .withOpacity(0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Engine ${mockEngine.status.toLowerCase()}',
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Up ${mockEngine.uptime} • scanning 75 pairs',
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.flash_on,
              color: LuminColors.accent,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _RegimeAndPnlRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pnlPositive = mockEngine.todayPnlUsd >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: LuminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatPill(
                    label: 'Regime',
                    value: mockEngine.regime,
                    icon: Icons.bar_chart_outlined,
                    valueColor: LuminColors.accent,
                  ),
                  const SizedBox(height: LuminSpacing.sm),
                  Text(
                    '${mockEngine.regimePctTrending.toStringAsFixed(1)}% of cycles',
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: LuminSpacing.md),
          Expanded(
            child: LuminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatPill(
                    label: "Today's P&L",
                    value:
                        '${pnlPositive ? '+' : ''}\$${mockEngine.todayPnlUsd.toStringAsFixed(2)}',
                    valueColor:
                        pnlPositive ? LuminColors.success : LuminColors.loss,
                    icon: pnlPositive
                        ? Icons.trending_up
                        : Icons.trending_down,
                  ),
                  const SizedBox(height: LuminSpacing.sm),
                  Text(
                    '${pnlPositive ? '+' : ''}${mockEngine.todayPnlPct.toStringAsFixed(2)}% on margin',
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyLossBudgetCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final used = mockEngine.dailyLossUsedUsd.abs();
    final budget = mockEngine.dailyLossBudgetUsd;
    final pct = budget == 0 ? 0.0 : (used / budget).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: LuminColors.accent, size: 16),
                const SizedBox(width: LuminSpacing.xs),
                const Text(
                  'DAILY LOSS BUDGET',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '\$${used.toStringAsFixed(2)} / \$${budget.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(LuminRadii.pill),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: LuminColors.bgElevated,
                valueColor: AlwaysStoppedAnimation(
                  pct < 0.7
                      ? LuminColors.success
                      : pct < 0.95
                          ? LuminColors.warn
                          : LuminColors.loss,
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.xs),
            Text(
              pct < 0.01
                  ? 'No losses today — budget intact'
                  : '${(pct * 100).toStringAsFixed(0)}% of daily budget used',
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentSignalsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final recent = mockSignals.take(3).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.history, color: LuminColors.accent, size: 16),
                SizedBox(width: LuminSpacing.xs),
                Text(
                  'RECENT SIGNALS',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            for (final sig in recent) _RecentSignalRow(sig: sig),
          ],
        ),
      ),
    );
  }
}

class _RecentSignalRow extends StatelessWidget {
  const _RecentSignalRow({required this.sig});
  final MockSignal sig;

  Color _statusColor() {
    switch (sig.status) {
      case 'TP1_HIT':
      case 'TP2_HIT':
      case 'TP3_HIT':
        return LuminColors.success;
      case 'SL_HIT':
        return LuminColors.loss;
      case 'INVALIDATED':
        return LuminColors.textMuted;
      default:
        return LuminColors.accent;
    }
  }

  String _agoLabel() {
    if (sig.minutesAgo < 60) return '${sig.minutesAgo}m ago';
    if (sig.minutesAgo < 1440) return '${(sig.minutesAgo / 60).round()}h ago';
    return '${(sig.minutesAgo / 1440).round()}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final pnlPositive = sig.pnlPct >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LuminSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: _statusColor(),
              borderRadius: BorderRadius.circular(LuminRadii.pill),
            ),
          ),
          const SizedBox(width: LuminSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      sig.symbol,
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: LuminSpacing.xs),
                    Text(
                      sig.direction,
                      style: TextStyle(
                        color: sig.direction == 'LONG'
                            ? LuminColors.success
                            : LuminColors.loss,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: LuminSpacing.xs),
                    Text(
                      '• ${sig.status}',
                      style: TextStyle(
                        color: _statusColor(),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${sig.agentName} • ${_agoLabel()}',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${pnlPositive ? '+' : ''}${sig.pnlPct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: pnlPositive ? LuminColors.success : LuminColors.loss,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

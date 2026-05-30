/// Agents — 15 evaluator personas + per-agent drill-down.
///
/// The detail bottom sheet fetches that agent's lifecycle stats and
/// recent signals from the live engine (or mock repo offline) so users
/// see WHAT each evaluator has actually shipped, not just what the
/// evaluator class is supposed to do.
import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import 'agent_data.dart';

class AgentsPage extends StatelessWidget {
  const AgentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About the agents',
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
              child: Text(
                '${kAgents.length} AI specialists',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: LuminSpacing.md),
              child: Text(
                'Each agent watches markets for a specific setup family. '
                'Tap an agent to see its live stats and recent signals.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: kAgents.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: LuminSpacing.md),
                itemBuilder: (_, i) => _AgentCard(agent: kAgents[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: Text("Lumin's ${kAgents.length} AI agents"),
        content: const Text(
          "Each agent corresponds to one of the engine's evaluator paths. "
          'They scan 75 USDT-M futures pairs continuously, looking for their '
          "specific setup type. When an agent's confidence clears the paid "
          'threshold (65+), the signal is dispatched.\n\n'
          'Per-agent toggles and custom thresholds coming with a future '
          'subscription tier. Live stats are populated as soon as that '
          'evaluator emits a signal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});
  final Agent agent;

  @override
  Widget build(BuildContext context) {
    return LuminCard(
      onTap: () => _openDetail(context, agent),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: LuminColors.accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(LuminRadii.md),
              border: Border.all(color: LuminColors.cardBorder),
            ),
            child: Icon(agent.icon, color: LuminColors.accent, size: 28),
          ),
          const SizedBox(width: LuminSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(agent.name,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: LuminSpacing.xs),
                Text(agent.tagline,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: LuminColors.textMuted),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, Agent agent) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LuminColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
      ),
      builder: (_) => _AgentDetailSheet(agent: agent),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail bottom sheet — async-fetches stats + recent signals.
// ---------------------------------------------------------------------------

class _AgentDetailBundle {
  const _AgentDetailBundle({required this.stat, required this.signals});
  final AgentStat stat;
  final List<MockSignal> signals;
}

class _AgentDetailSheet extends StatefulWidget {
  const _AgentDetailSheet({required this.agent});
  final Agent agent;

  @override
  State<_AgentDetailSheet> createState() => _AgentDetailSheetState();
}

class _AgentDetailSheetState extends State<_AgentDetailSheet> {
  late Future<_AgentDetailBundle> _future;

  @override
  void initState() {
    super.initState();
    // We must read AppConfigScope after the first frame; doing so here is
    // safe because showModalBottomSheet is called with a context that
    // sits below AppConfigScope.
    _future = _load();
  }

  Future<_AgentDetailBundle> _load() async {
    final repo = AppConfigScope.of(context).repo;
    // Route through the SWR-cached watches (first emission) rather than the
    // raw fetch* methods. When warm — the agents list is prewarmed at
    // sign-in, and re-opening the same agent hits the per-setupClass signals
    // cache — this resolves synchronously, so the sheet renders instantly
    // instead of showing a spinner on every open.
    final results = await Future.wait([
      repo.watchAgents().first,
      repo
          .watchSignals(
            status: 'all',
            limit: 10,
            setupClass: widget.agent.id,
          )
          .first,
    ]);
    final allAgents = results[0] as List<AgentStat>;
    final signals = (results[1] as List).cast<MockSignal>();
    final stat = allAgents.firstWhere(
      (a) => a.setupClass == widget.agent.id,
      orElse: () => AgentStat(
        evaluator: widget.agent.id,
        setupClass: widget.agent.id,
        displayName: widget.agent.name,
        enabled: true,
        attempts: 0,
        generated: 0,
        noSignal: 0,
      ),
    );
    return _AgentDetailBundle(stat: stat, signals: signals);
  }

  Future<void> _refresh() async {
    // Pull-to-refresh must bypass the cache — invalidate both keys so the
    // next _load() goes straight to the network for genuinely fresh data.
    final repo = AppConfigScope.of(context).repo;
    repo.invalidateAgentsCache();
    repo.invalidateSignalsCache(
      status: 'all',
      limit: 10,
      setupClass: widget.agent.id,
    );
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            LuminSpacing.xl,
            LuminSpacing.lg,
            LuminSpacing.xl,
            LuminSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: LuminColors.textMuted,
                    borderRadius: BorderRadius.circular(LuminRadii.pill),
                  ),
                ),
              ),
              const SizedBox(height: LuminSpacing.lg),
              _Hero(agent: widget.agent),
              const SizedBox(height: LuminSpacing.lg),
              Text(
                widget.agent.specialty,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: LuminSpacing.lg),
              FutureBuilder<_AgentDetailBundle>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: LuminSpacing.xl),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LuminColors.accent,
                          ),
                        ),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return _ErrorBlock(
                      error: snap.error.toString(),
                      onRetry: _refresh,
                    );
                  }
                  final bundle = snap.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatsCard(stat: bundle.stat),
                      const SizedBox(height: LuminSpacing.lg),
                      _RecentSignalsBlock(signals: bundle.signals),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.agent});
  final Agent agent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(agent.icon, size: 32, color: LuminColors.accent),
        const SizedBox(width: LuminSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(agent.name,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text(
                agent.tagline,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: LuminColors.accent),
              ),
              const SizedBox(height: LuminSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LuminSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: LuminColors.bgElevated,
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                ),
                child: Text(
                  agent.id,
                  style: const TextStyle(
                    color: LuminColors.textMuted,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stat});
  final AgentStat stat;

  @override
  Widget build(BuildContext context) {
    final lastFired = stat.lastSignalAgeMinutes;
    final lastFiredLabel = lastFired == null
        ? 'never'
        : lastFired < 1
            ? 'just now'
            : '${formatAge(lastFired)} ago';
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STATS — LAST 24h',
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
              Expanded(
                child: _Stat(
                  label: 'TP hits',
                  value: '${stat.tpHits}',
                  color: LuminColors.success,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'SL hits',
                  value: '${stat.slHits}',
                  color: LuminColors.loss,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Invalidated',
                  value: '${stat.invalidated}',
                  color: LuminColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Closed',
                  value: '${stat.closedToday}',
                  color: LuminColors.textPrimary,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Last fired',
                  value: lastFiredLabel,
                  color: LuminColors.accent,
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Generated',
                  value: '${stat.generated}',
                  color: LuminColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: LuminColors.textMuted,
            fontSize: 9,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _RecentSignalsBlock extends StatelessWidget {
  const _RecentSignalsBlock({required this.signals});
  final List<MockSignal> signals;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECENT SIGNALS',
          style: TextStyle(
            color: LuminColors.textMuted,
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LuminSpacing.md),
        if (signals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: LuminSpacing.lg),
            child: Center(
              child: Text(
                'No signals from this agent yet.\n'
                'Will appear here as soon as it fires.',
                textAlign: TextAlign.center,
                style: TextStyle(color: LuminColors.textMuted, fontSize: 12),
              ),
            ),
          )
        else
          for (int i = 0; i < signals.length; i++) ...[
            _AgentSignalRow(sig: signals[i]),
            if (i < signals.length - 1)
              const Divider(
                color: LuminColors.cardBorder,
                height: LuminSpacing.lg,
              ),
          ],
      ],
    );
  }
}

class _AgentSignalRow extends StatelessWidget {
  const _AgentSignalRow({required this.sig});
  final MockSignal sig;

  Color _statusColor() {
    switch (sig.status) {
      case 'TP1_HIT':
      case 'TP2_HIT':
      case 'TP3_HIT':
      case 'FULL_TP_HIT':
        return LuminColors.success;
      case 'SL_HIT':
        return LuminColors.loss;
      case 'INVALIDATED':
      case 'EXPIRED':
      case 'CANCELLED':
        return LuminColors.textMuted;
      default:
        return LuminColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pnlPositive = sig.pnlPct >= 0;
    final isLong = sig.direction == 'LONG';
    return Row(
      children: [
        Container(
          width: 6,
          height: 36,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: LuminSpacing.xs),
                  Text(
                    sig.direction,
                    style: TextStyle(
                      color:
                          isLong ? LuminColors.success : LuminColors.loss,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${sig.status} • ${formatAge(sig.minutesAgo)} ago',
                style: TextStyle(
                  color: _statusColor(),
                  fontSize: 10,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        Text(
          formatPct(sig.pnlPct),
          style: TextStyle(
            color: pnlPositive ? LuminColors.success : LuminColors.loss,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.error, required this.onRetry});
  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LuminSpacing.lg),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, color: LuminColors.loss, size: 32),
          const SizedBox(height: LuminSpacing.sm),
          const Text(
            'Could not load agent stats',
            style: TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminSpacing.xs),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.accent,
              foregroundColor: LuminColors.bgDeep,
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

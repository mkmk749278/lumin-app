import 'package:flutter/material.dart';
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
          IconButton(icon: const Icon(Icons.info_outline), tooltip: 'About the agents', onPressed: () => _showAboutDialog(context)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
              child: Text('${kAgents.length} AI specialists', style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: LuminSpacing.md),
              child: Text('Each agent watches markets for a specific setup family.  Live stats land when the backend wires up.', style: Theme.of(context).textTheme.bodyMedium),
            ),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: kAgents.length,
                separatorBuilder: (_, __) => const SizedBox(height: LuminSpacing.md),
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
        title: const Text('Lumin\'s 14 AI agents'),
        content: const Text(
          'Each agent corresponds to one of the engine\'s evaluator paths.  They scan 75 USDT-M futures pairs continuously, looking for their specific setup type.  When an agent\'s confidence clears the paid threshold (65+), the signal is dispatched.\n\nPer-agent toggles, custom thresholds, and live stats coming with the next backend ship.',
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
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
      onTap: () => _showAgentDetail(context, agent),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
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
                Text(agent.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: LuminSpacing.xs),
                Text(agent.tagline, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: LuminColors.textMuted),
        ],
      ),
    );
  }

  void _showAgentDetail(BuildContext context, Agent agent) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LuminColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(LuminSpacing.xl, LuminSpacing.lg, LuminSpacing.xl, LuminSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: LuminColors.textMuted, borderRadius: BorderRadius.circular(LuminRadii.pill)))),
            const SizedBox(height: LuminSpacing.lg),
            Row(children: [
              Icon(agent.icon, size: 32, color: LuminColors.accent),
              const SizedBox(width: LuminSpacing.md),
              Expanded(child: Text(agent.name, style: Theme.of(context).textTheme.headlineMedium)),
            ]),
            const SizedBox(height: LuminSpacing.xs),
            Text(agent.tagline, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: LuminColors.accent)),
            const SizedBox(height: LuminSpacing.lg),
            Text(agent.specialty, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: LuminSpacing.lg),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.md, vertical: LuminSpacing.sm),
              decoration: BoxDecoration(color: LuminColors.bgElevated, borderRadius: BorderRadius.circular(LuminRadii.sm)),
              child: Row(children: [
                const Icon(Icons.tag, size: 14, color: LuminColors.textMuted),
                const SizedBox(width: LuminSpacing.xs),
                Text(agent.id, style: const TextStyle(color: LuminColors.textMuted, fontFamily: 'monospace', fontSize: 11, letterSpacing: 1.0)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

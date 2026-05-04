/// Signals — live + closed feed.
///
/// Filter chips (All / Open / Closed) toggle the visible subset.  Each
/// signal renders as a card with symbol, direction, agent, entry/SL/TP,
/// confidence tier, and live PnL.  Tap → detail bottom sheet (placeholder
/// for now; real chart preview lands when backend ships).
import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';

enum _SignalFilter { all, open, closed }

class SignalsPage extends StatefulWidget {
  const SignalsPage({super.key});

  @override
  State<SignalsPage> createState() => _SignalsPageState();
}

class _SignalsPageState extends State<SignalsPage> {
  _SignalFilter _filter = _SignalFilter.all;

  bool _isOpen(MockSignal s) => s.status == 'ACTIVE';

  List<MockSignal> get _filtered {
    switch (_filter) {
      case _SignalFilter.open:
        return mockSignals.where(_isOpen).toList();
      case _SignalFilter.closed:
        return mockSignals.where((s) => !_isOpen(s)).toList();
      case _SignalFilter.all:
        return mockSignals;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Signals')),
      body: Column(
        children: [
          const PreviewBadge(),
          _FilterRow(
            current: _filter,
            onChanged: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: LuminSpacing.sm),
          if (filtered.isEmpty)
            _EmptyState(filter: _filter)
          else
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: LuminSpacing.lg,
                ),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: LuminSpacing.md),
                itemBuilder: (_, i) => _SignalCard(sig: filtered[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.current, required this.onChanged});

  final _SignalFilter current;
  final ValueChanged<_SignalFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Row(
        children: [
          for (final f in _SignalFilter.values) ...[
            _FilterChip(
              label: f.name[0].toUpperCase() + f.name.substring(1),
              selected: current == f,
              onTap: () => onChanged(f),
            ),
            if (f != _SignalFilter.values.last)
              const SizedBox(width: LuminSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LuminRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.md,
            vertical: LuminSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? LuminColors.accent.withOpacity(0.15)
                : LuminColors.bgCard,
            borderRadius: BorderRadius.circular(LuminRadii.pill),
            border: Border.all(
              color: selected
                  ? LuminColors.accent.withOpacity(0.40)
                  : LuminColors.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? LuminColors.accent : LuminColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final _SignalFilter filter;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(LuminSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inbox_outlined,
                size: 48,
                color: LuminColors.textMuted,
              ),
              const SizedBox(height: LuminSpacing.md),
              Text(
                filter == _SignalFilter.open
                    ? 'No open signals right now'
                    : 'No closed signals yet',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.sig});
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
    if (sig.minutesAgo < 60) return '${sig.minutesAgo}m';
    if (sig.minutesAgo < 1440) return '${(sig.minutesAgo / 60).round()}h';
    return '${(sig.minutesAgo / 1440).round()}d';
  }

  @override
  Widget build(BuildContext context) {
    final isLong = sig.direction == 'LONG';
    final pnlPositive = sig.pnlPct >= 0;
    return LuminCard(
      onTap: () => _showDetail(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row.
          Row(
            children: [
              Text(
                sig.symbol,
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: LuminSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LuminSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: (isLong ? LuminColors.success : LuminColors.loss)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                ),
                child: Text(
                  sig.direction,
                  style: TextStyle(
                    color: isLong ? LuminColors.success : LuminColors.loss,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LuminSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: LuminColors.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                ),
                child: Text(
                  '${sig.confidence.toStringAsFixed(1)} ${sig.tier}',
                  style: const TextStyle(
                    color: LuminColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.xs),
          // Agent + setup
          Text(
            '${sig.agentName} • ${sig.setupName}',
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          // Price levels row.
          Row(
            children: [
              Expanded(
                child: _PriceCol(
                  label: 'Entry',
                  value: sig.entry.toStringAsFixed(2),
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'SL',
                  value: sig.sl.toStringAsFixed(2),
                  color: LuminColors.loss,
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'TP1',
                  value: sig.tp1.toStringAsFixed(2),
                  color: LuminColors.success,
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'TP3',
                  value: sig.tp3.toStringAsFixed(2),
                  color: LuminColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          // Status footer.
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: LuminSpacing.xs),
              Text(
                sig.status,
                style: TextStyle(
                  color: _statusColor(),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: LuminSpacing.sm),
              Text(
                '• ${_agoLabel()} ago',
                style: const TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              Text(
                '${pnlPositive ? '+' : ''}${sig.pnlPct.toStringAsFixed(2)}%',
                style: TextStyle(
                  color:
                      pnlPositive ? LuminColors.success : LuminColors.loss,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LuminColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(LuminRadii.lg),
        ),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(LuminSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Text(
              '${sig.symbol} ${sig.direction}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: LuminSpacing.xs),
            Text(
              'Signal ${sig.id} • ${sig.agentName}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: LuminSpacing.lg),
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: LuminColors.bgElevated,
                borderRadius: BorderRadius.circular(LuminRadii.md),
                border: Border.all(color: LuminColors.cardBorder),
              ),
              child: const Center(
                child: Text(
                  'Chart preview — coming with backend',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.lg),
            _DetailRow('TP2', sig.tp2.toStringAsFixed(2)),
            _DetailRow('Confidence',
                '${sig.confidence.toStringAsFixed(1)} (${sig.tier})'),
            _DetailRow('Status', sig.status),
          ],
        ),
      ),
    );
  }
}

class _PriceCol extends StatelessWidget {
  const _PriceCol({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

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
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color ?? LuminColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LuminSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

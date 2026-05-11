/// Signals — live + closed feed.
///
/// Filter chips trigger a re-fetch via the repository.  When the
/// "Closed" filter is active, a second row of sub-filter chips appears
/// (All / TP / SL / Invalidated / Expired) and is applied client-side
/// so we don't multiply API requests for what is essentially a status
/// projection of the same closed-pool.
import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import 'take_signal_sheet.dart';

enum _SignalFilter { all, open, closed }

extension _FilterStr on _SignalFilter {
  String get apiValue {
    switch (this) {
      case _SignalFilter.open:
        return 'open';
      case _SignalFilter.closed:
        return 'closed';
      case _SignalFilter.all:
        return 'all';
    }
  }

  String get label =>
      '${name[0].toUpperCase()}${name.substring(1)}';
}

enum _ClosedSubFilter { all, tp, sl, invalidated, expired }

extension _SubFilterStr on _ClosedSubFilter {
  String get label {
    switch (this) {
      case _ClosedSubFilter.all:
        return 'All';
      case _ClosedSubFilter.tp:
        return 'TP';
      case _ClosedSubFilter.sl:
        return 'SL';
      case _ClosedSubFilter.invalidated:
        return 'Invalidated';
      case _ClosedSubFilter.expired:
        return 'Expired';
    }
  }
}

bool _matchesSubFilter(MockSignal s, _ClosedSubFilter f) {
  switch (f) {
    case _ClosedSubFilter.all:
      return true;
    case _ClosedSubFilter.tp:
      return s.status == 'TP1_HIT' ||
          s.status == 'TP2_HIT' ||
          s.status == 'TP3_HIT' ||
          s.status == 'FULL_TP_HIT';
    case _ClosedSubFilter.sl:
      return s.status == 'SL_HIT';
    case _ClosedSubFilter.invalidated:
      return s.status == 'INVALIDATED' || s.status == 'CANCELLED';
    case _ClosedSubFilter.expired:
      return s.status == 'EXPIRED';
  }
}

class SignalsPage extends StatefulWidget {
  const SignalsPage({super.key});

  @override
  State<SignalsPage> createState() => _SignalsPageState();
}

class _SignalsPageState extends State<SignalsPage> {
  _SignalFilter _filter = _SignalFilter.all;
  _ClosedSubFilter _subFilter = _ClosedSubFilter.all;
  late Future<List<MockSignal>> _future;
  LuminRepository? _lastRepo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppConfigScope.of(context).repo;
    if (repo != _lastRepo) {
      _lastRepo = repo;
      _refetch();
    }
  }

  void _refetch() {
    final repo = AppConfigScope.of(context).repo;
    setState(() {
      _future = repo.fetchSignals(status: _filter.apiValue, limit: 100);
    });
  }

  Future<void> _refresh() async {
    _refetch();
    await _future;
  }

  void _setFilter(_SignalFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      // Reset sub-filter when switching primary chip — hidden when not Closed.
      _subFilter = _ClosedSubFilter.all;
    });
    _refetch();
  }

  void _setSubFilter(_ClosedSubFilter f) {
    if (f == _subFilter) return;
    setState(() => _subFilter = f);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Signals')),
      body: Column(
        children: [
          if (!scope.repo.isLive) const PreviewBadge(),
          _FilterRow(current: _filter, onChanged: _setFilter),
          if (_filter == _SignalFilter.closed) ...[
            const SizedBox(height: LuminSpacing.sm),
            _SubFilterRow(current: _subFilter, onChanged: _setSubFilter),
          ],
          const SizedBox(height: LuminSpacing.sm),
          Expanded(
            child: RefreshIndicator(
              color: LuminColors.accent,
              onRefresh: _refresh,
              child: FutureBuilder<List<MockSignal>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const _SignalsLoading();
                  }
                  if (snap.hasError) {
                    return _SignalsError(
                      error: snap.error.toString(),
                      onRetry: _refresh,
                    );
                  }
                  var items = snap.data ?? const <MockSignal>[];
                  if (_filter == _SignalFilter.closed &&
                      _subFilter != _ClosedSubFilter.all) {
                    items = items
                        .where((s) => _matchesSubFilter(s, _subFilter))
                        .toList(growable: false);
                  }
                  if (items.isEmpty) {
                    return _SignalsEmpty(
                      filter: _filter,
                      subFilter: _subFilter,
                      isLive: scope.repo.isLive,
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuminSpacing.lg,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: LuminSpacing.md),
                    itemBuilder: (_, i) => _SignalCard(sig: items[i]),
                  );
                },
              ),
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
            _Chip(
              label: f.label,
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

class _SubFilterRow extends StatelessWidget {
  const _SubFilterRow({required this.current, required this.onChanged});

  final _ClosedSubFilter current;
  final ValueChanged<_ClosedSubFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
        itemCount: _ClosedSubFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: LuminSpacing.sm),
        itemBuilder: (_, i) {
          final f = _ClosedSubFilter.values[i];
          return _Chip(
            label: f.label,
            selected: current == f,
            onTap: () => onChanged(f),
            compact: true,
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

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
          padding: EdgeInsets.symmetric(
            horizontal: compact ? LuminSpacing.sm : LuminSpacing.md,
            vertical: compact ? LuminSpacing.xs : LuminSpacing.xs + 2,
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
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalsEmpty extends StatelessWidget {
  const _SignalsEmpty({
    required this.filter,
    required this.subFilter,
    required this.isLive,
  });
  final _SignalFilter filter;
  final _ClosedSubFilter subFilter;
  final bool isLive;

  String _heading() {
    if (filter == _SignalFilter.open) return 'No open signals right now';
    if (filter == _SignalFilter.closed) {
      switch (subFilter) {
        case _ClosedSubFilter.all:
          return 'No closed signals yet';
        case _ClosedSubFilter.tp:
          return 'No TP hits yet';
        case _ClosedSubFilter.sl:
          return 'No SL hits yet';
        case _ClosedSubFilter.invalidated:
          return 'No invalidated signals';
        case _ClosedSubFilter.expired:
          return 'No expired signals';
      }
    }
    return 'No signals yet';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        const SizedBox(height: LuminSpacing.xxl),
        const Icon(Icons.inbox_outlined,
            size: 48, color: LuminColors.textMuted),
        const SizedBox(height: LuminSpacing.md),
        Text(
          _heading(),
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: LuminSpacing.xs),
        Text(
          isLive
              ? 'Engine is scanning 75 pairs.\nNew paid signals appear here when they fire.'
              : 'Pull down to refresh.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: LuminColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _SignalsLoading extends StatelessWidget {
  const _SignalsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: const [
        SizedBox(height: LuminSpacing.xxl),
        Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: LuminColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignalsError extends StatelessWidget {
  const _SignalsError({required this.error, required this.onRetry});
  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(LuminSpacing.lg),
      children: [
        const SizedBox(height: LuminSpacing.xxl),
        const Icon(Icons.cloud_off, color: LuminColors.loss, size: 40),
        const SizedBox(height: LuminSpacing.md),
        const Text(
          'Could not load signals',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: LuminColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LuminSpacing.sm),
        Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LuminColors.textSecondary,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: LuminSpacing.md),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.accent,
              foregroundColor: LuminColors.bgDeep,
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ),
      ],
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
    final isLong = sig.direction == 'LONG';
    final pnlPositive = sig.pnlPct >= 0;
    return LuminCard(
      onTap: () => _showDetail(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Text(
            '${sig.agentName} • ${sig.setupName}',
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PriceCol(
                  label: 'Entry',
                  value: formatPrice(sig.entry),
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'SL',
                  value: formatPrice(sig.sl),
                  color: LuminColors.loss,
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'TP1',
                  value: formatPrice(sig.tp1),
                  color: LuminColors.success,
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'TP2',
                  value: formatPrice(sig.tp2),
                  color: LuminColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
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
                '• ${formatAge(sig.minutesAgo)} ago',
                style: const TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              if (sig.currentPrice > 0) ...[
                Text(
                  formatPrice(sig.currentPrice),
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: LuminSpacing.sm),
              ],
              Text(
                formatPct(sig.pnlPct),
                style: TextStyle(
                  color: pnlPositive ? LuminColors.success : LuminColors.loss,
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
                  'Chart preview — coming with v0.1.0',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.lg),
            // Pre-TP centerpiece — shown when the engine stamped a trigger
            // at dispatch (B11 fee-aware doctrine).  Doctrine 2026-05-07:
            // Pre-TP is the primary scalp outcome; subscribers see it
            // before the TP ladder.
            if (sig.preTpTriggerPrice > 0) ...[
              _PreTpCard(sig: sig),
              const SizedBox(height: LuminSpacing.md),
            ],
            _DetailRow('Entry', formatPrice(sig.entry)),
            if (sig.currentPrice > 0)
              _DetailRow('Current', formatPrice(sig.currentPrice)),
            _DetailRow('SL', formatPrice(sig.sl)),
            _DetailRow('TP1', formatPrice(sig.tp1)),
            _DetailRow('TP2', formatPrice(sig.tp2)),
            _DetailRow('PnL', formatPct(sig.pnlPct)),
            _DetailRow('Confidence',
                '${sig.confidence.toStringAsFixed(1)} (${sig.tier})'),
            _DetailRow('Status', sig.status),
            // Take Signal — Phase 3b-1 manual order placement.  Visible
            // only when the signal is still actionable (ACTIVE status)
            // — TP/SL/expired signals are read-only.  Inside the sheet
            // the user confirms again before any order fires, and we
            // short-circuit on a prior signal_id (idempotency).
            if (sig.status == 'ACTIVE') ...[
              const SizedBox(height: LuminSpacing.lg),
              _TakeSignalAction(sig: sig),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Take signal" CTA on the detail sheet.  Opens the review sheet
/// (sized to wallet equity + per-user settings) on tap; the user
/// confirms there before any Binance call fires.
class _TakeSignalAction extends StatelessWidget {
  const _TakeSignalAction({required this.sig});
  final MockSignal sig;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: LuminColors.accent,
          foregroundColor: LuminColors.bgDeep,
          padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
        ),
        onPressed: () async {
          // Close the detail sheet first so the take sheet stacks
          // cleanly without an awkward double-modal.
          Navigator.of(context).pop();
          await showTakeSignalSheet(context, signal: sig);
        },
        icon: const Icon(Icons.bolt, size: 18),
        label: const Text(
          'Take signal',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Pre-TP centerpiece card — banked-state highlight or stamped-target.
class _PreTpCard extends StatelessWidget {
  const _PreTpCard({required this.sig});
  final MockSignal sig;

  @override
  Widget build(BuildContext context) {
    final banked = sig.preTpHit;
    final accent = banked ? LuminColors.success : LuminColors.accent;
    final title = banked ? '⚡ Pre-TP Banked' : '⚡ Pre-TP Target';
    final priceLine = formatPrice(sig.preTpTriggerPrice);
    final pctLine =
        '+${sig.preTpThresholdPct.toStringAsFixed(2)}% raw → SL ratchets to breakeven';
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(LuminRadii.md),
        border: Border.all(color: accent.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            priceLine,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pctLine,
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
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

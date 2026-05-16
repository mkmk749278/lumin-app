/// Paper Trades — per-trade visibility list for the Trade tab's Paper view.
///
/// Lists paginated paper trade records from
/// ``GET /api/trades?mode=paper`` ordered most-recent-first.  Each row
/// is the Binance-style trade card the owner asked for: side/symbol/
/// ROI% pill, entry/exit/qty/notional grid, fees + net PnL + timestamps.
/// Tap a row → :class:`PaperTradeDetailPage`.
///
/// The "Reset balance" action lives in the app-bar overflow menu;
/// firing it shows a confirm dialog, then calls
/// ``repo.resetPaperBalance()`` and refreshes.
import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import 'paper_trade_detail_page.dart';

class PaperTradesPage extends StatefulWidget {
  const PaperTradesPage({super.key});

  @override
  State<PaperTradesPage> createState() => _PaperTradesPageState();
}

class _PaperTradesPageState extends State<PaperTradesPage> {
  static const _pageSize = 50;

  final ScrollController _scroll = ScrollController();
  final List<TradeRecord> _items = [];
  int _total = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _resetting = false;
  String? _error;
  LuminRepository? _lastRepo;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppConfigScope.of(context).repo;
    if (repo != _lastRepo) {
      _lastRepo = repo;
      _refresh();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // Trigger the next page once we're within one screen of the end.
    if (pos.pixels >= pos.maxScrollExtent - pos.viewportDimension) {
      _loadMore();
    }
  }

  Future<void> _refresh() async {
    final repo = AppConfigScope.of(context).repo;
    setState(() {
      _initialLoading = true;
      _error = null;
      _items.clear();
      _total = 0;
    });
    try {
      final resp = await repo.fetchTrades(
        mode: 'paper',
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(resp.items);
        _total = resp.total;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _initialLoading) return;
    if (_items.length >= _total) return;
    final repo = AppConfigScope.of(context).repo;
    setState(() => _loadingMore = true);
    try {
      final resp = await repo.fetchTrades(
        mode: 'paper',
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(resp.items);
        _total = resp.total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Load more failed: $e'),
          duration: const Duration(seconds: 3),
          backgroundColor: LuminColors.loss,
        ),
      );
    }
  }

  /// Confirm + fire ``resetPaperBalance``.  Identical body to the
  /// owner's spec so subscribers see a consistent destructive-action
  /// warning across the app.
  Future<void> _confirmReset() async {
    if (_resetting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: const Row(
          children: [
            Icon(Icons.refresh, color: LuminColors.warn, size: 20),
            SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Text(
                'Reset paper balance?',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'This zeros your cumulative paper PnL and resets your paper '
          'equity to \$1000. The trade history will be archived but '
          "you'll start a fresh set. This cannot be undone.",
          style: TextStyle(
            color: LuminColors.textPrimary,
            fontSize: 13,
            height: 1.4,
          ),
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
              backgroundColor: LuminColors.warn,
              foregroundColor: LuminColors.bgDeep,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Reset',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = AppConfigScope.of(context).repo;
    setState(() => _resetting = true);
    try {
      final resp = await repo.resetPaperBalance();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Paper balance reset to \$${resp.startingEquityUsd.toStringAsFixed(2)}',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: LuminColors.success,
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reset failed: $e'),
          duration: const Duration(seconds: 4),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paper Trades'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _initialLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'reset') _confirmReset();
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt,
                        color: LuminColors.warn, size: 18),
                    SizedBox(width: LuminSpacing.sm),
                    Text('Reset balance'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: LuminColors.accent,
        onRefresh: _refresh,
        child: _buildBody(scope.repo.isLive),
      ),
    );
  }

  Widget _buildBody(bool isLive) {
    if (_initialLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          if (!isLive) const PreviewBadge(),
          const SizedBox(height: LuminSpacing.md),
          for (int i = 0; i < 3; i++) const _SkeletonCard(),
        ],
      );
    }
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _refresh);
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          if (!isLive) const PreviewBadge(),
          const SizedBox(height: LuminSpacing.xxl),
          const _EmptyState(),
        ],
      );
    }
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      itemCount: _items.length + (_loadingMore ? 1 : 0) + (isLive ? 0 : 1),
      itemBuilder: (context, i) {
        int idx = i;
        if (!isLive) {
          if (idx == 0) return const PreviewBadge();
          idx -= 1;
        }
        if (idx >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: LuminSpacing.lg),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: LuminColors.accent,
                ),
              ),
            ),
          );
        }
        final trade = _items[idx];
        return _TradeCard(
          trade: trade,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PaperTradeDetailPage(trade: trade),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Trade list card — Binance-style row with ROI pill + 4-col stats grid.
// ---------------------------------------------------------------------------

class _TradeCard extends StatelessWidget {
  const _TradeCard({required this.trade, required this.onTap});

  final TradeRecord trade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLong = trade.side.toLowerCase() == 'long';
    final sideColor = isLong ? LuminColors.success : LuminColors.loss;
    final roi = trade.roiPctOnMargin;
    final isOpen = trade.isOpen;
    final roiColor = isOpen
        ? LuminColors.textMuted
        : (roi != null && roi >= 0)
            ? LuminColors.success
            : LuminColors.loss;
    final roiLabel = isOpen
        ? 'OPEN'
        : (roi == null
            ? '—'
            : '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(2)}%');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg,
        LuminSpacing.sm,
        LuminSpacing.lg,
        LuminSpacing.sm,
      ),
      child: LuminCard(
        onTap: onTap,
        padding: const EdgeInsets.all(LuminSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row — side badge | symbol | ROI pill
            Row(
              children: [
                _SideBadge(side: trade.side, color: sideColor),
                const SizedBox(width: LuminSpacing.sm),
                Expanded(
                  child: Text(
                    trade.symbol,
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                _LeveragePill(leverage: trade.leverage),
                const SizedBox(width: LuminSpacing.xs),
                _RoiPill(label: roiLabel, color: roiColor),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            // Middle row — entry / exit / qty / notional
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: 'Entry',
                    value: formatPrice(trade.entry),
                  ),
                ),
                Expanded(
                  child: _StatCell(
                    label: 'Exit',
                    value: trade.closePrice != null
                        ? formatPrice(trade.closePrice!)
                        : '—',
                    valueColor: trade.closePrice == null
                        ? LuminColors.textMuted
                        : null,
                  ),
                ),
                Expanded(
                  child: _StatCell(
                    label: 'Qty',
                    value: _formatQty(trade.qty),
                  ),
                ),
                Expanded(
                  child: _StatCell(
                    label: 'Notional',
                    value: '\$${trade.notionalUsd.toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Divider(color: LuminColors.cardBorder, height: 1),
            const SizedBox(height: LuminSpacing.sm),
            // Bottom row — fees | net PnL | timestamps
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: 'Fees',
                    value: trade.feesUsd != null
                        ? '\$${trade.feesUsd!.toStringAsFixed(2)}'
                        : '—',
                    compact: true,
                    valueColor: LuminColors.textSecondary,
                  ),
                ),
                Expanded(
                  child: _StatCell(
                    label: 'Net PnL',
                    value: trade.netPnlUsd != null
                        ? formatPnl(trade.netPnlUsd!)
                        : '—',
                    compact: true,
                    valueColor: trade.netPnlUsd == null
                        ? LuminColors.textMuted
                        : (trade.netPnlUsd! >= 0
                            ? LuminColors.success
                            : LuminColors.loss),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _CloseReasonLabel.of(trade.closeReason, isOpen),
                        style: TextStyle(
                          color: _CloseReasonLabel.colorOf(
                              trade.closeReason, isOpen),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _windowLabel(trade),
                        style: const TextStyle(
                          color: LuminColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// "Opened 18m ago" for open trades, "12m → 1h ago" for closed.
  /// Compact + glanceable; the detail page renders full ISO.
  static String _windowLabel(TradeRecord t) {
    final now = DateTime.now().toUtc();
    final openedAgo = now.difference(t.createdAt).inMinutes;
    if (t.closedAt == null) {
      return 'Opened ${formatAge(openedAgo)} ago';
    }
    final closedAgo = now.difference(t.closedAt!).inMinutes;
    final lifespan = t.closedAt!.difference(t.createdAt).inMinutes;
    return '${formatAge(lifespan)} • closed ${formatAge(closedAgo)} ago';
  }

  /// Qty with adaptive precision — micro-cap altcoins keep their
  /// fractional digits, BTC-sized qty doesn't render as 0.0013.
  static String _formatQty(double q) {
    if (q.abs() >= 100) return q.toStringAsFixed(2);
    if (q.abs() >= 1) return q.toStringAsFixed(3);
    if (q.abs() >= 0.01) return q.toStringAsFixed(4);
    return q.toStringAsFixed(5);
  }
}

class _SideBadge extends StatelessWidget {
  const _SideBadge({required this.side, required this.color});
  final String side;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
      ),
      child: Text(
        side.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _LeveragePill extends StatelessWidget {
  const _LeveragePill({required this.leverage});
  final double leverage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(LuminRadii.sm),
      ),
      child: Text(
        '${leverage.toStringAsFixed(0)}x',
        style: const TextStyle(
          color: LuminColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RoiPill extends StatelessWidget {
  const _RoiPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.valueColor,
    this.compact = false,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: LuminColors.textMuted,
            fontSize: 9,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? LuminColors.textPrimary,
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

/// Compact human-readable label for the engine's ``close_reason``
/// vocabulary.  Same colour family the activity feed uses so a
/// glance across surfaces stays coherent.
class _CloseReasonLabel {
  _CloseReasonLabel._();

  static String of(String? reason, bool isOpen) {
    if (isOpen) return 'OPEN';
    switch (reason) {
      case 'tp1':
        return 'TP1';
      case 'tp2':
        return 'TP2';
      case 'tp3':
        return 'TP3';
      case 'sl_hit':
        return 'SL';
      case 'invalidated':
        return 'INVAL';
      case 'expired':
        return 'EXPIRED';
      case 'cancelled':
        return 'CANCELLED';
      case 'pre_tp_grab':
        return 'PRE-TP';
      default:
        return reason?.toUpperCase() ?? '—';
    }
  }

  static Color colorOf(String? reason, bool isOpen) {
    if (isOpen) return LuminColors.accent;
    switch (reason) {
      case 'tp1':
      case 'tp2':
      case 'tp3':
        return LuminColors.success;
      case 'sl_hit':
        return LuminColors.loss;
      case 'pre_tp_grab':
        return LuminColors.warn;
      case 'invalidated':
      case 'expired':
      case 'cancelled':
      default:
        return LuminColors.textMuted;
    }
  }
}

// ---------------------------------------------------------------------------
// Empty / loading / error states
// ---------------------------------------------------------------------------

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.lg,
        vertical: LuminSpacing.sm,
      ),
      child: LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _bar(width: 44, height: 14),
                const SizedBox(width: LuminSpacing.sm),
                _bar(width: 80, height: 14),
                const Spacer(),
                _bar(width: 60, height: 18),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            Row(
              children: [
                Expanded(child: _bar(height: 30)),
                const SizedBox(width: LuminSpacing.xs),
                Expanded(child: _bar(height: 30)),
                const SizedBox(width: LuminSpacing.xs),
                Expanded(child: _bar(height: 30)),
                const SizedBox(width: LuminSpacing.xs),
                Expanded(child: _bar(height: 30)),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            _bar(width: 200, height: 10),
          ],
        ),
      ),
    );
  }

  Widget _bar({double? width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(LuminRadii.sm),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined,
              color: LuminColors.textMuted, size: 48),
          const SizedBox(height: LuminSpacing.md),
          const Text(
            'No paper trades yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          const Text(
            "Once the engine fires its first signal, you'll see it here.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
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
          'Could not load paper trades',
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

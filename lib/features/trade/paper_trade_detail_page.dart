/// Paper Trade Detail — Binance-style trade detail layout for a single
/// :class:`TradeRecord`.
///
/// Mirrors the Binance Futures app trade-detail screen: status header
/// (icon + reason + symbol + side), Order Details section, Trade
/// Details section, and a Partial Fills section that surfaces when the
/// engine booked TP1 / TP2 / TP3 closes.  No interactivity — pure
/// drill-down read.
import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';

class PaperTradeDetailPage extends StatelessWidget {
  const PaperTradeDetailPage({super.key, required this.trade});

  final TradeRecord trade;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trade Detail')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
        children: [
          _HeaderCard(trade: trade),
          const SizedBox(height: LuminSpacing.md),
          _OrderDetailsCard(trade: trade),
          const SizedBox(height: LuminSpacing.md),
          _TradeDetailsCard(trade: trade),
          if (trade.partialFills.isNotEmpty) ...[
            const SizedBox(height: LuminSpacing.md),
            _PartialFillsCard(fills: trade.partialFills, side: trade.side),
          ],
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — status icon + symbol + side + headline ROI.
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.trade});
  final TradeRecord trade;

  @override
  Widget build(BuildContext context) {
    final isLong = trade.side.toLowerCase() == 'long';
    final sideColor = isLong ? LuminColors.success : LuminColors.loss;
    final isOpen = trade.isOpen;
    final reason = trade.closeReason;
    final icon = _statusIcon(reason, isOpen);
    final iconColor = _statusColor(reason, isOpen);
    final headline = _statusHeadline(reason, isOpen);
    final roi = trade.roiPctOnMargin;
    final roiColor = isOpen
        ? LuminColors.textMuted
        : (roi != null && roi >= 0)
            ? LuminColors.success
            : LuminColors.loss;
    final roiLabel = isOpen
        ? 'Open position'
        : (roi == null
            ? '—'
            : '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(2)}% ROI');
    final pnl = trade.netPnlUsd;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: LuminSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: TextStyle(
                          color: iconColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            trade.symbol,
                            style: const TextStyle(
                              color: LuminColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: LuminSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: LuminSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sideColor.withOpacity(0.15),
                              borderRadius:
                                  BorderRadius.circular(LuminRadii.sm),
                            ),
                            child: Text(
                              trade.side.toUpperCase(),
                              style: TextStyle(
                                color: sideColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: LuminSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: LuminSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: LuminColors.bgElevated,
                              borderRadius:
                                  BorderRadius.circular(LuminRadii.sm),
                            ),
                            child: Text(
                              '${trade.leverage.toStringAsFixed(0)}x',
                              style: const TextStyle(
                                color: LuminColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            const Divider(color: LuminColors.cardBorder, height: 1),
            const SizedBox(height: LuminSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NET PnL',
                      style: TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pnl == null ? '—' : formatPnl(pnl),
                      style: TextStyle(
                        color: pnl == null
                            ? LuminColors.textMuted
                            : (pnl >= 0
                                ? LuminColors.success
                                : LuminColors.loss),
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuminSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: roiColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(LuminRadii.sm),
                    border: Border.all(color: roiColor.withOpacity(0.45)),
                  ),
                  child: Text(
                    roiLabel,
                    style: TextStyle(
                      color: roiColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _statusIcon(String? reason, bool isOpen) {
    if (isOpen) return Icons.pause_circle_outline;
    switch (reason) {
      case 'tp1':
      case 'tp2':
      case 'tp3':
        return Icons.check_circle_outline;
      case 'sl_hit':
        return Icons.cancel_outlined;
      case 'pre_tp_grab':
        return Icons.bolt_outlined;
      case 'invalidated':
        return Icons.do_disturb_alt_outlined;
      case 'expired':
        return Icons.timer_off_outlined;
      case 'cancelled':
        return Icons.block_outlined;
      default:
        return Icons.help_outline;
    }
  }

  static Color _statusColor(String? reason, bool isOpen) {
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

  static String _statusHeadline(String? reason, bool isOpen) {
    if (isOpen) return 'OPEN';
    switch (reason) {
      case 'tp1':
        return 'Closed at TP1';
      case 'tp2':
        return 'Closed at TP2';
      case 'tp3':
        return 'Closed at TP3';
      case 'sl_hit':
        return 'Stopped out';
      case 'pre_tp_grab':
        return 'Pre-TP grab';
      case 'invalidated':
        return 'Invalidated';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return reason?.toUpperCase() ?? 'CLOSED';
    }
  }
}

// ---------------------------------------------------------------------------
// Order details — signalId, type, filled, avg price, etc.
// ---------------------------------------------------------------------------

class _OrderDetailsCard extends StatelessWidget {
  const _OrderDetailsCard({required this.trade});
  final TradeRecord trade;

  @override
  Widget build(BuildContext context) {
    final isLong = trade.side.toLowerCase() == 'long';
    return _SectionCard(
      title: 'ORDER DETAILS',
      icon: Icons.receipt_long_outlined,
      rows: [
        _Row(
          label: 'Order No.',
          value: trade.signalId,
          monospace: true,
        ),
        _Row(
          label: 'Type',
          value: 'Market / ${isLong ? "Buy" : "Sell"}',
        ),
        _Row(
          label: 'Filled / Amount',
          value:
              '${_formatQty(trade.qty)} / ${_formatQty(trade.qty)} ${_baseAsset(trade.symbol)}',
        ),
        _Row(
          label: 'Avg. Price',
          value: formatPrice(trade.entry),
        ),
        _Row(
          label: 'Leverage',
          value: '${trade.leverage.toStringAsFixed(0)}x cross',
        ),
        _Row(
          label: 'Position Size',
          value: '${trade.positionSizePct.toStringAsFixed(2)}% of equity',
        ),
        _Row(
          label: 'Notional',
          value: '\$${trade.notionalUsd.toStringAsFixed(2)}',
        ),
        _Row(
          label: 'Margin',
          value: '\$${trade.marginUsd.toStringAsFixed(2)}',
        ),
        const _Row(label: 'Reduce Only', value: 'No'),
        _Row(
          label: 'Fee',
          value: trade.feesUsd != null
              ? '\$${trade.feesUsd!.toStringAsFixed(4)}'
              : '—',
        ),
        _Row(
          label: 'Realized PnL',
          value: trade.netPnlUsd != null ? formatPnl(trade.netPnlUsd!) : '—',
          valueColor: trade.netPnlUsd == null
              ? null
              : (trade.netPnlUsd! >= 0
                  ? LuminColors.success
                  : LuminColors.loss),
        ),
        _Row(
          label: 'ROI %',
          value: trade.roiPctOnMargin != null
              ? '${trade.roiPctOnMargin! >= 0 ? '+' : ''}${trade.roiPctOnMargin!.toStringAsFixed(2)}%'
              : '—',
          valueColor: trade.roiPctOnMargin == null
              ? null
              : (trade.roiPctOnMargin! >= 0
                  ? LuminColors.success
                  : LuminColors.loss),
        ),
        _Row(
          label: 'Time Created',
          value: _formatTs(trade.createdAt),
        ),
        _Row(
          label: 'Time Updated',
          value: _formatTs(trade.closedAt ?? trade.createdAt),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Trade details — close-side info.
// ---------------------------------------------------------------------------

class _TradeDetailsCard extends StatelessWidget {
  const _TradeDetailsCard({required this.trade});
  final TradeRecord trade;

  @override
  Widget build(BuildContext context) {
    final closedAt = trade.closedAt ?? trade.createdAt;
    final isMaker = _isMakerClose(trade.closeReason);
    return _SectionCard(
      title: 'TRADE DETAILS',
      icon: Icons.fact_check_outlined,
      rows: [
        _Row(
          label: 'Date',
          value: _formatTs(closedAt),
        ),
        _Row(
          label: 'Quantity',
          value:
              '\$${trade.notionalUsd.toStringAsFixed(2)} (${_formatQty(trade.qty)} ${_baseAsset(trade.symbol)})',
        ),
        _Row(
          label: 'Price',
          value: trade.closePrice != null
              ? formatPrice(trade.closePrice!)
              : '—',
        ),
        _Row(
          label: 'Realized PnL',
          value: trade.netPnlUsd != null ? formatPnl(trade.netPnlUsd!) : '—',
          valueColor: trade.netPnlUsd == null
              ? null
              : (trade.netPnlUsd! >= 0
                  ? LuminColors.success
                  : LuminColors.loss),
        ),
        _Row(
          label: 'Fee',
          value: trade.feesUsd != null
              ? '\$${trade.feesUsd!.toStringAsFixed(4)}'
              : '—',
        ),
        _Row(
          label: 'Role',
          // TP fills land at limit prices (Maker rebate); SL / invalidation /
          // expiry are market closes (Taker fee).  Surfaced honestly so the
          // owner can sanity-check the fee math.
          value: isMaker ? 'Maker' : 'Taker',
        ),
        if (trade.closeReason != null)
          _Row(
            label: 'Close Reason',
            value: trade.closeReason!.toUpperCase().replaceAll('_', ' '),
          ),
      ],
    );
  }

  static bool _isMakerClose(String? reason) {
    return reason == 'tp1' || reason == 'tp2' || reason == 'tp3';
  }
}

// ---------------------------------------------------------------------------
// Partial fills — TP ladder rungs.
// ---------------------------------------------------------------------------

class _PartialFillsCard extends StatelessWidget {
  const _PartialFillsCard({required this.fills, required this.side});
  final List<PartialFill> fills;
  final String side;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.layers_outlined,
                    color: LuminColors.accent, size: 16),
                SizedBox(width: LuminSpacing.xs),
                Text(
                  'PARTIAL FILLS',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Text(
              'TP ladder closes — fraction × fill price → realised slice.',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
                height: 1.3,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            for (int i = 0; i < fills.length; i++) ...[
              _FillRow(fill: fills[i]),
              if (i < fills.length - 1)
                const Divider(
                  color: LuminColors.cardBorder,
                  height: LuminSpacing.lg,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FillRow extends StatelessWidget {
  const _FillRow({required this.fill});
  final PartialFill fill;

  @override
  Widget build(BuildContext context) {
    final positive = fill.pnlUsd >= 0;
    final color = positive ? LuminColors.success : LuminColors.loss;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LuminSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: LuminColors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
              ),
              child: Text(
                'TP${fill.tpLevel}',
                style: const TextStyle(
                  color: LuminColors.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: LuminSpacing.sm),
            Text(
              '${(fill.fraction * 100).toStringAsFixed(0)}% closed',
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              formatPnl(fill.pnlUsd),
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: LuminSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                'Fill ${formatPrice(fill.fillPrice)}',
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
            Text(
              'Fee \$${fill.feeUsd.toStringAsFixed(4)}',
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _formatTs(fill.ts),
          style: const TextStyle(
            color: LuminColors.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared section card + row helpers
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.rows,
  });
  final String title;
  final IconData icon;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: LuminColors.accent, size: 16),
                const SizedBox(width: LuminSpacing.xs),
                Text(
                  title,
                  style: const TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            for (final r in rows) r,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.valueColor,
    this.monospace = false,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: LuminSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? LuminColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: monospace ? 'monospace' : null,
                letterSpacing: monospace ? 0 : -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top-level helpers — kept private to the file so adjacent layouts can
// reuse the formatting decisions without exposing them as shared API.
// ---------------------------------------------------------------------------

String _formatQty(double q) {
  if (q.abs() >= 100) return q.toStringAsFixed(2);
  if (q.abs() >= 1) return q.toStringAsFixed(3);
  if (q.abs() >= 0.01) return q.toStringAsFixed(4);
  return q.toStringAsFixed(5);
}

/// Strip the USDT suffix for asset-name display: ``BTCUSDT`` → ``BTC``.
String _baseAsset(String symbol) {
  if (symbol.endsWith('USDT')) {
    return symbol.substring(0, symbol.length - 4);
  }
  return symbol;
}

/// UTC ISO-ish display: ``2026-05-16 14:32:08``.  No timezone suffix —
/// the engine speaks UTC end-to-end and surfacing a Z would clutter the
/// dense detail grid.  Lumin localises display on a separate pass.
String _formatTs(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final u = t.toUtc();
  return '${u.year}-${two(u.month)}-${two(u.day)} '
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
}

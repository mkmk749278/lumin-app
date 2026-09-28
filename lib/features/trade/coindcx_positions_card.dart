/// CoinDCX positions on the Trade tab (2026-09-28).
///
/// Owner screenshot: a CoinDCX order placed by Lumin, and the Trade tab
/// underneath it reading *"Binance shows no open positions on your account"*
/// and *"Placed on Binance"*.  The Live tab was Binance-only end to end, so a
/// user on CoinDCX saw a flat Binance account and nothing of the trade Lumin
/// had just opened for them.
///
/// This card is the CoinDCX counterpart of the Binance positions card: it
/// renders the engine's own CoinDCX records (`GET /api/coindcx/positions`) —
/// the engine is the source of truth — and never a Binance sentence.
///
/// **A live position without a resting stop is said in red, by name.** The
/// first cut of this row (on the Trading platform page) read *"Placing
/// stop…"* whenever `sl_resting` was false — a calming progress caption over
/// what, three minutes after the fill, was a naked position (HBARUSDT,
/// 2026-09-28).  Reassuring copy is the dangerous direction on a money
/// screen: a filled position with no stop now says so and gives the level to
/// set by hand.
library;

import 'package:flutter/material.dart';

import '../../data/coindcx_models.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';

/// One CoinDCX position row — shared by the Trade tab and the Trading
/// platform page so the same record never reads differently on two screens.
class CoinDCXPositionTile extends StatelessWidget {
  const CoinDCXPositionTile({super.key, required this.position});

  final CoinDCXPosition position;

  /// A filled position with no stop resting on CoinDCX.
  static bool isNaked(CoinDCXPosition p) =>
      (p.state == 'OPEN' || p.state == 'CLOSING') && !p.slResting;

  static String reasonLabel(String r) => const {
        'SL': 'Stopped out',
        'TP1': 'Target hit',
        'EXIT': 'Closed',
        'AGE_CAP': 'Closed (time limit)',
        'LIQUIDATED': 'Liquidated',
        'PROTECTION_FAILED': 'Closed — stop could not be placed',
        'LIQUIDATION_INSIDE_STOP': 'Closed — liquidation was nearer than the stop',
        'EXTERNAL': 'Closed on CoinDCX',
      }[r] ??
      r;

  @override
  Widget build(BuildContext context) {
    final p = position;
    final inr = p.marginCurrency == 'INR';
    // Net of CoinDCX's fees where both fills reported one; otherwise the
    // gross move, labelled as such — never a gross figure passed off as net.
    final net = inr ? p.netPnlInr : p.netPnlUsdt;
    final isNet = net != null;
    final pnl = net ?? (inr ? p.realizedPnlInr : p.realizedPnlUsdt);
    final pnlText = pnl == null
        ? (p.isLive ? 'Open' : '—')
        : '${pnl >= 0 ? '+' : ''}${inr ? '₹' : ''}${pnl.toStringAsFixed(2)}${inr ? '' : ' USDT'}';
    final pnlNote = pnl == null ? null : (isNet ? 'after fees' : 'before fees');
    final color = pnl == null
        ? LuminColors.textSecondary
        : (pnl >= 0 ? LuminColors.success : LuminColors.loss);
    final naked = isNaked(p);
    final String reason;
    if (naked) {
      reason = 'NO STOP on CoinDCX — set SL ${formatPrice(p.slPrice)} in '
          'CoinDCX now, or close it';
    } else if (p.state == 'PENDING' || p.state == 'ENTRY_UNCERTAIN') {
      reason = 'Confirming the entry with CoinDCX';
    } else if (p.isLive) {
      reason = 'Stop ${formatPrice(p.slPrice)} placed on CoinDCX';
    } else {
      reason = p.closeReason.isEmpty ? p.state : reasonLabel(p.closeReason);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: LuminSpacing.sm),
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: naked ? Border.all(color: LuminColors.loss) : null,
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.symbol} · ${p.side}',
                style: const TextStyle(
                    color: LuminColors.textPrimary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              '$reason · ${p.leverage.toStringAsFixed(0)}x ${p.marginCurrency}',
              key: naked ? const Key('coindcx-naked') : null,
              style: TextStyle(
                color: naked ? LuminColors.loss : LuminColors.textSecondary,
                fontSize: 12,
                fontWeight: naked ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(pnlText, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          if (pnlNote != null)
            Text(pnlNote,
                style: const TextStyle(color: LuminColors.textMuted, fontSize: 11)),
        ]),
      ]),
    );
  }
}

/// "YOUR OPEN POSITIONS" for a user whose platform is CoinDCX.
class CoinDCXPositionsCard extends StatelessWidget {
  const CoinDCXPositionsCard({super.key, required this.book});

  /// `null` while loading.
  final CoinDCXPositions? book;

  @override
  Widget build(BuildContext context) {
    final b = book;
    final live = b == null
        ? const <CoinDCXPosition>[]
        : b.positions.where((p) => p.isLive).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: LuminColors.textSecondary),
              const SizedBox(width: LuminSpacing.sm),
              const Text(
                'YOUR OPEN POSITIONS · COINDCX',
                style: TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                // A dash, not "0": an unreadable book is not an empty one.
                b == null || !b.readable ? '—' : '${live.length}',
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
            const SizedBox(height: LuminSpacing.sm),
            if (b == null)
              const Text('Loading your CoinDCX trades…',
                  style: TextStyle(color: LuminColors.textSecondary, fontSize: 13))
            else if (!b.readable)
              const Text(
                'Lumin can\'t confirm your CoinDCX positions right now — the '
                'engine\'s record could not be read. Your CoinDCX app shows '
                'what your account holds.',
                style: TextStyle(color: LuminColors.warn, fontSize: 13),
              )
            else if (live.isEmpty)
              // Our record, not the exchange's: say so, rather than claim the
              // CoinDCX account is flat — the user may hold their own trades.
              const Text(
                'Lumin has no open trades for you on CoinDCX right now. When an '
                'eligible signal fires, Lumin places the order and it shows '
                'up here. Trades you open yourself in CoinDCX are not listed.',
                style: TextStyle(color: LuminColors.textSecondary, fontSize: 13),
              )
            else
              for (final p in live) CoinDCXPositionTile(position: p),
          ],
        ),
      ),
    );
  }
}

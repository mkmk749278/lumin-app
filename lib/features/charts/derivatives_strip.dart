/// The strip under the chart: funding, open interest, long/short accounts
/// and taker flow (2026-09-25 Charts redesign, part 2).
///
/// Each tile names what the number IS in plain words ("Longs pay shorts",
/// "of accounts long") and stops there. None of it is a signal, and the
/// strip never colours a figure as good or bad for the viewer: the same
/// crowded-long reading is a warning to one trader and a confirmation to
/// the next. A figure Binance did not return shows "—", never 0.
library;

import 'package:flutter/material.dart';

import '../../data/binance_derivatives.dart';
import '../../shared/tokens.dart';
import 'market_view.dart' show formatQuoteVolume;

class DerivativesStrip extends StatelessWidget {
  const DerivativesStrip({super.key, required this.snapshot, required this.now});

  final DerivativesSnapshot? snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final funding = s?.fundingRate;
    final next = s?.nextFundingTime;
    final oi = s?.openInterestUsd;
    final oiChg = s?.openInterestChange24hPct;
    final longShare = s?.longAccountShare;
    final taker = s?.takerBuyShare;
    return Container(
      padding: const EdgeInsets.fromLTRB(LuminSpacing.md, 10, LuminSpacing.md, 10),
      decoration: const BoxDecoration(
        color: LuminColors.bgCard,
        border: Border(top: BorderSide(color: LuminColors.cardBorder)),
      ),
      child: Row(
        children: [
          _Tile(
            label: 'FUNDING',
            value: funding == null ? '—' : formatFundingRate(funding),
            sub: funding == null
                ? ' '
                : '${fundingPayerShort(funding)}${next != null ? ' · ${formatCountdown(next, now)}' : ''}',
          ),
          _Tile(
            label: 'OPEN INTEREST',
            value: oi == null ? '—' : formatQuoteVolume(oi),
            sub: oiChg == null ? ' ' : '${oiChg >= 0 ? '+' : ''}${oiChg.toStringAsFixed(1)}% in 24h',
          ),
          _Tile(
            label: 'ACCOUNTS',
            value: longShare == null ? '—' : '${(longShare * 100).round()}% long',
            sub: longShare == null ? ' ' : '${((1 - longShare) * 100).round()}% short',
            bar: longShare,
          ),
          _Tile(
            label: 'TAKERS · 1H',
            value: taker == null ? '—' : '${(taker * 100).round()}% buy',
            sub: taker == null ? ' ' : '${((1 - taker) * 100).round()}% sell',
            bar: taker,
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.sub, this.bar});
  final String label;
  final String value;
  final String sub;

  /// 0..1 split drawn as a neutral two-tone bar (never green/red: see above).
  final double? bar;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(
                    color: LuminColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: const TextStyle(
                      color: LuminColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            const SizedBox(height: 3),
            if (bar != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 4,
                  child: Row(children: [
                    Expanded(flex: (bar! * 1000).round().clamp(1, 999), child: Container(color: LuminColors.accent)),
                    Expanded(
                        flex: ((1 - bar!) * 1000).round().clamp(1, 999),
                        child: Container(color: LuminColors.accentMuted.withValues(alpha: 0.45))),
                  ]),
                ),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(sub,
                    maxLines: 1,
                    style: const TextStyle(color: LuminColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            if (bar != null) ...[
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(sub,
                    maxLines: 1,
                    style: const TextStyle(color: LuminColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

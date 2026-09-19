/// What this order can lose if the stop does its job.
///
/// Why this exists (handoff §14, 2026-09-19): the Take Signal review sheet
/// showed wallet equity, position size, leverage, notional and quantity — five
/// numbers about how BIG the position is, and not one about what it can cost.
/// The user was asked to confirm a real-money futures order whose downside was
/// derivable from the numbers on screen but nowhere stated, and the button
/// said `Confirm`.
///
/// The arithmetic is deliberately trivial and deliberately lives here rather
/// than inline in the sheet: it is the one figure on that screen a user makes
/// a decision from, so it gets a name, a test, and a single definition shared
/// by both execution paths (device-signed and server-side).
///
/// **It is "planned", not "maximum", and the distinction is not pedantry.** A
/// stop is an instruction to the exchange, not a guarantee: a gap through the
/// level, a liquidity hole, or a venue halt all fill worse than the stop
/// price. Calling this figure a maximum would be the reassuring-in-the-wrong-
/// direction error this repo already has a rule about — so the number is
/// labelled as what it is, and the sheet says a gap can exceed it.
library;

import 'package:flutter/material.dart';

import '../../shared/tokens.dart';

/// Loss in quote currency (USDT) if [stopLoss] fills exactly, for a position
/// of [notionalUsd] opened at [entry].
///
/// Direction-free by construction: the loss is the stop's *distance* from
/// entry, which is what the position is risking whether it is long or short.
/// A long stopped below entry and a short stopped above it risk the same
/// fraction of the same notional.
///
/// Returns null rather than a number when the inputs cannot support the
/// claim — a zero here would render as `$0.00 at risk` over a real order,
/// which is the one wrong answer worse than no answer:
///
///  * a non-positive [entry] (nothing to divide by, and no valid order),
///  * a non-positive [notionalUsd] (no position to lose),
///  * a [stopLoss] at or below zero (not a price),
///  * a [stopLoss] equal to [entry] (a breakeven-ratcheted signal risks
///    nothing on paper, and printing `$0.00` would invite the reader to
///    believe the trade cannot lose — it can, via slippage and fees).
///
/// Non-finite inputs are refused for the same reason.
double? plannedLossUsd({
  required double entry,
  required double stopLoss,
  required double notionalUsd,
}) {
  if (!entry.isFinite || !stopLoss.isFinite || !notionalUsd.isFinite) {
    return null;
  }
  if (entry <= 0 || notionalUsd <= 0 || stopLoss <= 0) return null;
  final distance = (entry - stopLoss).abs();
  if (distance <= 0) return null;
  return notionalUsd * (distance / entry);
}

/// The same risk as a percentage of the position's notional — i.e. how far
/// the stop sits from entry.
///
/// Published beside the money figure because the two answer different
/// questions: the dollar amount is what this trade costs today, the
/// percentage is whether the stop is tight or wide, which is the number that
/// makes two signals comparable. Same refusals as [plannedLossUsd].
double? plannedLossPct({
  required double entry,
  required double stopLoss,
}) {
  if (!entry.isFinite || !stopLoss.isFinite) return null;
  if (entry <= 0 || stopLoss <= 0) return null;
  final distance = (entry - stopLoss).abs();
  if (distance <= 0) return null;
  return distance / entry * 100.0;
}

/// The planned downside, rendered as money and as stop distance.
///
/// A public widget rather than a private method on the review sheet, so it
/// can be pumped in a widget test: the sheet itself cannot be, because
/// reaching it needs Binance keys, per-user settings, an `AppConfigScope` and
/// an Assist-tier entitlement. A figure whose arithmetic is tested but whose
/// rendering never is, is how a correct number ships behind a broken layout —
/// and this is the number a user decides from.
///
/// Refuses rather than guessing. When [plannedLossPct] cannot answer — a
/// breakeven-ratcheted stop, an unreadable entry — this renders **nothing**,
/// not a zero. `$0.00` beside a real order invites the reader to believe the
/// trade cannot lose.
class PlannedLossRow extends StatelessWidget {
  const PlannedLossRow({
    super.key,
    required this.entry,
    required this.stopLoss,
    this.notionalUsd,
  });

  final double entry;
  final double stopLoss;

  /// Null on the server-side path when the engine has not told us the size.
  /// The percentage still renders — it is a property of the geometry and
  /// needs no notional — because "3.00% of position" is a great deal more
  /// use than nothing at all.
  final double? notionalUsd;

  @override
  Widget build(BuildContext context) {
    final pct = plannedLossPct(entry: entry, stopLoss: stopLoss);
    if (pct == null) return const SizedBox.shrink();
    final usd = notionalUsd == null
        ? null
        : plannedLossUsd(
            entry: entry,
            stopLoss: stopLoss,
            notionalUsd: notionalUsd!,
          );
    final value = usd == null
        ? '${pct.toStringAsFixed(2)}% of position'
        : '-\$${usd.toStringAsFixed(2)}  (${pct.toStringAsFixed(2)}%)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Planned loss if stopped',
                  style: TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: LuminColors.loss,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Text(
          'A gap through the stop can cost more than this.',
          style: TextStyle(
            color: LuminColors.textMuted,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

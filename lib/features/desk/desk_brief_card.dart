/// The Desk Brief — the hourly analyst's latest read, at the top of the Desk
/// tab (Lumin 2.0, 2026-11-26).
///
/// Renders `GET /api/desk` and decides nothing itself. Every state the engine
/// can be in has its own sentence, because a blank card and a stand-aside
/// brief must never look alike:
///   * a current plan  → bias, age, notes, BTC context
///   * a stale plan    → the same, under an amber "no new brief for Xh"
///   * no plan yet     → says so
///   * not reported    → the engine has not published a desk
///   * disabled        → nothing (the owner switched the surface off)
///   * request failed  → says the brief could not be loaded
library;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';

class DeskBriefCard extends StatefulWidget {
  const DeskBriefCard({super.key});

  @override
  State<DeskBriefCard> createState() => DeskBriefCardState();
}

class DeskBriefCardState extends State<DeskBriefCard> {
  Future<DeskResponse>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppConfigScope.of(context).repo.fetchDesk();
  }

  /// Re-reads the desk (pull-to-refresh, foreground).
  void refresh() {
    setState(() {
      _future = AppConfigScope.of(context).repo.fetchDesk();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeskResponse>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Frame(child: _Loading());
        }
        if (snap.hasError || !snap.hasData) {
          return const _Frame(
            child: _Note(
              key: Key('desk.brief.failed'),
              text: "Couldn't load the desk brief. Pull down to try again.",
            ),
          );
        }
        return DeskBriefView(response: snap.data!, now: DateTime.now().toUtc());
      },
    );
  }
}

/// The card for one response. Separate from the fetch so every state can be
/// rendered and tested without a network.
class DeskBriefView extends StatelessWidget {
  const DeskBriefView({super.key, required this.response, required this.now});

  final DeskResponse response;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    switch (response.state) {
      case 'disabled':
        return const SizedBox.shrink(key: Key('desk.brief.disabled'));
      case 'ok':
        break;
      default:
        return const _Frame(
          child: _Note(
            key: Key('desk.brief.not_reported'),
            text: "The desk brief isn't available right now.",
          ),
        );
    }
    final desk = response.desk!;
    final brief = desk.brief;
    final plan = brief.plan;
    if (plan == null) {
      return const _Frame(
        child: _Note(
          key: Key('desk.brief.none'),
          text: 'No desk brief yet. The analyst publishes one every hour.',
        ),
      );
    }
    final stale = brief.freshness == BriefFreshness.stale;
    final age = plan.submittedAt == null ? null : now.difference(plan.submittedAt!);
    return _Frame(
      key: Key(stale ? 'desk.brief.stale' : 'desk.brief.current'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('DESK BRIEF', style: LuminType.eyebrow),
              const SizedBox(width: LuminSpacing.sm),
              _BiasPill(bias: plan.bias, label: desk.labels.biasOf(plan.bias)),
              const Spacer(),
              if (age != null)
                Text(
                  'Updated ${_ago(age)}',
                  style: LuminType.number(
                      fontSize: 12, color: LuminColors.textMuted),
                ),
            ],
          ),
          if (stale && age != null) ...[
            const SizedBox(height: LuminSpacing.sm),
            Text(
              'No new brief for ${_ago(age, suffix: false)}. This is the '
              "analyst's last read, not this hour's.",
              key: const Key('desk.brief.stale_note'),
              style: const TextStyle(
                  color: LuminColors.warn, fontSize: 13, height: 1.4),
            ),
          ],
          const SizedBox(height: LuminSpacing.md),
          _Market(market: brief.market),
          if (plan.notes.isNotEmpty) ...[
            const SizedBox(height: LuminSpacing.md),
            Text(
              plan.notes,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: LuminSpacing.md),
          Text(
            plan.stoodAside
                ? 'This hour: no setup published — the desk stood aside.'
                : 'This hour: ${plan.nAccepted} setup'
                    '${plan.nAccepted == 1 ? '' : 's'} published '
                    '(${plan.accepted.map((a) => '${a.symbol} ${a.side}').join(', ')}).',
            style: const TextStyle(
                color: LuminColors.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

String _ago(Duration d, {bool suffix = true}) {
  final s = suffix ? ' ago' : '';
  if (d.inMinutes < 1) return suffix ? 'just now' : 'under a minute';
  if (d.inMinutes < 60) return '${d.inMinutes}m$s';
  if (d.inHours < 48) return '${d.inHours}h$s';
  return '${d.inDays}d$s';
}

class _Frame extends StatelessWidget {
  const _Frame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
        child: LuminCard(child: child),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 96,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DESK BRIEF', style: LuminType.eyebrow),
          const SizedBox(height: LuminSpacing.sm),
          Text(text,
              style: const TextStyle(
                  color: LuminColors.textSecondary, fontSize: 14, height: 1.4)),
        ],
      );
}

class _BiasPill extends StatelessWidget {
  const _BiasPill({required this.bias, required this.label});
  final String? bias;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = switch (bias) {
      'risk_on' => LuminColors.success,
      'risk_off' => LuminColors.loss,
      'stand_aside' => LuminColors.warn,
      _ => LuminColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: LuminColors.tint(c),
        borderRadius: BorderRadius.circular(LuminRadii.pill),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.66,
        ),
      ),
    );
  }
}

class _Market extends StatelessWidget {
  const _Market({required this.market});
  final DeskMarket market;

  @override
  Widget build(BuildContext context) {
    if (!market.readable || market.btcPrice == null) {
      return const Text(
        'BTC context unavailable right now.',
        key: Key('desk.brief.market_unreadable'),
        style: TextStyle(color: LuminColors.textMuted, fontSize: 13),
      );
    }
    final ch = market.btcChange24hPct;
    final share = market.breadthReadable ? market.shareBeatingBtc7d : null;
    return Wrap(
      spacing: LuminSpacing.lg,
      runSpacing: LuminSpacing.xs,
      children: [
        _Fig(label: 'BTC', value: _price(market.btcPrice!)),
        if (ch != null)
          _Fig(
            label: '24H',
            value: '${ch >= 0 ? '+' : ''}${ch.toStringAsFixed(2)}%',
            color: ch >= 0 ? LuminColors.success : LuminColors.loss,
          ),
        _Fig(
          label: 'ALTS > BTC 7D',
          value: share == null ? '—' : '${(share * 100).round()}%',
        ),
      ],
    );
  }

  static String _price(double p) {
    final whole = p.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    return '\$$b';
  }
}

class _Fig extends StatelessWidget {
  const _Fig({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: LuminType.eyebrow),
          const SizedBox(height: 2),
          Text(value,
              style: LuminType.number(
                  fontSize: 15, color: color ?? LuminColors.textPrimary)),
        ],
      );
}

/// "Lumin read" — the engine's description of one pair (Charts redesign part 3).
///
/// Owner: manual traders "don't know how to react … based on current market
/// structure". This sheet is what the engine measured on the chart, in plain
/// words: the 4h leg, the nearest levels, where price sits against the
/// week's value area, what on the chart sits with a LONG and what with a
/// SHORT, and Lumin's own closed signals here — losses included.
///
/// It gives no verdict, no score and no instruction. The checklist lists
/// facts on both sides and the reader weighs them; the footer says so. The
/// checklist is part of the live-signal plan and the engine withholds it
/// from callers without live access (`checklist_locked`), so there is
/// nothing here to unlock client-side.
library;

import 'package:flutter/material.dart';

import '../../app/distribution.dart';
import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import '../auth/widgets/account_required.dart';
import '../settings/pages/subscription_page.dart';
import '../settings/pages/web_paywall_page.dart';
import 'coin_icon.dart';
import 'market_view.dart' show baseAsset, formatMarketPrice;

Future<void> showPairReadSheet(BuildContext context, {required String symbol, required PairContext? read}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: LuminColors.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.94,
      minChildSize: 0.4,
      builder: (ctx, scroll) => PairReadView(symbol: symbol, read: read, controller: scroll),
    ),
  );
}

class PairReadView extends StatelessWidget {
  const PairReadView({super.key, required this.symbol, required this.read, this.controller});
  final String symbol;
  final PairContext? read;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final r = read;
    final base = baseAsset(symbol);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(LuminSpacing.lg, LuminSpacing.md, LuminSpacing.lg, LuminSpacing.xxl),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: LuminSpacing.md),
            decoration: BoxDecoration(color: LuminColors.textMuted, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Row(children: [
          CoinIcon(symbol: symbol, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Lumin read · $base',
                style: const TextStyle(color: LuminColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          _asOf(r),
          style: const TextStyle(color: LuminColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: LuminSpacing.lg),
        ..._body(context, r),
        const SizedBox(height: LuminSpacing.lg),
        const Text(
          'What the engine measured on this chart, in plain words. It is not a '
          'prediction and not financial advice: the same fact can support one '
          'trade and warn against another, and you decide which.',
          style: TextStyle(color: LuminColors.textMuted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  static String _asOf(PairContext? r) {
    final t = r?.readAt;
    if (t == null) return "The engine's view of this chart";
    final hh = t.hour.toString().padLeft(2, '0'), mm = t.minute.toString().padLeft(2, '0');
    final age = DateTime.now().toUtc().difference(t);
    final stale = age.inMinutes > 10 ? ' · ${age.inMinutes} min old' : '';
    return "The engine's view as of $hh:$mm UTC$stale";
  }

  List<Widget> _body(BuildContext context, PairContext? r) {
    if (r == null) {
      return const [_Note('Loading Lumin\'s read…')];
    }
    final out = <Widget>[];
    switch (r.state) {
      case PairContextState.notTracked:
        out.add(const _Note(
            "Lumin doesn't scan this pair, so the engine has no levels or structure for it. "
            'Pairs Lumin scans are the ones that can get a signal.'));
      case PairContextState.notReported:
        out.add(const _Note("Lumin's read isn't available right now. Try again in a minute."));
      case PairContextState.covered:
        out.addAll(_covered(context, r));
    }
    out.add(const SizedBox(height: LuminSpacing.lg));
    out.add(_PastSignals(signals: r.pastSignals));
    return out;
  }

  List<Widget> _covered(BuildContext context, PairContext r) {
    final w = <Widget>[];
    final st = r.structure4h;
    w.add(_Section(
      title: '4H STRUCTURE',
      child: Text(st == null ? '—' : st.words,
          style: const TextStyle(color: LuminColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
    ));
    w.add(_Section(
      title: 'NEAREST LEVELS',
      child: Column(children: [
        for (final l in r.resistances.reversed) _LevelRow(level: l, support: false),
        if (r.price != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Expanded(child: Divider(color: LuminColors.accentMuted)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.sm),
                child: Text('Price ${formatMarketPrice(r.price!)}',
                    style: const TextStyle(color: LuminColors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const Expanded(child: Divider(color: LuminColors.accentMuted)),
            ]),
          ),
        for (final l in r.supports) _LevelRow(level: l, support: true),
        if (r.supports.isEmpty && r.resistances.isEmpty)
          const Text('No measured level within 12% of price.',
              style: TextStyle(color: LuminColors.textSecondary)),
      ]),
    ));
    final va = r.valueArea;
    if (va != null) {
      final where = switch (va.position) {
        'above_value' => 'above',
        'below_value' => 'below',
        _ => 'inside',
      };
      w.add(_Section(
        title: "WEEK'S VALUE AREA",
        child: Text(
          'Price is $where the value area '
          '(${formatMarketPrice(va.val)} – ${formatMarketPrice(va.vah)}). '
          'Most volume traded at ${formatMarketPrice(va.poc)} (POC).',
          style: const TextStyle(color: LuminColors.textPrimary, fontSize: 14, height: 1.4),
        ),
      ));
    }
    final c = r.checklist;
    if (c != null) {
      w.add(_Section(title: 'WHAT SITS WITH A LONG', child: _Bullets(items: c.long, color: LuminColors.success)));
      w.add(_Section(title: 'WHAT SITS WITH A SHORT', child: _Bullets(items: c.short, color: LuminColors.loss)));
      if (c.neutral.isNotEmpty) {
        w.add(_Section(title: 'ALSO ON THE CHART', child: _Bullets(items: c.neutral, color: LuminColors.textSecondary)));
      }
    } else if (r.checklistLocked) {
      w.add(const _LockedChecklist());
    }
    return w;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: LuminColors.textMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        child,
      ]),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({required this.level, required this.support});
  final PairLevel level;
  final bool support;

  @override
  Widget build(BuildContext context) {
    final c = support ? LuminColors.success : LuminColors.loss;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LuminSpacing.xs),
      child: Row(children: [
        Container(width: 4, height: 28, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatMarketPrice(level.price),
                style: const TextStyle(color: LuminColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            Text(
              '${support ? 'Support' : 'Resistance'} · ${level.touches} touch${level.touches == 1 ? '' : 'es'}'
              '${level.timeframes.isEmpty ? '' : ' · ${level.timeframes.join('/')}'}',
              style: const TextStyle(color: LuminColors.textSecondary, fontSize: 12),
            ),
          ]),
        ),
        Text(levelDistanceLabel(level.distPct, support: support),
            style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({required this.items, required this.color});
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Nothing measured on this side right now.',
          style: TextStyle(color: LuminColors.textSecondary, fontSize: 14));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final i in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(i, style: const TextStyle(color: LuminColors.textPrimary, fontSize: 14, height: 1.35))),
          ]),
        ),
    ]);
  }
}

class _LockedChecklist extends StatelessWidget {
  const _LockedChecklist();

  @override
  Widget build(BuildContext context) {
    final repo = AppConfigScope.maybeOf(context)?.repo;
    final guest = repo?.liveFeedAccess.value?.isGuest ?? false;
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        border: Border.all(color: LuminColors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.lock_rounded, color: LuminColors.accent, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('What sits with a LONG / a SHORT',
                style: TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ]),
        const SizedBox(height: 6),
        const Text('Part of the Signals plan, with live signals.',
            style: TextStyle(color: LuminColors.textSecondary, fontSize: 13)),
        const SizedBox(height: LuminSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              // The sheet's own context dies with the pop; act on the route
              // underneath it.
              final nav = Navigator.of(context);
              nav.pop();
              if (guest) {
                openCreateAccount(nav.context);
                return;
              }
              nav.push(MaterialPageRoute(
                builder: (_) => kDistribution == AppDistribution.web
                    ? const WebPaywallPage()
                    : const SubscriptionPage(),
              ));
            },
            child: Text(guest ? 'Sign up free — 3 days included' : 'See plans'),
          ),
        ),
      ]),
    );
  }
}

class _PastSignals extends StatelessWidget {
  const _PastSignals({required this.signals});
  final List<PastSignal> signals;

  @override
  Widget build(BuildContext context) {
    final wins = signals.where((s) => s.won == true).length;
    final losses = signals.where((s) => s.won == false).length;
    return _Section(
      title: 'LUMIN ON THIS PAIR · 30 DAYS',
      child: signals.isEmpty
          ? const Text('No closed Lumin signals on this pair in 30 days.',
              style: TextStyle(color: LuminColors.textSecondary, fontSize: 14))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${signals.length} closed · $wins won · $losses lost — every one shown',
                  style: const TextStyle(color: LuminColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              for (final s in signals.take(12)) _PastRow(s: s),
            ]),
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.s});
  final PastSignal s;

  @override
  Widget build(BuildContext context) {
    final won = s.won;
    final c = won == null ? LuminColors.textSecondary : (won ? LuminColors.success : LuminColors.loss);
    final d = s.closedAt;
    final date = d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final pnl = s.pnlPct;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: (s.isLong ? LuminColors.success : LuminColors.loss).withValues(alpha: 0.6)),
          ),
          child: Text(s.isLong ? 'LONG' : 'SHORT',
              style: TextStyle(
                  color: s.isLong ? LuminColors.success : LuminColors.loss,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('$date · ${s.outcome.isEmpty ? 'closed' : s.outcome.replaceAll('_', ' ').toLowerCase()}',
              style: const TextStyle(color: LuminColors.textPrimary, fontSize: 13)),
        ),
        Text(pnl == null ? '—' : '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}%',
            style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        border: Border.all(color: LuminColors.cardBorder),
      ),
      child: Text(text, style: const TextStyle(color: LuminColors.textSecondary, fontSize: 14, height: 1.4)),
    );
  }
}

/// "0.8% below" — or "At price" when the level is within rounding of it.
/// "0.0% below" read as a bug (UX review 2026-09-25).
String levelDistanceLabel(double distPct, {required bool support}) {
  final d = distPct.abs();
  if (d < 0.05) return 'At price';
  return '${d.toStringAsFixed(1)}% ${support ? 'below' : 'above'}';
}

/// Charts tab — the Markets board (2026-09-25 redesign, part 1).
///
/// Owner: the tab "looks outdated". It was one flat text list sorted by
/// volume. Now:
///   * a market strip — BTC, ETH, and how the whole board moved (breadth);
///   * segments — Favourites, Lumin live, Hot, Gainers, Losers
///     (the selection logic is pure, in `market_view.dart`, and unit-tested);
///   * rows with a coin icon, 24h sparkline, price and a filled change pill,
///     a LIVE badge where Lumin has a live signal, and a star to favourite.
///
/// Data is unchanged in kind: Binance public 24h ticker + exchangeInfo,
/// app→Binance direct, plus one light klines call per VISIBLE row for its
/// sparkline (`sparkline.dart`). The engine is asked only for the signals it
/// already serves the Signals tab.
///
/// A LIVE badge means a signal the engine says is open (`is_open`), never
/// merely a row in an `open` answer: on 2026-09-25 a guest's `status=open`
/// read came back with closed signals, and this page badged finished trades
/// as live (engine #1067). For a caller without live access the badge comes
/// from the engine's masked `locked_items` — symbol only, the same fact the
/// Signals tab's masked cards already show — and opens no levels.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/foreground_refresh.dart';
import '../../app/scroll_to_top.dart';
import '../../data/app_config.dart';
import '../../data/binance_market_data.dart';
import '../../data/favourite_pairs.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/shimmer.dart';
import 'chart_page.dart';
import 'coin_icon.dart';
import 'market_view.dart';
import 'models/candle.dart';
import 'sparkline.dart';

export 'market_view.dart' show orderPairRows;

class ChartsPage extends StatefulWidget {
  const ChartsPage({super.key});

  @override
  State<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<ChartsPage> implements ForegroundRefreshable, ScrollToTop {
  /// The longest list in the app — the whole tradable perpetual universe —
  /// so a tap on the active tab returning it to the top matters most here.
  final ScrollController _listController = ScrollController();
  final BinanceMarketData _md = BinanceMarketData();
  late final SparklineCache _sparks = SparklineCache(_md);
  late Future<List<MarketTicker>> _future;
  String _query = '';
  MarketSegment _segment = MarketSegment.hot;
  Set<String> _favourites = {};

  LuminRepository? _repo;
  StreamSubscription<List<MockSignal>>? _sigSub;

  /// Latest OPEN Lumin signal per symbol — badge + chart overlay source.
  Map<String, MockSignal> _liveBySymbol = const {};

  @override
  void initState() {
    super.initState();
    _future = _load();
    FavouritePairs.load().then((f) {
      if (mounted) setState(() => _favourites = f);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      _repo = AppConfigScope.maybeOf(context)?.repo;
      _subscribeSignals();
    }
  }

  @override
  void dispose() {
    _listController.dispose();
    _sigSub?.cancel();
    _sparks.close();
    _md.close();
    super.dispose();
  }

  @override
  void scrollToTop() {
    if (!_listController.hasClients) return;
    _listController.animateTo(0, duration: kScrollToTopDuration, curve: kScrollToTopCurve);
  }

  @override
  void refreshFromForeground() {
    if (!mounted) return;
    setState(() => _future = _load());
    _subscribeSignals();
  }

  void _subscribeSignals() {
    final repo = _repo;
    if (repo == null) return;
    _sigSub?.cancel();
    _sigSub = repo.watchSignals(status: 'open', limit: 100).listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _liveBySymbol = {
            for (final s in items)
              if (s.effectiveIsOpen) s.symbol: s,
          };
        });
      },
      onError: (_) {/* engine unreachable — badges just stay off */},
    );
  }

  Future<List<MarketTicker>> _load() async {
    final perps = (await _md.perpetualSymbols()).toSet();
    final tickers = await _md.ticker24h();
    final rows = [
      for (final t in tickers)
        if (perps.contains(t.symbol)) t,
    ];
    rows.sort((a, b) => b.quoteVolume.compareTo(a.quoteVolume));
    return rows;
  }

  void _toggleFavourite(String symbol) {
    setState(() {
      _favourites = {..._favourites};
      if (!_favourites.remove(symbol)) _favourites.add(symbol);
    });
    FavouritePairs.save(_favourites);
  }

  void _open(String symbol) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChartPage(symbol: symbol, signal: _liveBySymbol[symbol]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      appBar: AppBar(
        backgroundColor: LuminColors.bgDeep,
        title: const Text('Markets'),
      ),
      body: ValueListenableBuilder<LiveFeedAccess?>(
        valueListenable: repo?.liveFeedAccess ?? ValueNotifier<LiveFeedAccess?>(null),
        builder: (context, access, _) {
          final lockedSymbols = <String>{
            if (access != null && access.locked)
              for (final l in access.lockedItems) l.symbol,
          };
          final liveSymbols = {..._liveBySymbol.keys, ...lockedSymbols};
          return FutureBuilder<List<MarketTicker>>(
            future: _future,
            // Cross-fade skeleton → board (UX review 2026-09-25).
            builder: (context, snap) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _board(context, snap, liveSymbols, lockedSymbols),
            ),
          );
        },
      ),
    );
  }

  Widget _board(
    BuildContext context,
    AsyncSnapshot<List<MarketTicker>> snap,
    Set<String> liveSymbols,
    Set<String> lockedSymbols,
  ) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return const _MarketsSkeleton(key: ValueKey('markets-skeleton'));
    }
    if (snap.hasError) {
      return KeyedSubtree(key: const ValueKey('markets-error'), child: _Error(onRetry: refreshFromForeground));
    }
    final all = snap.data ?? const <MarketTicker>[];
    final searching = _query.isNotEmpty;
    final rows = searching
        ? orderPairRows(searchRows(all, _query), liveSymbols)
        : segmentRows(all, _segment, favourites: _favourites, liveSymbols: liveSymbols);
    return RefreshIndicator(
      key: const ValueKey('markets-data'),
      onRefresh: () {
        setState(() => _future = _load());
        _subscribeSignals();
        return _future;
      },
      child: CustomScrollView(
        controller: _listController,
        slivers: [
          SliverToBoxAdapter(
            child: _SearchField(onChanged: (v) => setState(() => _query = v.trim())),
          ),
          if (!searching) SliverToBoxAdapter(child: _MarketStrip(all: all, onOpen: _open)),
          if (!searching)
            SliverToBoxAdapter(
              child: _SegmentBar(
                selected: _segment,
                liveCount: liveSymbols.where((s) => all.any((r) => r.symbol == s)).length,
                onSelect: (s) => setState(() => _segment = s),
              ),
            ),
          SliverToBoxAdapter(child: _ColumnHeader(searching: searching, segment: _segment)),
          if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(segment: searching ? null : _segment),
            )
          else
            SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                return _PairRow(
                  key: ValueKey(r.symbol),
                  t: r,
                  signal: _liveBySymbol[r.symbol],
                  locked: lockedSymbols.contains(r.symbol),
                  favourite: _favourites.contains(r.symbol),
                  spark: _sparks.watch(r.symbol),
                  onTap: _open,
                  onStar: _toggleFavourite,
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: LuminSpacing.xl)),
        ],
      ),
    );
  }
}

Color _changeColor(double pct) => switch (changeDirection(pct)) {
      1 => LuminColors.success,
      -1 => LuminColors.loss,
      _ => LuminColors.textSecondary,
    };

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(LuminSpacing.lg, LuminSpacing.xs, LuminSpacing.lg, LuminSpacing.md),
      child: TextField(
        onChanged: onChanged,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: LuminColors.textSecondary),
          hintText: 'Search any coin — BTC, SOL, PEPE…',
          hintStyle: const TextStyle(color: LuminColors.textMuted),
          filled: true,
          fillColor: LuminColors.bgCard,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(LuminRadii.pill),
            borderSide: const BorderSide(color: LuminColors.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(LuminRadii.pill),
            borderSide: const BorderSide(color: LuminColors.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(LuminRadii.pill),
            borderSide: const BorderSide(color: LuminColors.accent),
          ),
        ),
      ),
    );
  }
}

/// BTC · ETH cards and the board's breadth, above the tabs.
class _MarketStrip extends StatelessWidget {
  const _MarketStrip({required this.all, required this.onOpen});
  final List<MarketTicker> all;
  final void Function(String) onOpen;

  MarketTicker? _find(String s) {
    for (final r in all) {
      if (r.symbol == s) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final btc = _find('BTCUSDT'), eth = _find('ETHUSDT');
    final breadth = marketBreadth(all);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: SizedBox(
        height: 92,
        child: Row(
          children: [
            if (btc != null) Expanded(child: _MajorCard(t: btc, onTap: () => onOpen(btc.symbol))),
            if (eth != null) Expanded(child: _MajorCard(t: eth, onTap: () => onOpen(eth.symbol))),
            Expanded(flex: 1, child: _BreadthCard(b: breadth)),
          ],
        ),
      ),
    );
  }
}

class _MajorCard extends StatelessWidget {
  const _MajorCard({required this.t, required this.onTap});
  final MarketTicker t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = _changeColor(t.changePct);
    return Padding(
      padding: const EdgeInsets.only(right: LuminSpacing.sm),
      child: Material(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(LuminRadii.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LuminRadii.md),
              border: Border.all(color: LuminColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  CoinIcon(symbol: t.symbol, size: 22),
                  const SizedBox(width: 8),
                  Text(baseAsset(t.symbol),
                      style:
                          const TextStyle(color: LuminColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
                Text(formatMarketPrice(t.lastPrice),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        fontFeatures: [FontFeature.tabularFigures()])),
                Text(formatChangePct(t.changePct),
                    style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BreadthCard extends StatelessWidget {
  const _BreadthCard({required this.b});
  final MarketBreadth b;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        border: Border.all(color: LuminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('MARKET',
              style:
                  TextStyle(color: LuminColors.textMuted, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1)),
          Text(b.mood,
              style: const TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                Expanded(flex: (b.upShare * 1000).round().clamp(1, 999), child: Container(color: LuminColors.success)),
                Expanded(
                    flex: ((1 - b.upShare) * 1000).round().clamp(1, 999), child: Container(color: LuminColors.loss)),
              ]),
            ),
          ),
          Text('${b.up}↑ · ${b.down}↓',
              style: const TextStyle(color: LuminColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.selected, required this.onSelect, required this.liveCount});
  final MarketSegment selected;
  final ValueChanged<MarketSegment> onSelect;
  final int liveCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(LuminSpacing.lg, LuminSpacing.md, LuminSpacing.lg, LuminSpacing.xs),
        children: [
          for (final s in MarketSegment.values)
            Padding(
              padding: const EdgeInsets.only(right: LuminSpacing.sm),
              child: _SegmentChip(
                label: s == MarketSegment.live && liveCount > 0 ? '${s.label} · $liveCount' : s.label,
                icon: switch (s) {
                  MarketSegment.favourites => Icons.star_rounded,
                  MarketSegment.live => Icons.bolt_rounded,
                  MarketSegment.hot => Icons.local_fire_department_rounded,
                  MarketSegment.gainers => Icons.trending_up_rounded,
                  MarketSegment.losers => Icons.trending_down_rounded,
                },
                selected: s == selected,
                onTap: () => onSelect(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(LuminRadii.pill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? LuminColors.accent : LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.pill),
          border: Border.all(color: selected ? LuminColors.accent : LuminColors.cardBorder),
          boxShadow: selected ? [BoxShadow(color: LuminColors.accent.withValues(alpha: 0.35), blurRadius: 14)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: selected ? LuminColors.bgDeep : LuminColors.textSecondary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                color: selected ? LuminColors.bgDeep : LuminColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              )),
        ]),
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.searching, required this.segment});
  final bool searching;
  final MarketSegment segment;

  @override
  Widget build(BuildContext context) {
    const s = TextStyle(color: LuminColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6);
    final left = searching
        ? 'RESULTS'
        : (segment == MarketSegment.gainers || segment == MarketSegment.losers)
            ? 'PAIR · VOL ≥ \$5M'
            : 'PAIR · 24H VOL';
    return Padding(
      padding: const EdgeInsets.fromLTRB(LuminSpacing.lg, LuminSpacing.md, LuminSpacing.xs, LuminSpacing.xs),
      child: Row(children: [
        Expanded(child: Text(left, style: s)),
        const SizedBox(width: 64, child: Text('24H', style: s, textAlign: TextAlign.center)),
        const SizedBox(width: LuminSpacing.sm),
        const SizedBox(width: 100, child: Text('PRICE · CHG', style: s, textAlign: TextAlign.right)),
        const SizedBox(width: 40),
      ]),
    );
  }
}

class _PairRow extends StatelessWidget {
  const _PairRow({
    super.key,
    required this.t,
    required this.onTap,
    required this.onStar,
    required this.favourite,
    required this.spark,
    required this.locked,
    this.signal,
  });
  final MarketTicker t;
  final MockSignal? signal;
  final bool locked;
  final bool favourite;
  final ValueListenable<List<double>?> spark;
  final void Function(String symbol) onTap;
  final void Function(String symbol) onStar;

  @override
  Widget build(BuildContext context) {
    final c = _changeColor(t.changePct);
    final mult = contractMultiplier(t.symbol);
    final sig = signal;
    return InkWell(
      onTap: () => onTap(t.symbol),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(LuminSpacing.lg, 10, LuminSpacing.xs, 10),
        child: Row(
          children: [
            CoinIcon(symbol: t.symbol, size: 36),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          if (mult != null)
                            TextSpan(text: mult, style: const TextStyle(color: LuminColors.textMuted, fontSize: 12)),
                          TextSpan(
                            text: baseAsset(t.symbol),
                            style: const TextStyle(
                                color: LuminColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          const TextSpan(text: ' /USDT', style: TextStyle(color: LuminColors.textMuted, fontSize: 11)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (sig != null) ...[
                      const SizedBox(width: 6),
                      _LiveBadge(text: sig.direction.toUpperCase(), long: sig.direction.toUpperCase() == 'LONG'),
                    ] else if (locked) ...[
                      const SizedBox(width: 6),
                      const _LiveBadge(text: 'LIVE', locked: true),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(formatQuoteVolume(t.quoteVolume),
                      style: const TextStyle(color: LuminColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            ValueListenableBuilder<List<double>?>(
              valueListenable: spark,
              builder: (_, pts, __) => Sparkline(points: pts, width: 64, height: 28),
            ),
            const SizedBox(width: LuminSpacing.sm),
            SizedBox(
              width: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMarketPrice(t.lastPrice),
                      maxLines: 1,
                      style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(formatChangePct(t.changePct),
                        style: TextStyle(
                            color: c,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: favourite ? 'Remove from favourites' : 'Add to favourites',
              onPressed: () => onStar(t.symbol),
              icon: Icon(
                favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: favourite ? LuminColors.warn : LuminColors.textMuted,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// LONG / SHORT for a live signal the caller can see; LIVE + lock for one
/// the engine is masking from them (symbol only — no side).
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.text, this.long = true, this.locked = false});
  final String text;
  final bool long;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final color = locked ? LuminColors.accent : (long ? LuminColors.success : LuminColors.loss);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (locked) ...[
          Icon(Icons.lock_rounded, size: 11, color: color),
          const SizedBox(width: 3),
        ],
        Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.segment});
  final MarketSegment? segment;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (segment) {
      null => (Icons.search_off_rounded, 'No pairs match', 'Try the coin name, like SOL or PEPE.'),
      MarketSegment.favourites => (
          Icons.star_outline_rounded,
          'No favourites yet',
          'Tap the ☆ on any pair to keep it here.'
        ),
      MarketSegment.live => (
          Icons.bolt_rounded,
          'No live signals right now',
          'Pairs with a live Lumin signal show up here.'
        ),
      _ => (Icons.show_chart_rounded, 'Nothing here right now', 'Pull down to refresh.'),
    };
    return Padding(
      padding: const EdgeInsets.all(LuminSpacing.xxl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: LuminColors.textMuted, size: 40),
        const SizedBox(height: LuminSpacing.md),
        Text(title, style: const TextStyle(color: LuminColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        Text(body, textAlign: TextAlign.center, style: const TextStyle(color: LuminColors.textMuted)),
      ]),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load markets.', style: TextStyle(color: LuminColors.textMuted)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Skeleton in the shape of the board: the strip, the tabs, then rows.
class _MarketsSkeleton extends StatelessWidget {
  const _MarketsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
        children: [
          const SizedBox(height: 60),
          Row(children: [
            _box(width: 150, height: 80),
            const SizedBox(width: 8),
            _box(width: 150, height: 80),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < 4; i++) ...[_box(width: 72, height: 32), const SizedBox(width: 8)]
          ]),
          const SizedBox(height: 20),
          for (var i = 0; i < 9; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                _box(width: 36, height: 36, round: true),
                const SizedBox(width: 12),
                _box(width: 90, height: 16),
                const Spacer(),
                _box(width: 60, height: 24),
                const SizedBox(width: 12),
                _box(width: 70, height: 30),
              ]),
            ),
        ],
      ),
    );
  }

  static Widget _box({required double width, required double height, bool round = false}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(round ? height : LuminRadii.sm),
        border: Border.all(color: LuminColors.cardBorder),
      ),
    );
  }
}

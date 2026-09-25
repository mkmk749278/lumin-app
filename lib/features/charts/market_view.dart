/// Markets list — the pure half (2026-09-25 Charts redesign, part 1).
///
/// Owner: the Charts tab "looks outdated". The list was one flat text column
/// sorted by volume. It now has segments (Favourites / Lumin live / Hot /
/// Gainers / Losers), a market-breadth strip, coin icons and 24h sparklines.
/// Everything that decides WHAT is shown lives here, widget-free, so it is
/// unit-tested without a device; `charts_page.dart` only draws it.
library;

import 'models/candle.dart';

/// The list's tabs. Order is the on-screen order.
enum MarketSegment { favourites, live, hot, gainers, losers }

extension MarketSegmentLabel on MarketSegment {
  String get label => switch (this) {
        MarketSegment.favourites => 'Favourites',
        MarketSegment.live => 'Lumin live',
        MarketSegment.hot => 'Hot',
        MarketSegment.gainers => 'Gainers',
        MarketSegment.losers => 'Losers',
      };
}

/// Pairs thinner than this are left out of Gainers / Losers: a +80% move on
/// $40k of volume is a thin book printing a wick, not a market worth
/// ranking first. Hot is already volume-sorted and search shows everything.
const double kMoversMinQuoteVolume = 5e6;

/// `BTCUSDT` → `BTC`; `1000PEPEUSDT` → `PEPE` (Binance scales tiny coins by a
/// numeric prefix — the coin is still PEPE, and that is the icon to show).
String baseAsset(String symbol) {
  var b = symbol.endsWith('USDT') ? symbol.substring(0, symbol.length - 4) : symbol;
  final m = RegExp(r'^(\d+)([A-Z].*)$').firstMatch(b);
  if (m != null) b = m.group(2)!;
  return b;
}

/// The multiplier Binance put in front of the base (`1000PEPEUSDT` → `1000`),
/// or null. Shown beside the name so "PEPE" never reads as a price of one
/// PEPE when the contract is 1000 of them.
String? contractMultiplier(String symbol) {
  final b = symbol.endsWith('USDT') ? symbol.substring(0, symbol.length - 4) : symbol;
  final m = RegExp(r'^(\d+)[A-Z]').firstMatch(b);
  return m?.group(1);
}

/// Rows for one segment, before search. Live-signal pairs float to the top
/// of every segment except Gainers / Losers, whose whole point is the order.
List<MarketTicker> segmentRows(
  List<MarketTicker> all,
  MarketSegment seg, {
  required Set<String> favourites,
  required Set<String> liveSymbols,
}) {
  switch (seg) {
    case MarketSegment.favourites:
      return orderPairRows([for (final r in all) if (favourites.contains(r.symbol)) r], liveSymbols);
    case MarketSegment.live:
      return [for (final r in all) if (liveSymbols.contains(r.symbol)) r];
    case MarketSegment.hot:
      return orderPairRows(all, liveSymbols);
    case MarketSegment.gainers:
      final g = [for (final r in all) if (r.quoteVolume >= kMoversMinQuoteVolume && r.changePct > 0) r]
        ..sort((a, b) => b.changePct.compareTo(a.changePct));
      return g;
    case MarketSegment.losers:
      final l = [for (final r in all) if (r.quoteVolume >= kMoversMinQuoteVolume && r.changePct < 0) r]
        ..sort((a, b) => a.changePct.compareTo(b.changePct));
      return l;
  }
}

/// Search across the WHOLE board, whatever segment is selected: a user who
/// types "SOL" on the Losers tab is looking for SOL, not for SOL-if-it-fell.
List<MarketTicker> searchRows(List<MarketTicker> all, String query) {
  final q = query.trim().toUpperCase();
  if (q.isEmpty) return all;
  final starts = <MarketTicker>[];
  final contains = <MarketTicker>[];
  for (final r in all) {
    final base = baseAsset(r.symbol);
    if (base.startsWith(q) || r.symbol.startsWith(q)) {
      starts.add(r);
    } else if (r.symbol.contains(q)) {
      contains.add(r);
    }
  }
  return [...starts, ...contains];
}

/// Float pairs with a live signal to the top, preserving the volume order
/// within each partition. Pure — unit-tested in pair_ordering_test.dart.
List<MarketTicker> orderPairRows(
  List<MarketTicker> rows,
  Set<String> liveSignalSymbols,
) {
  if (liveSignalSymbols.isEmpty) return rows;
  final live = <MarketTicker>[];
  final rest = <MarketTicker>[];
  for (final r in rows) {
    (liveSignalSymbols.contains(r.symbol) ? live : rest).add(r);
  }
  return [...live, ...rest];
}

/// How the whole board moved over 24h — the strip above the list.
class MarketBreadth {
  const MarketBreadth({required this.up, required this.down, required this.flat});
  final int up;
  final int down;
  final int flat;
  int get total => up + down + flat;

  /// Share of pairs up, 0..1 (0.5 when there is nothing to count).
  double get upShare => total == 0 ? 0.5 : up / total;

  /// A word for the board, never a forecast: it says what already happened.
  String get mood {
    if (total == 0) return '—';
    final s = upShare;
    if (s >= 0.65) return 'Mostly up';
    if (s <= 0.35) return 'Mostly down';
    return 'Mixed';
  }
}

/// Breadth over pairs with real volume (the same floor as the movers tabs),
/// so a hundred dead listings do not decide the board's mood.
MarketBreadth marketBreadth(List<MarketTicker> all) {
  var up = 0, down = 0, flat = 0;
  for (final r in all) {
    if (r.quoteVolume < kMoversMinQuoteVolume) continue;
    if (r.changePct > 0.05) {
      up++;
    } else if (r.changePct < -0.05) {
      down++;
    } else {
      flat++;
    }
  }
  return MarketBreadth(up: up, down: down, flat: flat);
}

/// `64,328.8` / `3.412` / `0.000767` — enough digits to see a move on any
/// magnitude, never a float's 17.
String formatMarketPrice(double p) {
  if (p <= 0 || !p.isFinite) return '—';
  final String s;
  if (p >= 1000) {
    s = p.toStringAsFixed(1);
  } else if (p >= 1) {
    s = p.toStringAsFixed(3);
  } else if (p >= 0.01) {
    s = p.toStringAsFixed(4);
  } else {
    s = p.toStringAsFixed(6);
  }
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

/// `$1.68B` / `$445.1M` / `$92K`.
String formatQuoteVolume(double v) {
  if (v >= 1e9) return '\$${(v / 1e9).toStringAsFixed(2)}B';
  if (v >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return '\$${(v / 1e3).toStringAsFixed(0)}K';
  return '\$${v.toStringAsFixed(0)}';
}

/// `+4.44%` / `-1.14%` / `0.00%` — a move that rounds to nothing is shown
/// as nothing, never as a red `-0.00%`.
String formatChangePct(double pct) {
  if (changeDirection(pct) == 0) return '0.00%';
  return '${pct > 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
}

/// 1 up, -1 down, 0 for a move that rounds to 0.00% — the colour of a row.
int changeDirection(double pct) {
  if (pct.abs() < 0.005 || !pct.isFinite) return 0;
  return pct > 0 ? 1 : -1;
}

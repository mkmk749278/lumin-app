/// Charts tab — the full Binance USDT-M futures pair list. Tap a pair to open
/// its live chart ([ChartPage]; with our signal overlay when that pair has a
/// live Lumin signal). Replaces the old Agents tab (Agents demoted to a Menu
/// row). Market data is the public 24h ticker intersected with the tradable
/// perpetual universe — app→Binance direct, no engine load. Live-signal pairs
/// are badged and floated to the top (design §10), read from the same
/// SWR-cached signals stream the Signals tab uses.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/foreground_refresh.dart';
import '../../data/app_config.dart';
import '../../data/binance_market_data.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import 'chart_page.dart';
import 'models/candle.dart';

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

class ChartsPage extends StatefulWidget {
  const ChartsPage({super.key});

  @override
  State<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<ChartsPage>
    implements ForegroundRefreshable {
  final BinanceMarketData _md = BinanceMarketData();
  late Future<List<MarketTicker>> _future;
  String _query = '';

  LuminRepository? _repo;
  StreamSubscription<List<MockSignal>>? _sigSub;

  /// Latest open Lumin signal per symbol — badge + overlay source.
  Map<String, MockSignal> _liveBySymbol = const {};

  @override
  void initState() {
    super.initState();
    _future = _load();
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
    _sigSub?.cancel();
    _md.close();
    super.dispose();
  }

  @override
  void refreshFromForeground() {
    if (!mounted) return;
    setState(() => _future = _load());
    _subscribeSignals();
  }

  /// Watch the open-signals list (SWR-cached — dedups with the Signals tab's
  /// own subscription). Failures leave the badge layer empty; the market list
  /// itself never depends on our engine.
  void _subscribeSignals() {
    final repo = _repo;
    if (repo == null) return;
    _sigSub?.cancel();
    _sigSub = repo.watchSignals(status: 'open', limit: 100).listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _liveBySymbol = {for (final s in items) s.symbol: s};
        });
      },
      onError: (_) {/* engine unreachable — badges just stay off */},
    );
  }

  /// Tradable USDT-M perps with their 24h context, most-liquid first.
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

  List<MarketTicker> _filter(List<MarketTicker> rows) {
    if (_query.isEmpty) return rows;
    final q = _query.toUpperCase();
    return [for (final r in rows) if (r.symbol.contains(q)) r];
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
    return Scaffold(
      appBar: AppBar(title: const Text('Charts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search pairs (e.g. BTC, SOL)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MarketTicker>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _Error(onRetry: refreshFromForeground);
                }
                final rows = orderPairRows(
                  _filter(snap.data ?? const []),
                  _liveBySymbol.keys.toSet(),
                );
                if (rows.isEmpty) {
                  return const Center(child: Text('No pairs match.'));
                }
                return RefreshIndicator(
                  onRefresh: () {
                    setState(() => _future = _load());
                    _subscribeSignals();
                    return _future;
                  },
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0x22FFFFFF)),
                    itemBuilder: (_, i) => _PairRow(
                      t: rows[i],
                      signal: _liveBySymbol[rows[i].symbol],
                      onTap: _open,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  const _PairRow({required this.t, required this.onTap, this.signal});
  final MarketTicker t;
  final MockSignal? signal;
  final void Function(String symbol) onTap;

  @override
  Widget build(BuildContext context) {
    final up = t.changePct >= 0;
    final pct = '${up ? '+' : ''}${t.changePct.toStringAsFixed(2)}%';
    final sig = signal;
    return ListTile(
      dense: true,
      onTap: () => onTap(t.symbol),
      title: Row(
        children: [
          Text(
            t.symbol,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (sig != null) ...[
            const SizedBox(width: 8),
            _SignalBadge(direction: sig.direction),
          ],
        ],
      ),
      subtitle: Text(
        _vol(t.quoteVolume),
        style: const TextStyle(color: LuminColors.textMuted, fontSize: 11),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _price(t.lastPrice),
            style: const TextStyle(color: LuminColors.textPrimary),
          ),
          Text(
            pct,
            style: TextStyle(
              color: up ? LuminColors.success : LuminColors.loss,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static String _price(double p) {
    if (p >= 1000) return p.toStringAsFixed(1);
    if (p >= 1) return p.toStringAsFixed(3);
    return p.toStringAsFixed(6);
  }

  static String _vol(double v) {
    if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(2)}B vol';
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M vol';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K vol';
    return '${v.toStringAsFixed(0)} vol';
  }
}

/// Small pill marking a pair with a live Lumin signal — tapping the row opens
/// the chart with that signal's levels overlaid.
class _SignalBadge extends StatelessWidget {
  const _SignalBadge({required this.direction});
  final String direction;

  @override
  Widget build(BuildContext context) {
    final long = direction.toUpperCase() == 'LONG';
    final color = long ? LuminColors.success : LuminColors.loss;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        direction.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
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
          const Text('Could not load pairs.',
              style: TextStyle(color: LuminColors.textMuted)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Charts tab — the full Binance USDT-M futures pair list. Tap a pair to open
/// its live chart ([ChartPage], no overlay). Replaces the old Agents tab
/// (Agents demoted to a Menu row). Data is the public 24h ticker intersected
/// with the tradable perpetual universe — app→Binance direct, no engine load.
library;

import 'package:flutter/material.dart';

import '../../app/foreground_refresh.dart';
import '../../data/binance_market_data.dart';
import '../../shared/tokens.dart';
import 'chart_page.dart';
import 'models/candle.dart';

class ChartsPage extends StatefulWidget {
  const ChartsPage({super.key});

  @override
  State<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<ChartsPage> implements ForegroundRefreshable {
  final BinanceMarketData _md = BinanceMarketData();
  late Future<List<MarketTicker>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _md.close();
    super.dispose();
  }

  @override
  void refreshFromForeground() {
    if (!mounted) return;
    setState(() => _future = _load());
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
      MaterialPageRoute(builder: (_) => ChartPage(symbol: symbol)),
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
                final rows = _filter(snap.data ?? const []);
                if (rows.isEmpty) {
                  return const Center(child: Text('No pairs match.'));
                }
                return RefreshIndicator(
                  onRefresh: () {
                    setState(() => _future = _load());
                    return _future;
                  },
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Color(0x22FFFFFF)),
                    itemBuilder: (_, i) => _PairRow(t: rows[i], onTap: _open),
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
  const _PairRow({required this.t, required this.onTap});
  final MarketTicker t;
  final void Function(String symbol) onTap;

  @override
  Widget build(BuildContext context) {
    final up = t.changePct >= 0;
    final pct = '${up ? '+' : ''}${t.changePct.toStringAsFixed(2)}%';
    return ListTile(
      dense: true,
      onTap: () => onTap(t.symbol),
      title: Text(
        t.symbol,
        style: const TextStyle(
          color: LuminColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
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

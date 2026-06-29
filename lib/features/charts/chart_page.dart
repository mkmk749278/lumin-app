/// Market chart screen — candles for one symbol with optional Lumin overlay.
///
/// Reached from (1) the Charts tab pair list (no overlay) and (2) a signal
/// detail sheet's "Open chart" (overlay = that signal's entry/SL/TP/BE).
/// History from Binance public klines; the live last bar is kept current by a
/// short REST poll of the latest klines (reliable — reuses the same proven
/// `klines()` path that loads history, so it can't silently freeze the way a
/// background WebSocket can). All app→Binance direct. Rendered by the vendored
/// Lightweight Charts WebView.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/binance_market_data.dart';
import '../../data/mock_data.dart';
import 'chart_webview.dart';
import 'models/chart_overlay.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({super.key, required this.symbol, this.signal});

  final String symbol;

  /// When opened from a signal, draw its entry/SL/TP/BE overlay.
  final MockSignal? signal;

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  final BinanceMarketData _md = BinanceMarketData();
  ChartBridge? _bridge;
  Timer? _poll;
  bool _ticking = false; // guards against overlapping poll fetches

  String _tf = '15m';
  bool _loading = true;
  String? _error;

  /// How often the live last bar is refreshed from REST while the chart is open.
  static const Duration _pollInterval = Duration(seconds: 2);

  static const List<String> _tfs = ['1m', '5m', '15m', '1h', '4h'];

  @override
  void dispose() {
    _poll?.cancel();
    _md.close();
    super.dispose();
  }

  Future<void> _onReady(ChartBridge bridge) async {
    _bridge = bridge;
    await _loadAndStream();
  }

  Future<void> _loadAndStream() async {
    final bridge = _bridge;
    if (bridge == null) return;
    if (mounted) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final candles = await _md.klines(
        symbol: widget.symbol,
        interval: BinanceMarketData.intervals[_tf] ?? '15m',
        limit: 500,
      );
      await bridge.setCandles(_tf, candles);
      final sig = widget.signal;
      if (sig != null) {
        await bridge.setOverlay(ChartOverlay.fromSignal(sig));
      }
      _startPoll();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load chart: $e';
        });
      }
    }
  }

  /// Keep the latest bar(s) live with a short REST poll. We re-fetch the last
  /// two klines so both the in-progress bar and the just-closed bar finalise.
  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    final bridge = _bridge;
    if (bridge == null || _ticking) return;
    _ticking = true;
    try {
      final latest = await _md.klines(
        symbol: widget.symbol,
        interval: BinanceMarketData.intervals[_tf] ?? '15m',
        limit: 2,
      );
      for (final c in latest) {
        await bridge.updateCandle(c);
      }
    } catch (_) {
      /* transient — next tick retries; history already on screen */
    } finally {
      _ticking = false;
    }
  }

  void _onTf(String tf) {
    if (tf == _tf) return;
    setState(() => _tf = tf);
    _loadAndStream();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.symbol)),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final tf in _tfs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tf),
                      selected: tf == _tf,
                      onSelected: (_) => _onTf(tf),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ChartWebView(onReady: _onReady, onError: _onWebError),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onWebError(String message) {
    if (mounted) setState(() => _error = 'Chart error: $message');
  }
}

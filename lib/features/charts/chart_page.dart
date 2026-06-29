/// Market chart screen — candles for one symbol with optional Lumin overlay.
///
/// Reached from (1) the Charts tab pair list (no overlay) and (2) a signal
/// detail sheet's "Open chart" (overlay = that signal's entry/SL/TP/BE).
/// History from Binance public klines, live last bar from the kline WS, both
/// app→Binance direct. Rendered by the vendored Lightweight Charts WebView.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/binance_kline_socket.dart';
import '../../data/binance_market_data.dart';
import '../../data/mock_data.dart';
import 'chart_webview.dart';
import 'models/candle.dart';
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
  BinanceKlineSocket? _socket;
  StreamSubscription<Candle>? _sub;

  String _tf = '15m';
  bool _loading = true;
  String? _error;

  static const List<String> _tfs = ['1m', '5m', '15m', '1h', '4h'];

  @override
  void dispose() {
    _sub?.cancel();
    _socket?.dispose();
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
      _openSocket();
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

  void _openSocket() {
    _sub?.cancel();
    _socket?.dispose();
    _socket = BinanceKlineSocket(
      symbol: widget.symbol,
      interval: BinanceMarketData.intervals[_tf] ?? '15m',
    );
    _sub = _socket!.stream().listen(
      (c) => _bridge?.updateCandle(c),
      onError: (_) {/* socket self-reconnects; REST history still shown */},
    );
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

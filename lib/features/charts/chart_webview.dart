/// WebView host for the vendored TradingView Lightweight Charts asset, plus the
/// Dart side of the bridge (docs/market_charts_tab.md §8).
///
/// [ChartWebView] loads `assets/chart/index.html`, listens on the `LuminChart`
/// JS channel for `ready`/`error`, and hands the parent a [ChartBridge] once the
/// chart has initialised. The parent ([ChartController]) pushes candles / live
/// updates / our overlay through the bridge.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models/candle.dart';
import 'models/chart_overlay.dart';

/// Dart→JS commands. Each call serialises the payload to a JSON string and
/// passes it as a single string argument the JS side `JSON.parse`s.
class ChartBridge {
  ChartBridge(this._controller);
  final WebViewController _controller;

  Future<void> setCandles(String tf, List<Candle> candles) {
    return _call('setCandles', {
      'tf': tf,
      'candles': [for (final c in candles) c.toChartJson()],
      'volumes': [for (final c in candles) c.toVolumeJson()],
    });
  }

  Future<void> updateCandle(Candle c) {
    return _call('updateCandle', {
      'candle': c.toChartJson(),
      'volume': c.toVolumeJson(),
    });
  }

  Future<void> setOverlay(ChartOverlay o) => _call('setOverlay', o.toJson());

  Future<void> clearOverlay() => _controller.runJavaScript('window.lumin.clearOverlay();');

  Future<void> setTheme({required bool dark}) => _call('setTheme', {'dark': dark});

  Future<void> _call(String fn, Object payload) {
    // jsonEncode(payload) → JSON string; jsonEncode(that) → a safe JS string
    // literal. JS does `JSON.parse(arg)` back into the object.
    final arg = jsonEncode(jsonEncode(payload));
    return _controller.runJavaScript('window.lumin.$fn($arg);');
  }
}

class ChartWebView extends StatefulWidget {
  const ChartWebView({
    super.key,
    required this.onReady,
    this.onError,
    this.dark = true,
  });

  /// Called once the chart JS has initialised (`ready` event).
  final void Function(ChartBridge bridge) onReady;
  final void Function(String message)? onError;
  final bool dark;

  @override
  State<ChartWebView> createState() => _ChartWebViewState();
}

class _ChartWebViewState extends State<ChartWebView> {
  late final WebViewController _controller;
  late final ChartBridge _bridge;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0E1116))
      ..addJavaScriptChannel('LuminChart', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (e) => widget.onError?.call(e.description),
        ),
      )
      ..loadFlutterAsset('assets/chart/index.html');
    _bridge = ChartBridge(_controller);
  }

  void _onMessage(JavaScriptMessage msg) {
    try {
      final j = jsonDecode(msg.message);
      if (j is! Map<String, dynamic>) return;
      switch (j['event']) {
        case 'ready':
          widget.onReady(_bridge);
          break;
        case 'error':
          widget.onError?.call((j['message'] ?? 'chart error').toString());
          break;
      }
    } catch (_) {/* ignore malformed bridge message */}
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

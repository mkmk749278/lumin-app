/// WebView host for the vendored TradingView Lightweight Charts asset —
/// the Android/iOS side of the bridge (docs/market_charts_tab.md §8).
///
/// [ChartWebView] loads `assets/chart/index.html`, listens on the `LuminChart`
/// JS channel for `ready`/`error`/`visibleRangeChanged`, and hands the parent
/// a [ChartBridge] once the chart has initialised. The parent ([ChartPage])
/// pushes candles / live updates / indicators / our overlay through the bridge.
///
/// Selected via the conditional export in `chart_webview.dart`; the web app
/// gets the iframe host in `chart_webview_web.dart` instead
/// (`webview_flutter` has no web implementation).
library;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'chart_bridge.dart';

class _WebViewChartBridge extends ChartBridge {
  _WebViewChartBridge(this._controller);
  final WebViewController _controller;

  @override
  Future<void> invoke(String fn, String? jsonArg) {
    if (jsonArg == null) {
      return _controller.runJavaScript('window.lumin.$fn();');
    }
    // jsonEncode(jsonArg) → a safe JS string literal. JS does
    // `JSON.parse(arg)` back into the object.
    final arg = ChartBridge.encodeJsStringLiteral(jsonArg);
    return _controller.runJavaScript('window.lumin.$fn($arg);');
  }
}

class ChartWebView extends StatefulWidget {
  const ChartWebView({
    super.key,
    required this.onReady,
    this.onError,
    this.onVisibleRange,
    this.dark = true,
  });

  /// Called once the chart JS has initialised (`ready` event).
  final void Function(ChartBridge bridge) onReady;
  final void Function(String message)? onError;

  /// Visible time range changed (seconds since epoch) — used by the parent
  /// to lazy-load older history when the user scrolls near the left edge.
  final void Function(double from, double to)? onVisibleRange;
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
    _bridge = _WebViewChartBridge(_controller);
  }

  void _onMessage(JavaScriptMessage msg) {
    dispatchChartEvent(
      msg.message,
      onReady: () => widget.onReady(_bridge),
      onError: widget.onError,
      onVisibleRange: widget.onVisibleRange,
    );
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

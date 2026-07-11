/// WebView host for the vendored TradingView Lightweight Charts asset, plus the
/// Dart side of the bridge (docs/market_charts_tab.md §8).
///
/// [ChartWebView] loads `assets/chart/index.html`, listens on the `LuminChart`
/// JS channel for `ready`/`error`/`visibleRangeChanged`, and hands the parent
/// a [ChartBridge] once the chart has initialised. The parent ([ChartPage])
/// pushes candles / live updates / indicators / our overlay through the bridge.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models/alert_overlay.dart';
import 'models/candle.dart';
import 'models/chart_overlay.dart';

/// One overlay indicator line (EMA/SMA) ready for the JS bridge.
class IndicatorLine {
  const IndicatorLine({
    required this.id,
    required this.title,
    required this.color,
    required this.data,
  });

  final String id;
  final String title;
  final String color; // CSS color string
  final List<Map<String, dynamic>> data; // [{time, value}]

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'color': color, 'data': data};
}

/// Dart→JS commands. Each call serialises the payload to a JSON string and
/// passes it as a single string argument the JS side `JSON.parse`s.
class ChartBridge {
  ChartBridge(this._controller);
  final WebViewController _controller;

  /// Seed/replace the series. [precision]/[minMove] fix the price axis for
  /// sub-dollar alts (Lightweight Charts defaults to 2 decimals). Set
  /// [preserveView] on a history-prepend so the viewport doesn't jump.
  Future<void> setCandles(
    String tf,
    List<Candle> candles, {
    int? precision,
    double? minMove,
    bool preserveView = false,
  }) {
    return _call('setCandles', {
      'tf': tf,
      'candles': [for (final c in candles) c.toChartJson()],
      'volumes': [for (final c in candles) c.toVolumeJson()],
      if (precision != null) 'precision': precision,
      if (minMove != null) 'minMove': minMove,
      'preserveView': preserveView,
    });
  }

  Future<void> updateCandle(Candle c) {
    return _call('updateCandle', {
      'candle': c.toChartJson(),
      'volume': c.toVolumeJson(),
    });
  }

  /// Draw/replace the full indicator set. [rsiData] non-null shows the RSI
  /// band (which swaps with the volume histogram — [showVolume] false).
  Future<void> setIndicators({
    required List<IndicatorLine> lines,
    List<Map<String, dynamic>>? rsiData,
    required bool showVolume,
  }) {
    return _call('setIndicators', {
      'lines': [for (final l in lines) l.toJson()],
      'rsi': rsiData != null ? {'data': rsiData} : null,
      'showVolume': showVolume,
    });
  }

  /// Push just the newest point of each active indicator (live tick).
  Future<void> updateIndicators({
    required List<Map<String, dynamic>> points,
    Map<String, dynamic>? rsiPoint,
  }) {
    return _call('updateIndicators', {
      'points': points,
      'rsi': rsiPoint,
    });
  }

  Future<void> setOverlay(ChartOverlay o) => _call('setOverlay', o.toJson());

  /// Draw a market-alert setup (level lines / divergence segment / alert
  /// marker) — the alert-tap counterpart of the signal overlay.
  Future<void> setAlertOverlay(AlertChartOverlay o) =>
      _call('setAlertOverlay', o.toJson());

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
        case 'visibleRangeChanged':
          final from = j['from'];
          final to = j['to'];
          if (from is num && to is num) {
            widget.onVisibleRange?.call(from.toDouble(), to.toDouble());
          }
          break;
      }
    } catch (_) {/* ignore malformed bridge message */}
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

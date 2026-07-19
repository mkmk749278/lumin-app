/// Iframe host for the vendored TradingView Lightweight Charts asset — the
/// web-app side of the bridge (2026-07-18 PWA channel).
///
/// `webview_flutter` has no web implementation, so on web [ChartWebView]
/// mounts `assets/chart/index.html` in a same-origin `<iframe>` via
/// [HtmlElementView] and reproduces the bridge over `postMessage`:
///
///   * Dart→JS: `{luminCall: <fn>, arg: <jsonString>}` posted into the
///     iframe; a shim in the asset dispatches to `window.lumin.<fn>(arg)`.
///   * JS→Dart: the same shim emulates the `LuminChart` channel by posting
///     `{luminChart: <jsonString>}` to the parent window.
///
/// The parent ([ChartPage]) sees the identical [ChartBridge] interface and
/// `ready`/`error`/`visibleRangeChanged` events as the WebView host.
library;

import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'chart_bridge.dart';

const String _viewType = 'lumin-chart-iframe';
bool _factoryRegistered = false;

/// Frames created by the platform-view factory, keyed by viewId so
/// `onPlatformViewCreated` can claim the element it was handed.
final Map<int, web.HTMLIFrameElement> _framesByViewId = {};

void _ensureFactoryRegistered() {
  if (_factoryRegistered) return;
  _factoryRegistered = true;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
    // Flutter web serves the bundle's asset tree under `assets/<key>`, so
    // the asset key `assets/chart/index.html` resolves one level deeper.
    final frame = web.HTMLIFrameElement()
      ..src = 'assets/assets/chart/index.html';
    frame.style
      ..border = 'none'
      ..width = '100%'
      ..height = '100%'
      ..backgroundColor = '#0E1116';
    _framesByViewId[viewId] = frame;
    return frame;
  });
}

class _IframeChartBridge extends ChartBridge {
  _IframeChartBridge(this._frame);
  final web.HTMLIFrameElement _frame;

  @override
  Future<void> invoke(String fn, String? jsonArg) async {
    final message = <String, Object?>{
      'luminCall': fn,
      if (jsonArg != null) 'arg': jsonArg,
    };
    // Same-origin frame; '*' is safe because the payload is chart data the
    // document itself rendered from public market feeds.
    _frame.contentWindow?.postMessage(message.jsify(), '*'.toJS);
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
  web.HTMLIFrameElement? _frame;
  _IframeChartBridge? _bridge;
  JSFunction? _listener;

  @override
  void initState() {
    super.initState();
    _ensureFactoryRegistered();
    // Attach the window listener before the iframe exists so the asset's
    // `ready` post can never race past us.
    _listener = _onWindowMessage.toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    if (_listener != null) {
      web.window.removeEventListener('message', _listener);
    }
    super.dispose();
  }

  void _onWindowMessage(web.MessageEvent event) {
    final frame = _frame;
    // Only accept messages from our own frame's window (dart2js compiles
    // `==` on JS objects to reference equality).
    if (frame == null || event.source != frame.contentWindow) return;
    final data = event.data.dartify();
    if (data is! Map) return;
    final raw = data['luminChart'];
    if (raw is! String) return;
    dispatchChartEvent(
      raw,
      onReady: () {
        final bridge = _bridge;
        if (bridge != null) widget.onReady(bridge);
      },
      onError: widget.onError,
      onVisibleRange: widget.onVisibleRange,
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final frame = _framesByViewId.remove(viewId);
    if (frame == null) return;
    _frame = frame;
    _bridge = _IframeChartBridge(frame);
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(
        viewType: _viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
      );
}

/// Chart host façade — the import [ChartPage] uses.
///
/// The bridge contract ([ChartBridge], [IndicatorLine], the event dispatch)
/// is platform-neutral and lives in `chart_bridge.dart`. The *host widget*
/// differs per platform and is selected at compile time:
///
///   * Android/iOS — `chart_webview_mobile.dart` (`webview_flutter`).
///   * Web (PWA, 2026-07-18) — `chart_webview_web.dart` (same-origin iframe
///     + postMessage; `webview_flutter` has no web implementation).
///
/// Both export an identical `ChartWebView` widget, so consumers never
/// branch on platform.
library;

export 'chart_bridge.dart';
export 'chart_webview_mobile.dart'
    if (dart.library.js_interop) 'chart_webview_web.dart';

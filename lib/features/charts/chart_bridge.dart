/// Platform-neutral half of the chart bridge (docs/market_charts_tab.md §8).
///
/// [ChartBridge] owns the *payload shapes* of every Dart→JS command so the
/// two hosts — the Android WebView ([chart_webview_mobile.dart]) and the web
/// app's iframe ([chart_webview_web.dart], 2026-07-18 PWA channel) — differ
/// only in how a `(fn, jsonString)` pair physically reaches `window.lumin`.
/// [ChartPage] talks to this interface and never learns which host it got.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models/alert_overlay.dart';
import 'models/candle.dart';
import 'models/chart_overlay.dart';

/// How an [IndicatorLine] is drawn.
///
/// [dots] exists for Parabolic SAR: the SAR jumps from one side of price to
/// the other on a reversal, so a connected line would draw a long diagonal
/// through the candles that no bar's SAR level ever occupied. Points-only is
/// how SAR is conventionally rendered, and here it is also the only rendering
/// that isn't drawing prices that never existed.
enum IndicatorStyle {
  line,
  dots;

  String get wire => name;
}

/// One overlay indicator line (EMA/SMA/SAR) ready for the JS bridge.
class IndicatorLine {
  const IndicatorLine({
    required this.id,
    required this.title,
    required this.color,
    required this.data,
    this.style = IndicatorStyle.line,
  });

  final String id;
  final String title;
  final String color; // CSS color string
  final List<Map<String, dynamic>> data; // [{time, value}]
  final IndicatorStyle style;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'color': color,
        'data': data,
        'style': style.wire,
      };
}

/// Dart→JS commands. Each call serialises the payload to a JSON string the
/// JS side `JSON.parse`s; the transport is host-specific ([invoke]).
abstract class ChartBridge {
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

  Future<void> clearOverlay() => invoke('clearOverlay', null);

  Future<void> setTheme({required bool dark}) => _call('setTheme', {'dark': dark});

  Future<void> _call(String fn, Object payload) =>
      invoke(fn, jsonEncode(payload));

  /// Host transport: deliver `window.lumin.<fn>(<jsonArg>)` to the chart
  /// document. [jsonArg] is null for zero-argument commands.
  @protected
  Future<void> invoke(String fn, String? jsonArg);

  /// Encode an arbitrary string as a JS string literal — used by hosts that
  /// inject the argument into evaluated source (the WebView host) rather
  /// than passing it structurally (the iframe host's postMessage).
  static String encodeJsStringLiteral(String s) => jsonEncode(s);
}

/// Shared JS→Dart event dispatch — both hosts receive the same
/// `{event, ...}` JSON strings on the `LuminChart` channel and route them
/// through here so the switch lives in one place.
void dispatchChartEvent(
  String message, {
  required void Function() onReady,
  required void Function(String message)? onError,
  required void Function(double from, double to)? onVisibleRange,
}) {
  try {
    final j = jsonDecode(message);
    if (j is! Map<String, dynamic>) return;
    switch (j['event']) {
      case 'ready':
        onReady();
        break;
      case 'error':
        onError?.call((j['message'] ?? 'chart error').toString());
        break;
      case 'visibleRangeChanged':
        final from = j['from'];
        final to = j['to'];
        if (from is num && to is num) {
          onVisibleRange?.call(from.toDouble(), to.toDouble());
        }
        break;
    }
  } catch (_) {/* ignore malformed bridge message */}
}

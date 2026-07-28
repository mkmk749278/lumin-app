/// Chart bridge contract (split out for the web/PWA channel, 2026-07-18).
///
/// `ChartBridge` now owns every Dart→JS payload shape while the two hosts
/// (Android WebView, web iframe) only implement `invoke(fn, jsonArg)`.
/// These tests pin the wire contract the vendored chart asset's
/// `window.lumin.*` functions JSON.parse — a drift here breaks BOTH hosts,
/// so it must fail loudly in CI — plus the JS→Dart event dispatch both
/// hosts route through `dispatchChartEvent`.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/charts/chart_bridge.dart';
import 'package:lumin/features/charts/models/candle.dart';

/// Recording host: captures (fn, jsonArg) pairs instead of a WebView/iframe.
class _RecordingBridge extends ChartBridge {
  final List<(String, String?)> calls = [];

  @override
  Future<void> invoke(String fn, String? jsonArg) async {
    calls.add((fn, jsonArg));
  }
}

Candle _candle() => Candle(
      time: 1700000000,
      open: 1.0,
      high: 2.0,
      low: 0.5,
      close: 1.5,
      volume: 42.0,
    );

void main() {
  group('ChartBridge payload shapes', () {
    test('setCandles sends tf, candles, volumes and optional precision',
        () async {
      final b = _RecordingBridge();
      await b.setCandles('5m', [_candle()], precision: 4, minMove: 0.0001);
      final (fn, arg) = b.calls.single;
      expect(fn, 'setCandles');
      final j = jsonDecode(arg!) as Map<String, dynamic>;
      expect(j['tf'], '5m');
      expect(j['candles'], hasLength(1));
      expect(j['volumes'], hasLength(1));
      expect(j['precision'], 4);
      expect(j['minMove'], 0.0001);
      expect(j['preserveView'], isFalse);
    });

    test('setCandles omits precision/minMove when unset', () async {
      final b = _RecordingBridge();
      await b.setCandles('1m', [_candle()], preserveView: true);
      final j = jsonDecode(b.calls.single.$2!) as Map<String, dynamic>;
      expect(j.containsKey('precision'), isFalse);
      expect(j.containsKey('minMove'), isFalse);
      expect(j['preserveView'], isTrue);
    });

    test('updateCandle wraps candle + volume', () async {
      final b = _RecordingBridge();
      await b.updateCandle(_candle());
      final (fn, arg) = b.calls.single;
      expect(fn, 'updateCandle');
      final j = jsonDecode(arg!) as Map<String, dynamic>;
      expect(j.keys, containsAll(['candle', 'volume']));
    });

    test('setIndicators serialises lines and the rsi/volume swap', () async {
      final b = _RecordingBridge();
      await b.setIndicators(
        lines: const [
          IndicatorLine(
            id: 'ema20',
            title: 'EMA 20',
            color: '#7BD3F7',
            data: [
              {'time': 1, 'value': 2.0},
            ],
          ),
        ],
        rsiData: const [
          {'time': 1, 'value': 55.0},
        ],
        showVolume: false,
      );
      final j = jsonDecode(b.calls.single.$2!) as Map<String, dynamic>;
      expect(j['lines'], hasLength(1));
      expect((j['lines'] as List).single['id'], 'ema20');
      expect(j['rsi'], {'data': [{'time': 1, 'value': 55.0}]});
      expect(j['showVolume'], isFalse);
      // Unstyled lines still declare a style, so the JS never has to guess.
      expect((j['lines'] as List).single['style'], 'line');
    });

    test('setIndicators carries the dots style for SAR', () async {
      // SAR jumps sides on a reversal — the renderer must be told to draw
      // points with no connecting line, or it spans the flip with a diagonal
      // through prices no bar's SAR level ever held.
      final b = _RecordingBridge();
      await b.setIndicators(
        lines: const [
          IndicatorLine(
            id: 'sar',
            title: 'SAR',
            color: '#9aa4b2',
            style: IndicatorStyle.dots,
            data: [
              {'time': 1, 'value': 0.9},
            ],
          ),
        ],
        showVolume: true,
      );
      final j = jsonDecode(b.calls.single.$2!) as Map<String, dynamic>;
      expect((j['lines'] as List).single['style'], 'dots');
    });

    test('clearOverlay is a zero-argument invoke', () async {
      final b = _RecordingBridge();
      await b.clearOverlay();
      expect(b.calls.single, ('clearOverlay', null));
    });

    test('setTheme sends the dark flag', () async {
      final b = _RecordingBridge();
      await b.setTheme(dark: false);
      expect(b.calls.single.$1, 'setTheme');
      expect(jsonDecode(b.calls.single.$2!), {'dark': false});
    });

    test('encodeJsStringLiteral produces a JS-safe literal', () {
      expect(
        ChartBridge.encodeJsStringLiteral('{"a":"x\ny"}'),
        '"{\\"a\\":\\"x\\ny\\"}"',
      );
    });
  });

  group('dispatchChartEvent', () {
    test('ready routes to onReady', () {
      var ready = false;
      dispatchChartEvent(
        '{"event":"ready"}',
        onReady: () => ready = true,
        onError: (_) => fail('unexpected error'),
        onVisibleRange: (_, __) => fail('unexpected range'),
      );
      expect(ready, isTrue);
    });

    test('error routes the message, defaulting when absent', () {
      final errors = <String>[];
      dispatchChartEvent(
        '{"event":"error","message":"boom"}',
        onReady: () {},
        onError: errors.add,
        onVisibleRange: null,
      );
      dispatchChartEvent(
        '{"event":"error"}',
        onReady: () {},
        onError: errors.add,
        onVisibleRange: null,
      );
      expect(errors, ['boom', 'chart error']);
    });

    test('visibleRangeChanged passes numeric from/to only', () {
      final ranges = <(double, double)>[];
      dispatchChartEvent(
        '{"event":"visibleRangeChanged","from":100,"to":200.5}',
        onReady: () {},
        onError: null,
        onVisibleRange: (f, t) => ranges.add((f, t)),
      );
      dispatchChartEvent(
        '{"event":"visibleRangeChanged","from":"nan","to":200}',
        onReady: () {},
        onError: null,
        onVisibleRange: (f, t) => ranges.add((f, t)),
      );
      expect(ranges, [(100.0, 200.5)]);
    });

    test('malformed JSON and non-map payloads are ignored', () {
      dispatchChartEvent(
        'not json{',
        onReady: () => fail('must not fire'),
        onError: (_) => fail('must not fire'),
        onVisibleRange: null,
      );
      dispatchChartEvent(
        '[1,2,3]',
        onReady: () => fail('must not fire'),
        onError: (_) => fail('must not fire'),
        onVisibleRange: null,
      );
    });
  });
}

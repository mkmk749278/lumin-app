/// AlertThumbnail — the 100eyes card mini chart.
///
/// Pins: (1) ThumbData maps alert metrics to paint space correctly
/// (fired-candle resolution, zone start clamp, divergence pivots,
/// graceful nulls); (2) the widget goes shimmer → CustomPaint → and a
/// memo hit never refetches; (3) the painter renders every setup
/// variant without throwing.
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumin/data/binance_market_data.dart';
import 'package:lumin/data/klines_thumbnail_service.dart';
import 'package:lumin/data/market_alert.dart';
import 'package:lumin/features/charts/models/alert_overlay.dart';
import 'package:lumin/features/charts/models/candle.dart';
import 'package:lumin/features/pulse/alert_thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tfSec = 3600;

/// 96 hourly candles whose LAST bar opens exactly on the alert's fired
/// bar time, so fired-index resolution is exact.
List<Candle> _candles(MarketAlert alert, {int n = 96}) {
  final lastOpen = AlertChartOverlay.alertBarTime(alert);
  return [
    for (var i = 0; i < n; i++)
      Candle(
        time: lastOpen - (n - 1 - i) * _tfSec,
        open: 100 + i * 0.1,
        high: 101 + i * 0.1,
        low: 99 + i * 0.1,
        close: 100.5 + i * 0.1,
        volume: 1000,
      ),
  ];
}

MarketAlert _alert({
  String type = 'NEAR_SUPPORT',
  String bias = 'BULLISH',
  Map<String, dynamic> metrics = const {},
  String id = 'a1',
}) {
  return MarketAlert(
    alertId: id,
    alertType: type,
    symbol: 'RAVEUSDT',
    timeframe: '1h',
    price: 100.0,
    title: 'title',
    message: 'message',
    bias: bias,
    metrics: metrics,
    createdAt: '2026-07-11T10:22:30+00:00',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbData.build', () {
    test('resolves the fired candle by bar time and trims to ~60 bars', () {
      final a = _alert();
      final data = ThumbData.build(a, _candles(a));
      expect(data.candles, hasLength(ThumbData.targetBars));
      expect(data.firedIndex, data.candles.length - 1);
      expect(data.candles[data.firedIndex].time,
          AlertChartOverlay.alertBarTime(a));
    });

    test('keeps the zone start visible even beyond the 60-bar target', () {
      final a = _alert(metrics: const {
        'level_price': 100.0,
        'zone_low': 99.5,
        'zone_high': 100.5,
        'first_touch_bars_ago': 80,
      });
      final data = ThumbData.build(a, _candles(a));
      expect(data.candles.length, greaterThanOrEqualTo(80));
      expect(data.zoneFromIndex, data.firedIndex - 80);
      expect(data.zoneLow, 99.5);
      expect(data.zoneHigh, 100.5);
      expect(data.levelPrice, 100.0);
    });

    test('maps divergence pivots relative to the fired candle', () {
      final a = _alert(
        type: 'RSI_BEARISH_DIVERGENCE',
        bias: 'BEARISH',
        metrics: const {
          'pivot_a_bars_ago': 9,
          'pivot_b_bars_ago': 2,
          'pivot_a_price': 110.0,
          'pivot_b_price': 112.0,
        },
      );
      final data = ThumbData.build(a, _candles(a));
      expect(data.divergence, isNotNull);
      expect(data.divergence!.$1, data.firedIndex - 9);
      expect(data.divergence!.$2, 110.0);
      expect(data.divergence!.$3, data.firedIndex - 2);
      expect(data.divergence!.$4, 112.0);
    });

    test('missing geometry leaves setup fields null (candles + marker only)',
        () {
      final a = _alert(metrics: const {'level_price': 100.0, 'touches': 523});
      final data = ThumbData.build(a, _candles(a));
      expect(data.zoneFromIndex, isNull);
      expect(data.zoneLow, isNull);
      expect(data.divergence, isNull);
      expect(data.levelPrice, 100.0); // level line still draws
    });

    test('an alert older than the fetched window falls back to the last bar',
        () {
      final a = _alert();
      // Candles whose newest bar is far after the alert bar.
      final future = [
        for (var i = 0; i < 96; i++)
          Candle(
            time: AlertChartOverlay.alertBarTime(a) + (i + 200) * _tfSec,
            open: 100,
            high: 101,
            low: 99,
            close: 100,
            volume: 1,
          ),
      ];
      final data = ThumbData.build(a, future);
      expect(data.firedIndex, data.candles.length - 1);
    });
  });

  group('AlertThumbnail widget', () {
    late int hits;

    KlinesThumbnailService service(MarketAlert alert) {
      hits = 0;
      final rows = [
        for (final c in _candles(alert))
          [c.time * 1000, '${c.open}', '${c.high}', '${c.low}', '${c.close}', '${c.volume}'],
      ];
      final mock = MockClient((req) async {
        hits++;
        return http.Response(jsonEncode(rows), 200);
      });
      return KlinesThumbnailService.forTest(
        BinanceMarketData(httpClient: mock),
      );
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget host(Widget child) =>
        MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('shimmer while loading, CustomPaint once resolved',
        (tester) async {
      final a = _alert(id: 'w1');
      await tester.pumpWidget(
        host(AlertThumbnail(alert: a, service: service(a))),
      );
      expect(
        find.descendant(
          of: find.byType(AlertThumbnail),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertThumbnail),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(hits, 1);
    });

    testWidgets('memo hit repaints without a second fetch', (tester) async {
      final a = _alert(id: 'w2');
      final s = service(a);
      await tester.pumpWidget(host(AlertThumbnail(alert: a, service: s)));
      await tester.pumpAndSettle();
      expect(hits, 1);
      // Tear down and rebuild the same alert — the static memo serves it.
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpWidget(host(AlertThumbnail(alert: a, service: s)));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(AlertThumbnail),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(hits, 1);
    });

    testWidgets('fetch failure shows the unavailable placeholder',
        (tester) async {
      final mock = MockClient((req) async => http.Response('{}', 500));
      final s = KlinesThumbnailService.forTest(
        BinanceMarketData(httpClient: mock),
      );
      await tester.pumpWidget(
        host(AlertThumbnail(alert: _alert(id: 'w3'), service: s)),
      );
      await tester.pumpAndSettle();
      expect(find.text('chart unavailable'), findsOneWidget);
    });
  });

  group('AlertThumbnailPainter', () {
    void paintVariant(MarketAlert a) {
      final data = ThumbData.build(a, _candles(a));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      AlertThumbnailPainter(data).paint(canvas, const Size(320, 110));
      recorder.endRecording();
    }

    test('paints an S/R zone setup without throwing', () {
      paintVariant(_alert(metrics: const {
        'level_price': 100.0,
        'zone_low': 99.5,
        'zone_high': 100.5,
        'first_touch_bars_ago': 40,
      }));
    });

    test('paints a divergence setup without throwing', () {
      paintVariant(_alert(
        type: 'RSI_BEARISH_DIVERGENCE',
        bias: 'BEARISH',
        metrics: const {
          'pivot_a_bars_ago': 9,
          'pivot_b_bars_ago': 2,
          'pivot_a_price': 110.0,
          'pivot_b_price': 112.0,
        },
      ));
    });

    test('paints a geometry-less alert without throwing', () {
      paintVariant(_alert(type: 'VOLUME_SPIKE', bias: 'NEUTRAL'));
    });

    test('survives an empty candle list', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      AlertThumbnailPainter(
        const ThumbData(candles: [], firedIndex: 0, bias: 'NEUTRAL'),
      ).paint(canvas, const Size(320, 110));
      recorder.endRecording();
    });
  });
}

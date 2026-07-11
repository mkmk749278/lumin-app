/// SignalSnap — the signal-sheet setup snap (alert-card mini chart pattern).
///
/// Pins: (1) the timeframe auto-pick keeps the entry bar inside the
/// painted window; (2) SignalSnapData maps a signal to paint space
/// correctly (entry-bar resolution, 60-bar trim, out-of-window entry →
/// no marker, BE-armed effective stop, tpN>0 filtering); (3) the widget
/// goes shimmer → CustomPaint with one fetch, degrades to the
/// unavailable placeholder, and taps through; (4) the painter renders
/// every variant without throwing.
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumin/data/binance_market_data.dart';
import 'package:lumin/data/klines_thumbnail_service.dart';
import 'package:lumin/data/mock_data.dart';
import 'package:lumin/features/charts/models/candle.dart';
import 'package:lumin/features/signals/signal_snap.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tfSec = 900; // 15m — the fresh-signal default

/// A fixed "now" aligned exactly on a 15m bar open, so entry-bucket math
/// in the build tests is bar-exact.
final _now = DateTime.fromMillisecondsSinceEpoch(
  ((DateTime.utc(2026, 7, 11, 10).millisecondsSinceEpoch ~/ 1000 ~/ _tfSec) *
          _tfSec) *
      1000,
  isUtc: true,
);

/// [n] 15m candles, newest bar opening exactly at [_now] (or [lastOpen]).
List<Candle> _candles({int n = 96, int? lastOpen}) {
  final last = lastOpen ?? _now.millisecondsSinceEpoch ~/ 1000;
  return [
    for (var i = 0; i < n; i++)
      Candle(
        time: last - (n - 1 - i) * _tfSec,
        open: 100 + i * 0.1,
        high: 101 + i * 0.1,
        low: 99 + i * 0.1,
        close: 100.5 + i * 0.1,
        volume: 1000,
      ),
  ];
}

MockSignal _sig({
  String direction = 'LONG',
  String status = 'ACTIVE',
  int minutesAgo = 30,
  double entry = 100.0,
  double sl = 99.0,
  double tp1 = 101.0,
  double tp2 = 102.0,
  double tp3 = 0.0,
  double mfe = 0.0,
  bool? isOpen,
}) {
  return MockSignal(
    id: 'MVRTP-TEST1',
    symbol: 'RAVEUSDT',
    direction: direction,
    setupName: 'MOVER TREND PULLBACK',
    agentName: 'The Momentum Rider',
    entry: entry,
    sl: sl,
    tp1: tp1,
    tp2: tp2,
    tp3: tp3,
    confidence: 80,
    tier: 'A+',
    status: status,
    pnlPct: 0.0,
    minutesAgo: minutesAgo,
    maxFavorableExcursionPct: mfe,
    isOpen: isOpen,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SignalSnapData.pickTf', () {
    test('keeps the entry bar inside the painted window with margin', () {
      expect(SignalSnapData.pickTf(5), '15m');
      expect(SignalSnapData.pickTf(800), '15m');
      expect(SignalSnapData.pickTf(840), '15m'); // boundary: 56 bars × 15m
      expect(SignalSnapData.pickTf(900), '1h');
      expect(SignalSnapData.pickTf(3000), '1h');
      expect(SignalSnapData.pickTf(3360), '1h'); // boundary: 56 bars × 1h
      expect(SignalSnapData.pickTf(4000), '4h');
      expect(SignalSnapData.pickTf(20000), '4h');
    });
  });

  group('SignalSnapData.build', () {
    test('trims to 60 bars and resolves the entry bar by floored bucket', () {
      // 30 min ago on a 15m grid = exactly 2 bars before the newest.
      final data =
          SignalSnapData.build(_sig(minutesAgo: 30), '15m', _candles(), now: _now);
      expect(data.candles, hasLength(SignalSnapData.targetBars));
      expect(data.entryIndex, data.candles.length - 1 - 2);
      expect(data.candles[data.entryIndex!].time,
          _now.millisecondsSinceEpoch ~/ 1000 - 2 * _tfSec);
    });

    test('an entry older than the painted window gets no marker', () {
      // 60 painted 15m bars reach back ~885 min; 2000 min is far outside.
      final data = SignalSnapData.build(
          _sig(minutesAgo: 2000, status: 'SL_HIT', isOpen: false),
          '15m',
          _candles(),
          now: _now);
      expect(data.entryIndex, isNull);
    });

    test('BE-armed active signal shows the effective stop at entry', () {
      final data = SignalSnapData.build(
          _sig(mfe: 1.5), '15m', _candles(), now: _now);
      expect(data.beArmed, isTrue);
      expect(data.stop, data.entry);
    });

    test('un-armed signal keeps its original SL', () {
      final data = SignalSnapData.build(
          _sig(mfe: 0.4), '15m', _candles(), now: _now);
      expect(data.beArmed, isFalse);
      expect(data.stop, 99.0);
    });

    test('zero TPs map to null so no phantom lines draw', () {
      final data = SignalSnapData.build(
          _sig(tp2: 0.0, tp3: 0.0), '15m', _candles(), now: _now);
      expect(data.tp1, 101.0);
      expect(data.tp2, isNull);
      expect(data.tp3, isNull);
    });

    test('a closed SL_HIT signal still builds with its full geometry', () {
      final data = SignalSnapData.build(
          _sig(status: 'SL_HIT', isOpen: false, minutesAgo: 240),
          '15m',
          _candles(),
          now: _now);
      expect(data.beArmed, isFalse);
      expect(data.stop, 99.0);
      expect(data.entryIndex, data.candles.length - 1 - 16); // 240min = 16 bars
    });
  });

  group('SignalSnap widget', () {
    late int hits;

    KlinesThumbnailService service() {
      hits = 0;
      // Newest bar opens on the real wall-clock 15m bucket — the widget
      // resolves the entry bar against DateTime.now().
      final lastOpen =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ _tfSec) * _tfSec;
      final rows = [
        for (final c in _candles(lastOpen: lastOpen))
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

    testWidgets('shimmer while loading, CustomPaint once resolved with one fetch',
        (tester) async {
      await tester.pumpWidget(host(SignalSnap(sig: _sig(), service: service())));
      expect(
        find.descendant(
          of: find.byType(SignalSnap),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SignalSnap),
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
      await tester.pumpWidget(host(SignalSnap(sig: _sig(), service: s)));
      await tester.pumpAndSettle();
      expect(find.text('chart unavailable'), findsOneWidget);
    });

    testWidgets('tap fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(SignalSnap(
        sig: _sig(),
        service: service(),
        onTap: () => tapped = true,
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SignalSnap));
      expect(tapped, isTrue);
    });
  });

  group('SignalSnapPainter', () {
    void paintVariant(SignalSnapData data) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      SignalSnapPainter(data).paint(canvas, const Size(320, 110));
      recorder.endRecording();
    }

    test('paints a LONG setup without throwing', () {
      paintVariant(
          SignalSnapData.build(_sig(), '15m', _candles(), now: _now));
    });

    test('paints a SHORT setup without throwing', () {
      paintVariant(SignalSnapData.build(
          _sig(direction: 'SHORT', sl: 101.5, tp1: 99.0, tp2: 98.0),
          '15m',
          _candles(),
          now: _now));
    });

    test('paints a marker-less (out-of-window) setup without throwing', () {
      paintVariant(SignalSnapData.build(
          _sig(minutesAgo: 2000), '15m', _candles(), now: _now));
    });

    test('survives an empty candle list', () {
      paintVariant(const SignalSnapData(
        candles: [],
        entryIndex: null,
        direction: 'LONG',
        entry: 100,
        stop: 99,
        beArmed: false,
      ));
    });
  });
}

/// AlertChartOverlay (2026-07-11) — the alert→chart setup sync contract.
///
/// What we pin:
///
/// * alertBarTime lands on the OPEN of the closed candle that fired the
///   alert (chart marker must snap to a real bar).
/// * Near-S/R alerts draw the level line (solid, touch count in title)
///   plus the alert-price reference line.
/// * RSI-divergence alerts turn the engine's pivot bars-ago metrics into
///   a two-point segment at the correct bar times.
/// * Unknown / metric-less alerts degrade to an alert-price line, never
///   crash (older app vs newer engine).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/market_alert.dart';
import 'package:lumin/features/charts/models/alert_overlay.dart';

MarketAlert _alert({
  String type = 'NEAR_SUPPORT',
  String tf = '1h',
  String bias = 'BULLISH',
  double price = 100.0,
  Map<String, dynamic> metrics = const {},
  String createdAt = '2026-07-11T10:22:30+00:00',
}) {
  return MarketAlert(
    alertId: 'a1',
    alertType: type,
    symbol: 'RAVEUSDT',
    timeframe: tf,
    price: price,
    title: 'title',
    message: 'message',
    bias: bias,
    metrics: metrics,
    createdAt: createdAt,
  );
}

void main() {
  group('alertBarTime', () {
    test('snaps to the open of the last CLOSED candle before the alert', () {
      // 10:22:30 UTC on a 1h alert → the candle that fired closed at
      // 10:00, and its open was 09:00.
      final t = AlertChartOverlay.alertBarTime(_alert());
      final expected =
          DateTime.utc(2026, 7, 11, 9).millisecondsSinceEpoch ~/ 1000;
      expect(t, expected);
    });

    test('15m timeframe uses 15m buckets', () {
      final t = AlertChartOverlay.alertBarTime(_alert(tf: '15m'));
      final expected =
          DateTime.utc(2026, 7, 11, 10, 0).millisecondsSinceEpoch ~/ 1000;
      expect(t, expected);
    });
  });

  group('near-level alerts', () {
    test('draw the level line with touches + the alert-price reference', () {
      final o = AlertChartOverlay.fromAlert(_alert(
        metrics: {'level_price': 99.5, 'touches': 43},
      ));
      expect(o.lines, hasLength(2));
      expect(o.lines.first['price'], 99.5);
      expect(o.lines.first['title'], 'Support · 43×');
      expect(o.lines.first['solid'], isTrue);
      expect(o.lines.last['price'], 100.0);
      expect(o.segments, isEmpty);
      expect(o.markers, hasLength(1));
      expect(o.markers.first['position'], 'below'); // bullish bias
    });
  });

  group('divergence alerts', () {
    test('build the pivot segment from bars-ago metrics', () {
      final a = _alert(
        type: 'RSI_BEARISH_DIVERGENCE',
        bias: 'BEARISH',
        metrics: {
          'pivot_a_bars_ago': 9,
          'pivot_b_bars_ago': 2,
          'pivot_a_price': 110.0,
          'pivot_b_price': 112.0,
        },
      );
      final o = AlertChartOverlay.fromAlert(a);
      final barTime = AlertChartOverlay.alertBarTime(a);
      expect(o.segments, hasLength(1));
      final points = o.segments.first['points'] as List;
      expect(points[0], {'time': barTime - 9 * 3600, 'value': 110.0});
      expect(points[1], {'time': barTime - 2 * 3600, 'value': 112.0});
      expect(o.markers.first['position'], 'above'); // bearish bias
    });

    test('missing pivot metrics degrade to the reference line only', () {
      final o = AlertChartOverlay.fromAlert(
        _alert(type: 'RSI_BULLISH_DIVERGENCE'),
      );
      expect(o.segments, isEmpty);
      expect(o.lines, hasLength(1));
    });
  });

  test('RSI extreme titles the alert-price line with the RSI value', () {
    final o = AlertChartOverlay.fromAlert(_alert(
      type: 'RSI_OVERSOLD',
      metrics: {'rsi': 19.0},
    ));
    expect(o.lines.single['title'], 'RSI 19.0');
  });

  test('unknown alert type never crashes and still marks the bar', () {
    final o = AlertChartOverlay.fromAlert(_alert(type: 'SOME_FUTURE_TYPE'));
    expect(o.lines, hasLength(1));
    expect(o.markers, hasLength(1));
    expect(o.toJson().keys, containsAll(['lines', 'segments', 'markers']));
  });

  group('S/R zone geometry (v3)', () {
    final metrics = {
      'level_price': 99.5,
      'touches': 4,
      'touch_count': 4,
      'zone_low': 99.2,
      'zone_high': 99.8,
      'first_touch_bars_ago': 40,
      'last_touch_bars_ago': 1,
    };

    test('draws the shaded zone from the first touch and focuses on it', () {
      final a = _alert(metrics: metrics);
      final o = AlertChartOverlay.fromAlert(a);
      final barTime = AlertChartOverlay.alertBarTime(a);
      expect(o.zones, hasLength(1));
      final z = o.zones.single;
      expect(z['from'], barTime - 40 * 3600);
      expect(z['low'], 99.2);
      expect(z['high'], 99.8);
      expect(z['label'], 'Support · 4×');
      expect(o.lines.first['title'], 'Support · 4×'); // prefers touch_count
      expect(o.focus, isNotNull);
      expect(o.focus!['from'], barTime - (40 + 8) * 3600);
      expect(o.focus!['to'], barTime + 15 * 3600);
    });

    test('caps a very old first touch so the box stays framable', () {
      final a = _alert(metrics: {...metrics, 'first_touch_bars_ago': 500});
      final o = AlertChartOverlay.fromAlert(a);
      final barTime = AlertChartOverlay.alertBarTime(a);
      expect(o.zones.single['from'], barTime - 180 * 3600);
    });

    test('missing zone geometry degrades to the pre-v3 line-only look', () {
      final o = AlertChartOverlay.fromAlert(_alert(
        metrics: {'level_price': 99.5, 'touches': 43},
      ));
      expect(o.zones, isEmpty);
      expect(o.lines, hasLength(2)); // level + reference, exactly as before
      expect(o.focus, isNotNull); // default window still frames the alert
    });
  });

  group('divergence RSI-pane mirror (v3)', () {
    final metrics = {
      'pivot_a_bars_ago': 9,
      'pivot_b_bars_ago': 2,
      'pivot_a_price': 110.0,
      'pivot_b_price': 112.0,
      'rsi_first': 71.2,
      'rsi_second': 64.8,
    };

    test('mirrors the trend line on the RSI band', () {
      final a = _alert(
        type: 'RSI_BEARISH_DIVERGENCE',
        bias: 'BEARISH',
        metrics: metrics,
      );
      final o = AlertChartOverlay.fromAlert(a);
      final barTime = AlertChartOverlay.alertBarTime(a);
      expect(o.rsiSegments, hasLength(1));
      final points = o.rsiSegments.single['points'] as List;
      expect(points[0], {'time': barTime - 9 * 3600, 'value': 71.2});
      expect(points[1], {'time': barTime - 2 * 3600, 'value': 64.8});
      expect(o.focus!['from'], barTime - (9 + 8) * 3600);
    });

    test('missing RSI values keep the price segment but no RSI mirror', () {
      final o = AlertChartOverlay.fromAlert(_alert(
        type: 'RSI_BEARISH_DIVERGENCE',
        metrics: {...metrics}
          ..remove('rsi_first'),
      ));
      expect(o.segments, hasLength(1));
      expect(o.rsiSegments, isEmpty);
    });
  });

  group('chartTf mismatch', () {
    test('emits only price lines when the chart is on another timeframe', () {
      final o = AlertChartOverlay.fromAlert(
        _alert(metrics: {
          'level_price': 99.5,
          'touch_count': 4,
          'zone_low': 99.2,
          'zone_high': 99.8,
          'first_touch_bars_ago': 40,
        }),
        chartTf: '15m', // alert is 1h — bar-offset math would be wrong
      );
      expect(o.lines, isNotEmpty); // price lines are TF-independent
      expect(o.zones, isEmpty);
      expect(o.markers, isEmpty);
      expect(o.focus, isNull);
    });

    test('matching chartTf emits everything', () {
      final o = AlertChartOverlay.fromAlert(
        _alert(metrics: {
          'level_price': 99.5,
          'touch_count': 4,
          'zone_low': 99.2,
          'zone_high': 99.8,
          'first_touch_bars_ago': 40,
        }),
        chartTf: '1h',
      );
      expect(o.zones, hasLength(1));
      expect(o.markers, hasLength(1));
      expect(o.focus, isNotNull);
    });
  });

  group('bridge contract', () {
    test('toJson always carries the v3 arrays and omits a null focus', () {
      final mismatch = AlertChartOverlay.fromAlert(_alert(), chartTf: '4h');
      expect(
        mismatch.toJson().keys,
        containsAll(['lines', 'segments', 'markers', 'rsiSegments', 'zones']),
      );
      expect(mismatch.toJson().containsKey('focus'), isFalse);

      final matched = AlertChartOverlay.fromAlert(_alert());
      expect(matched.toJson()['focus'], isNotNull);
    });
  });
}

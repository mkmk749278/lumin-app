/// MarketAlert model (2026-07-11) — Pulse → Alerts feed.
///
/// What we pin:
///
/// * fromMap tolerates missing / malformed fields (an older cached SWR
///   payload or a newer engine must never crash the feed).
/// * toMap/fromMap round-trips (SWR cache persistence).
/// * agoLabel renders sane relative ages across the m/h/d boundaries.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/market_alert.dart';

void main() {
  final full = <String, dynamic>{
    'alert_id': 'abc123',
    'alert_type': 'RSI_OVERBOUGHT',
    'symbol': 'BTCUSDT',
    'timeframe': '1h',
    'price': 64230.5,
    'title': 'RSI Extremely Overbought',
    'message': 'RSI(14) at 83.4 — extremely overbought',
    'bias': 'BEARISH',
    'metrics': {'rsi': 83.4},
    'created_at': '2026-07-11T08:30:00+00:00',
  };

  group('MarketAlert.fromMap', () {
    test('parses a full engine payload', () {
      final a = MarketAlert.fromMap(full);
      expect(a.alertId, 'abc123');
      expect(a.alertType, 'RSI_OVERBOUGHT');
      expect(a.symbol, 'BTCUSDT');
      expect(a.timeframe, '1h');
      expect(a.price, 64230.5);
      expect(a.bias, 'BEARISH');
      expect(a.metrics['rsi'], 83.4);
      expect(a.createdAtUtc, DateTime.utc(2026, 7, 11, 8, 30));
    });

    test('tolerates an empty payload (shape drift never crashes)', () {
      final a = MarketAlert.fromMap(const {});
      expect(a.alertType, '');
      expect(a.price, 0.0);
      expect(a.bias, 'NEUTRAL');
      expect(a.metrics, isEmpty);
      expect(a.createdAtUtc, isNull);
      expect(a.agoLabel(), '');
    });

    test('int price coerces to double', () {
      final a = MarketAlert.fromMap({...full, 'price': 64230});
      expect(a.price, 64230.0);
    });
  });

  test('toMap/fromMap round-trips (SWR persistence)', () {
    final a = MarketAlert.fromMap(full);
    final b = MarketAlert.fromMap(a.toMap());
    expect(b.toMap(), a.toMap());
  });

  group('agoLabel', () {
    MarketAlert at(DateTime created) => MarketAlert.fromMap({
          ...full,
          'created_at': created.toIso8601String(),
        });
    final now = DateTime.utc(2026, 7, 11, 12, 0);

    test('sub-minute → just now', () {
      expect(at(now.subtract(const Duration(seconds: 20))).agoLabel(now: now),
          'just now');
    });

    test('minutes', () {
      expect(at(now.subtract(const Duration(minutes: 12))).agoLabel(now: now),
          '12m ago');
    });

    test('hours', () {
      expect(at(now.subtract(const Duration(hours: 3))).agoLabel(now: now),
          '3h ago');
    });

    test('days', () {
      expect(at(now.subtract(const Duration(days: 2))).agoLabel(now: now),
          '2d ago');
    });
  });

  test('mockAlerts fixture covers distinct alert types', () {
    expect(mockAlerts, isNotEmpty);
    final types = mockAlerts.map((a) => a.alertType).toSet();
    expect(types.length, greaterThan(2));
  });
}

/// Candle / MarketTicker parsing for the Market Charts tab. Pure parsing —
/// asserts the Binance kline-array and WS-frame shapes map correctly and that
/// openTime (ms) is converted to the seconds unit Lightweight Charts expects.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/charts/models/candle.dart';

void main() {
  group('Candle.fromKlineArray', () {
    test('parses a REST kline row and converts ms→s', () {
      // [openTime, open, high, low, close, volume, closeTime, ...]
      final row = <dynamic>[
        1719640000000, '0.10799', '0.11200', '0.10500', '0.11000', '12345.6',
        1719640899999, '0', 100, '0', '0', '0',
      ];
      final c = Candle.fromKlineArray(row);
      expect(c.time, 1719640000); // ms → s
      expect(c.open, 0.10799);
      expect(c.high, 0.11200);
      expect(c.low, 0.10500);
      expect(c.close, 0.11000);
      expect(c.volume, 12345.6);
    });

    test('toChartJson uses seconds time + OHLC (no volume)', () {
      final c = Candle.fromKlineArray(
        [1719640000000, '1', '2', '0.5', '1.5', '10', 0],
      );
      expect(c.toChartJson(), {
        'time': 1719640000,
        'open': 1.0,
        'high': 2.0,
        'low': 0.5,
        'close': 1.5,
      });
      expect(c.toVolumeJson(), {'time': 1719640000, 'value': 10.0});
    });
  });

  group('Candle.fromWsKline', () {
    test('parses the k payload from a kline WS frame', () {
      final k = <String, dynamic>{
        't': 1719641800000, 'o': '0.11', 'h': '0.12', 'l': '0.10',
        'c': '0.115', 'v': '999.0', 'x': false,
      };
      final c = Candle.fromWsKline(k);
      expect(c.time, 1719641800);
      expect(c.close, 0.115);
      expect(c.volume, 999.0);
    });
  });

  group('upsertCandles (live-poll merge)', () {
    Candle c(int t, double close) => Candle(
        time: t, open: close, high: close, low: close, close: close, volume: 1);

    test('replaces the in-progress bar and appends the new one', () {
      final base = [c(100, 1), c(200, 2)];
      final out = upsertCandles(base, [c(200, 2.5), c(300, 3)]);
      expect([for (final x in out) x.time], [100, 200, 300]);
      expect(out[1].close, 2.5);
      expect(out.last.close, 3);
    });

    test('bars older than anything held are dropped, not inserted', () {
      final base = [c(200, 2), c(300, 3)];
      final out = upsertCandles(base, [c(100, 1)]);
      expect([for (final x in out) x.time], [200, 300]);
    });

    test('empty base takes the updates as-is; empty updates are a no-op', () {
      expect(upsertCandles([], [c(100, 1)]).length, 1);
      final base = [c(100, 1)];
      expect(upsertCandles(base, []), same(base));
    });
  });

  group('MarketTicker.fromJson', () {
    test('parses 24h ticker fields with string numerics', () {
      final t = MarketTicker.fromJson({
        'symbol': 'GUAUSDT',
        'lastPrice': '0.2034',
        'priceChangePercent': '-23.50',
        'quoteVolume': '18000000.0',
      });
      expect(t.symbol, 'GUAUSDT');
      expect(t.lastPrice, 0.2034);
      expect(t.changePct, -23.5);
      expect(t.quoteVolume, 18000000.0);
    });

    test('missing/garbage fields degrade to safe defaults', () {
      final t = MarketTicker.fromJson({'symbol': 'XUSDT'});
      expect(t.symbol, 'XUSDT');
      expect(t.lastPrice, 0.0);
      expect(t.changePct, 0.0);
      expect(t.quoteVolume, 0.0);
    });
  });
}

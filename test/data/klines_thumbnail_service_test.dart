/// KlinesThumbnailService — the caching contract behind alert-card
/// thumbnails: memory TTL, in-flight dedup, disk round-trip + LRU prune.
///
/// Strategy: inject ``MockClient`` (package:http/testing) into a real
/// [BinanceMarketData] so the service exercises its true kline-parsing
/// path, and count HTTP hits to pin the dedup/caching behaviour.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumin/data/binance_market_data.dart';
import 'package:lumin/data/klines_thumbnail_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<List<dynamic>> _klineRows(int n) => [
      for (var i = 0; i < n; i++)
        [
          (1720000000 + i * 3600) * 1000, // openTime ms
          '100.0', '101.0', '99.0', '100.5', '1200.0',
          0, '0', 0, '0', '0', '0',
        ],
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int hits;

  KlinesThumbnailService service() {
    hits = 0;
    final mock = MockClient((req) async {
      hits++;
      return http.Response(jsonEncode(_klineRows(96)), 200);
    });
    return KlinesThumbnailService.forTest(
      BinanceMarketData(httpClient: mock),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('memory cache serves repeat requests without refetching', () async {
    final s = service();
    final first = await s.get('BTCUSDT', '1h');
    final second = await s.get('BTCUSDT', '1h');
    expect(first, hasLength(96));
    expect(identical(first, second), isTrue);
    expect(hits, 1);
  });

  test('concurrent requests for one key share a single fetch', () async {
    final s = service();
    final results = await Future.wait([
      s.get('ETHUSDT', '1h'),
      s.get('ETHUSDT', '1h'),
      s.get('ETHUSDT', '1h'),
    ]);
    expect(hits, 1);
    expect(results[0], hasLength(96));
  });

  test('different keys fetch independently', () async {
    final s = service();
    await s.get('BTCUSDT', '1h');
    await s.get('BTCUSDT', '4h');
    await s.get('SOLUSDT', '1h');
    expect(hits, 3);
  });

  test('disk layer round-trips: a fresh service instance skips the network',
      () async {
    final s1 = service();
    await s1.get('BTCUSDT', '1h'); // network → memory + disk
    await s1.diskWritesSettled;
    expect(hits, 1);

    final s2 = service(); // new instance, empty memory, same (mock) disk
    final candles = await s2.get('BTCUSDT', '1h');
    expect(hits, 0); // served from disk
    expect(candles, hasLength(96));
    expect(candles.first.open, 100.0);
    expect(candles.first.time, 1720000000);
  });

  test('disk index prunes beyond the LRU cap', () async {
    final s = service();
    // Cap is 40 keys — write 42 and expect the 2 oldest gone.
    for (var i = 0; i < 42; i++) {
      await s.get('SYM${i}USDT', '1h');
    }
    await s.diskWritesSettled;
    final p = await SharedPreferences.getInstance();
    expect(p.getString('thumb.SYM0USDT|1h'), isNull);
    expect(p.getString('thumb.SYM1USDT|1h'), isNull);
    expect(p.getString('thumb.SYM41USDT|1h'), isNotNull);
    expect(p.getStringList('thumb.index'), hasLength(40));
  });

  test('a failing fetch surfaces the error and does not poison the cache',
      () async {
    var fail = true;
    final mock = MockClient((req) async {
      hits++;
      if (fail) throw Exception('network down');
      return http.Response(jsonEncode(_klineRows(96)), 200);
    });
    hits = 0;
    final s = KlinesThumbnailService.forTest(
      BinanceMarketData(httpClient: mock),
    );
    await expectLater(s.get('BTCUSDT', '1h'), throwsA(anything));
    fail = false;
    final candles = await s.get('BTCUSDT', '1h'); // retry succeeds
    expect(candles, hasLength(96));
    expect(hits, 2);
  });
}

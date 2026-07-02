/// Charts-tab pair ordering — live-signal pairs float to the top while the
/// volume order is preserved within each partition (design §10).
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/charts/charts_page.dart';
import 'package:lumin/features/charts/models/candle.dart';

MarketTicker _t(String symbol, double vol) => MarketTicker(
      symbol: symbol,
      lastPrice: 1.0,
      changePct: 0.0,
      quoteVolume: vol,
    );

void main() {
  final rows = [
    _t('BTCUSDT', 900),
    _t('ETHUSDT', 800),
    _t('SOLUSDT', 700),
    _t('GUAUSDT', 50),
  ];

  test('no live signals: order untouched', () {
    expect(orderPairRows(rows, const {}), same(rows));
  });

  test('live-signal pairs float first, volume order kept in both partitions', () {
    final out = orderPairRows(rows, {'GUAUSDT', 'ETHUSDT'});
    expect(
      [for (final r in out) r.symbol],
      ['ETHUSDT', 'GUAUSDT', 'BTCUSDT', 'SOLUSDT'],
    );
  });

  test('signal symbols absent from the board are simply ignored', () {
    final out = orderPairRows(rows, {'NOPEUSDT'});
    expect([for (final r in out) r.symbol],
        ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'GUAUSDT']);
  });
}

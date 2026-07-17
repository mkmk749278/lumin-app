/// Chart header formatting + TF table consistency (2026-07-17 polish).
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/binance_market_data.dart';
import 'package:lumin/features/charts/chart_stats.dart';

void main() {
  group('formatHeaderPrice', () {
    test('thousands separators at chart precision', () {
      expect(formatHeaderPrice(1822.42, 2), '1,822.42');
      expect(formatHeaderPrice(62677.0, 1), '62,677.0');
    });
    test('sub-dollar alts keep their precision', () {
      expect(formatHeaderPrice(0.008547, 6), '0.008547');
    });
    test('zero precision renders whole numbers', () {
      expect(formatHeaderPrice(1234567, 0), '1,234,567');
    });
  });

  group('formatHeaderPct', () {
    test('signs explicitly', () {
      expect(formatHeaderPct(1.28), '+1.28%');
      expect(formatHeaderPct(-0.451), '-0.45%');
      expect(formatHeaderPct(0), '+0.00%');
    });
  });

  test('every chart TF has a Binance interval (incl. the new 1D)', () {
    const tfs = ['1m', '5m', '15m', '1h', '4h', '1D'];
    for (final tf in tfs) {
      expect(
        BinanceMarketData.intervals[tf],
        isNotNull,
        reason: '$tf must map to a Binance interval code',
      );
    }
    expect(BinanceMarketData.intervals['1D'], '1d');
  });
}

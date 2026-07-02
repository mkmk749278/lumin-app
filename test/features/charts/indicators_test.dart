/// Indicator math + price-format derivation for the Market Charts tab.
/// Pure functions — known-value checks computed by hand.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/charts/indicators.dart';

void main() {
  group('sma', () {
    test('nulls through warm-up, then rolling mean', () {
      expect(sma([1, 2, 3, 4, 5], 3), [null, null, 2.0, 3.0, 4.0]);
    });

    test('series shorter than period is all null', () {
      expect(sma([1, 2], 3), [null, null]);
    });
  });

  group('ema', () {
    test('seeds with SMA of the first period, then smooths (k = 2/(p+1))', () {
      // period 3 → k = 0.5; seed at i=2 is (1+2+3)/3 = 2
      // i=3: 4·0.5 + 2·0.5 = 3;  i=4: 5·0.5 + 3·0.5 = 4
      expect(ema([1, 2, 3, 4, 5], 3), [null, null, 2.0, 3.0, 4.0]);
    });

    test('constant series stays at the constant', () {
      final out = ema(List.filled(10, 7.0), 4);
      expect(out.sublist(3), everyElement(7.0));
    });
  });

  group('rsi', () {
    test('monotonic rise (no losses) reads 100', () {
      final out = rsi([for (var i = 0; i < 20; i++) i.toDouble()], period: 14);
      expect(out.sublist(0, 14), everyElement(isNull));
      expect(out[14], 100);
      expect(out.last, 100);
    });

    test('Wilder smoothing hand-computed case (period 2)', () {
      // values 1,2,1,2 → deltas +1,−1,+1
      // seed: avgGain 0.5, avgLoss 0.5 → RSI[2] = 50
      // next: avgGain (0.5+1)/2 = 0.75, avgLoss 0.25 → RS 3 → RSI[3] = 75
      final out = rsi([1, 2, 1, 2], period: 2);
      expect(out[0], isNull);
      expect(out[1], isNull);
      expect(out[2], closeTo(50, 1e-9));
      expect(out[3], closeTo(75, 1e-9));
    });

    test('stays within 0..100 on a noisy series', () {
      final vals = [for (var i = 0; i < 60; i++) 100 + 7.0 * ((i * 13) % 5 - 2)];
      for (final v in rsi(vals)) {
        if (v != null) {
          expect(v, inInclusiveRange(0, 100));
        }
      }
    });
  });

  group('chartPrecisionFor', () {
    test('majors keep the 2-decimal floor', () {
      expect(chartPrecisionFor(43000.5), 2); // BTC
      expect(chartPrecisionFor(110.0), 2); // SOL
    });

    test('sub-dollar alts get enough decimals to resolve the tick', () {
      expect(chartPrecisionFor(1.5), 4);
      expect(chartPrecisionFor(0.107), 5); // the 0.10-range perp the doc cites
      expect(chartPrecisionFor(0.00001234), 8); // memecoin, clamped at 8
    });

    test('degenerate inputs fall back to the default 2', () {
      expect(chartPrecisionFor(0), 2);
      expect(chartPrecisionFor(-1), 2);
      expect(chartPrecisionFor(double.nan), 2);
    });
  });

  test('minMoveForPrecision is 10^-precision', () {
    expect(minMoveForPrecision(2), closeTo(0.01, 1e-12));
    expect(minMoveForPrecision(5), closeTo(0.00001, 1e-12));
  });
}

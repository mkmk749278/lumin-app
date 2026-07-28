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

  group('parabolicSar', () {
    // ------------------------------------------------------------------
    // Cross-repo contract vector.
    //
    // HIGHS/LOWS below are a synthetic 40-bar series (rise → roll over →
    // fall → recover) chosen because it flips the SAR twice — a single-trend
    // series never exercises the reversal branch, which is the half of the
    // algorithm that is easy to get wrong.
    //
    // EXPECTED is not hand-computed and not computed by this port: it is the
    // output of the ENGINE's `parabolic_sar` (`src/sar_exit_shadow.py` in
    // `mkmk749278/360-v2`) run on exactly these inputs at 0.02/0.2. The same
    // three lists are pinned engine-side in `tests/test_sar_chart_contract.py`.
    // If either implementation drifts, one of the two CIs goes red — which is
    // the point: the chart must not draw a different indicator from the one
    // the engine's SAR study measures.
    // ------------------------------------------------------------------
    const highs = <double>[
      100.8, 102.0454, 103.2632, 104.4266, 105.5102, 106.4911, 107.3488, //
      108.0667, 108.6316, 109.035, 109.2724, 109.3444, 109.2558, 109.016,
      108.6385, 108.1408, 107.5436, 106.8704, 106.1467, 105.3996, 104.6566,
      103.9453, 103.2923, 102.7227, 102.2592, 101.9215, 101.7259, 101.6848,
      101.8063, 102.0938, 102.5465, 103.1585, 103.92, 104.8168, 105.8308,
      106.941, 108.1235, 109.3525, 110.6008, 111.8407,
    ];
    const lows = <double>[
      99.2, 100.4454, 101.6632, 102.8266, 103.9102, 104.8911, 105.7488, //
      106.4667, 107.0316, 107.435, 107.6724, 107.7444, 107.6558, 107.416,
      107.0385, 106.5408, 105.9436, 105.2704, 104.5467, 103.7996, 103.0566,
      102.3453, 101.6923, 101.1227, 100.6592, 100.3215, 100.1259, 100.0848,
      100.2063, 100.4938, 100.9465, 101.5585, 102.32, 103.2168, 104.2308,
      105.341, 106.5235, 107.7525, 109.0008, 110.2407,
    ];
    const expected = <double?>[
      null, 99.2, 99.2, 99.362528, 99.66637232, 100.1338785344, //
      100.76960068096, 101.55910459924479, 102.47016795535052,
      103.45599708249443, 104.46021760764543, 105.42265408611635,
      106.20700326889308, 106.83448261511445, 109.3444, 109.298282,
      109.18798272, 108.99331975679999, 108.695486176256, 108.2806075586304,
      107.74288665159474, 107.08680652037148, 106.32816547711204,
      105.49370969123187, 104.6195077529855, 103.8274462023884,
      103.12625696191073, 102.52618556952858, 102.03790845562287, 100.0848,
      100.12498000000001, 100.22184080000001, 100.39804035200001,
      100.67979712384, 101.093497411456, 101.66197372208129,
      102.4010374009899, 103.31663141683153, 104.40308776180186,
      105.64263020944149,
    ];

    test('reproduces the engine implementation bar for bar', () {
      final out = parabolicSar(highs, lows);
      expect(out, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        if (expected[i] == null) {
          expect(out[i], isNull, reason: 'bar $i should have no level yet');
        } else {
          expect(out[i], isNotNull, reason: 'bar $i lost its level');
          expect(out[i]!, closeTo(expected[i]!, 1e-9), reason: 'bar $i');
        }
      }
    });

    test('flips sides with the trend rather than trailing through price', () {
      final out = parabolicSar(highs, lows);
      // Bars 14..28 are the down leg: the stop sits ABOVE the bar's high.
      for (var i = 14; i <= 28; i++) {
        expect(out[i]!, greaterThan(highs[i]), reason: 'bar $i is bearish');
      }
      // Either side of that leg it sits BELOW the bar's low.
      for (final i in [10, 13, 30, 39]) {
        expect(out[i]!, lessThan(lows[i]), reason: 'bar $i is bullish');
      }
    });

    test('uses the engine study parameters by default', () {
      expect(kSarStep, 0.02);
      expect(kSarMaxStep, 0.2);
      expect(kSarStudyTf, '15m');
      expect(parabolicSar(highs, lows), parabolicSar(highs, lows,
          step: kSarStep, maxStep: kSarMaxStep));
    });

    test('refuses rather than clamps when the inputs cannot support it', () {
      // Too short for the recursion to seed.
      expect(parabolicSar(const [1], const [0.5]), [null]);
      expect(parabolicSar(const [], const []), isEmpty);
      // Mismatched arrays are refused whole — never truncated to the shorter,
      // which would silently compute SAR over a series nobody asked for.
      expect(
        parabolicSar(const [1, 2, 3], const [0.5, 1.5]),
        [null, null, null],
      );
    });

    test('a flat series parks the stop and never reverses', () {
      final flat = List<double>.filled(30, 100.0);
      final out = parabolicSar(flat, flat);
      expect(out[0], isNull);
      for (var i = 1; i < out.length; i++) {
        expect(out[i], closeTo(100.0, 1e-9));
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

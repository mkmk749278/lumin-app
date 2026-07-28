/// The SAR caption is load-bearing copy, so it is pinned like any other
/// contract. Two claims must never be inferable from the chart study:
/// that Lumin exits on a SAR flip, and that a SAR-agreeing signal is a better
/// signal. Neither is true (see `sar_disclosure.dart` for the measurement),
/// and the only thing standing between a user and both inferences is this
/// string — so a silent edit that drops the qualifier fails CI.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/charts/indicators.dart';
import 'package:lumin/features/charts/sar_disclosure.dart';

void main() {
  group('sarCaption', () {
    test('always states the parameters and that exits are unaffected', () {
      for (final tf in ['1m', '5m', '15m', '1h', '4h']) {
        final c = sarCaption(tf);
        expect(c, contains('0.02/0.2'));
        expect(c, contains('Chart study only'));
        expect(c, contains("SL/TP"));
      }
    });

    test('on the study timeframe it says the timeframes agree', () {
      final c = sarCaption(kSarStudyTf);
      expect(c, contains('15m'));
      expect(c, contains('the timeframe our signal research uses'));
      expect(c, isNot(contains('will not match')));
    });

    test('off the study timeframe it warns the dots will not match', () {
      final c = sarCaption('1m');
      expect(c, contains('drawn on 1m'));
      expect(c, contains('15m'));
      expect(c, contains('will not match'));
    });

    test('makes no claim about SAR agreement predicting signal quality', () {
      for (final tf in ['1m', '15m', '4h']) {
        final c = sarCaption(tf).toLowerCase();
        for (final banned in ['confirm', 'agree', 'better', 'stronger']) {
          expect(c, isNot(contains(banned)),
              reason: '"$banned" reads as a quality claim the data does not '
                  'support (agreed cohort nets +0.007%/trade)');
        }
      }
    });
  });
}

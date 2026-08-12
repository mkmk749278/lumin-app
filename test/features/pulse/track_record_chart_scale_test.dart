/// `TrackRecordChartScale` — a loss must not be drawn smaller than it is.
///
/// Moved here on 2026-08-12 when the Pulse summary card was removed and the
/// signal-book-by-day card kept (owner: *"we don't need two track cards
/// there"*). The scale outlived that card — the full record page still draws
/// these bars — and the property it guards is invisible without measuring
/// pixels, so it keeps its own tests rather than riding a widget's.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/pulse/track_record_chart_scale.dart';

void main() {
  group('TrackRecordChartScale — a loss must not be drawn smaller than it is',
      () {
    // The defect this guards was found by looking at the rendered chart, not
    // by a test: on the owner's real 30-day book a -$22.85 day drew about a
    // third as tall as a +$26.18 day, because the zero line was placed by the
    // running total's range and each side then filled whatever room was left.
    // Every number behind it was correct and the chart said the losses were
    // small — the one direction a performance surface must never be wrong in,
    // and invisible without measuring pixels. So the property is asserted here
    // rather than left to a glance.
    const h = 96.0;

    double distance(TrackRecordChartScale s, double v, List<double> series) =>
        (s.y(v, series) - s.zeroY).abs();

    test('equal magnitudes either side of zero are equal distances', () {
      final bars = [26.18, -22.85, 14.59, -3.21];
      final s = TrackRecordChartScale.of(h, [bars]);
      expect(distance(s, 20.0, bars), closeTo(distance(s, -20.0, bars), 1e-9));
      expect(distance(s, 5.0, bars), closeTo(distance(s, -5.0, bars), 1e-9));
    });

    test('...and it still holds with a second, far larger series present', () {
      // This is the real configuration: daily bars against a running total an
      // order of magnitude bigger. The asymmetry entered exactly here.
      final bars = [26.18, -22.85, 14.59, -3.21];
      final cums = [6.04, -29.08, 42.55, 55.06, 51.85];
      final s = TrackRecordChartScale.of(h, [bars, cums]);
      expect(distance(s, 26.18, bars), closeTo(distance(s, -26.18, bars), 1e-9));
      expect(distance(s, 55.06, cums), closeTo(distance(s, -55.06, cums), 1e-9));
    });

    test('the pre-fix placement would have failed this', () {
      // Sanity on the vector itself: with zero placed by the running total's
      // range alone, the two sides genuinely differ — so the assertions above
      // are testing something, not restating an identity.
      final cums = [6.04, -29.08, 42.55, 55.06, 51.85];
      final hi = cums.reduce((a, b) => a > b ? a : b);
      final lo = cums.reduce((a, b) => a < b ? a : b);
      final zeroFrac = hi / (hi - lo);
      expect(zeroFrac * h, greaterThan((1 - zeroFrac) * h * 1.5));
    });

    test('each series keeps its own full scale', () {
      // A day's result and a month's running total differ by an order of
      // magnitude; one shared magnitude scale would flatten the bars into the
      // axis. Their peaks should reach comparable extents.
      final bars = [26.18, -22.85];
      final cums = [55.06, -29.08];
      final s = TrackRecordChartScale.of(h, [bars, cums]);
      expect(distance(s, 26.18, bars), closeTo(distance(s, 55.06, cums), 1e-9));
    });

    test('an all-positive book does not waste half the chart below zero', () {
      final bars = [1.0, 2.0, 3.0];
      final s = TrackRecordChartScale.of(h, [bars]);
      // Zero sits at the bottom, so the whole height carries the book.
      expect(s.zeroY, greaterThan(h * 0.9));
      expect(s.y(3.0, bars), lessThan(h * 0.1));
    });

    test('an all-negative book mirrors it', () {
      final bars = [-1.0, -2.0, -3.0];
      final s = TrackRecordChartScale.of(h, [bars]);
      expect(s.zeroY, lessThan(h * 0.1));
      expect(s.y(-3.0, bars), greaterThan(h * 0.9));
    });

    test('a flat book does not divide by zero', () {
      final s = TrackRecordChartScale.of(h, [
        [0.0, 0.0]
      ]);
      expect(s.y(0.0, [0.0, 0.0]), s.zeroY);
      expect(s.zeroY.isFinite, isTrue);
    });

    test('an empty series does not divide by zero', () {
      final s = TrackRecordChartScale.of(h, [<double>[]]);
      expect(s.zeroY.isFinite, isTrue);
      expect(s.y(1.0, <double>[]), s.zeroY);
    });

    test('nothing is drawn outside the canvas', () {
      final bars = [26.18, -22.85];
      final cums = [55.06, -29.08];
      final s = TrackRecordChartScale.of(h, [bars, cums]);
      for (final v in bars) {
        expect(s.y(v, bars), inInclusiveRange(0, h));
      }
      for (final v in cums) {
        expect(s.y(v, cums), inInclusiveRange(0, h));
      }
    });
  });
}

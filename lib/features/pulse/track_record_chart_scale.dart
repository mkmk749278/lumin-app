/// Where zero sits on a track-record chart, and how far a value is drawn
/// from it.
///
/// Lives in its own file because it outlived the widget it was written for.
/// The Pulse summary card that first drew these bars was removed on
/// 2026-08-12 (owner: *"we don't need two track cards there, keep that signal
/// book by day"*). The full record page still draws them, and the property
/// this object guarantees is the one a glance at a chart cannot verify.
library;

import 'dart:math' as math;

/// Where zero sits, and how far a value is drawn from it.
///
/// Public so `track_record_chart_scale_test.dart` can drive the symmetry
/// property directly. Measuring it through a rendered
/// CustomPaint would mean asserting pixels, and a test nobody can read is not
/// a guard against a defect nobody can see.
///
/// Exists as its own object because the property it guarantees is the one a
/// glance at the chart cannot verify and a reader would never question:
///
/// > **A dollar above zero and a dollar below it are the same number of
/// > pixels.**
///
/// The first cut gave the two sides independent room — the zero line was placed
/// by the running total's range, and each series then filled whatever space was
/// left on its own side. On the owner's real 30-day book that put zero at 65%
/// of the height, so a **-$22.85 day rendered about a third as tall as a
/// +$26.18 day**. Every number behind it was right and the chart said the
/// losses were small. On a performance surface that is the one direction an
/// error must never point, and it is invisible without measuring pixels.
///
/// Each series keeps its **own full-scale** — a day's result and a month's
/// running total differ by an order of magnitude, and one magnitude scale would
/// flatten the bars into the axis. What they share is the zero line and the
/// symmetry about it, which is what [of] computes across all of them at once.
class TrackRecordChartScale {
  const TrackRecordChartScale._(this.zeroY, this._pxPerUnit);

  /// Pixels from the top to the zero line.
  final double zeroY;

  /// Pixels per **normalised** unit — a value divided by its own series' peak,
  /// so each series spans at most [-1, 1]. Identical in both directions, which
  /// is the whole point.
  final double _pxPerUnit;

  /// Build a scale that fits every series and is symmetric about zero.
  ///
  /// Zero is not pinned to the middle: a book that never lost should not spend
  /// half the chart on empty space below the axis. It is placed where the
  /// normalised extremes put it, which keeps the pixels-per-unit equal on both
  /// sides for free — that equality is exactly what pinning or clamping it
  /// would break, so neither is done.
  factory TrackRecordChartScale.of(double height, List<List<double>> series) {
    var hi = 0.0;
    var lo = 0.0;
    for (final s in series) {
      final peak = s.fold<double>(0.0, (a, v) => math.max(a, v.abs()));
      if (peak <= 0) continue;
      for (final v in s) {
        final n = v / peak;
        hi = math.max(hi, n);
        lo = math.min(lo, n);
      }
    }
    final span = hi - lo;
    if (span <= 0) return TrackRecordChartScale._(height / 2, 0);
    // Inset so a full-scale value has a pixel of air rather than sitting on
    // the frame — applied to the span, so it cannot break the symmetry.
    final usable = height - 4;
    return TrackRecordChartScale._(2 + usable * (hi / span), usable / span);
  }

  /// The y for [value], normalised against its own [series]' peak.
  double y(double value, List<double> series) {
    final peak = series.fold<double>(0.0, (a, v) => math.max(a, v.abs()));
    if (peak <= 0 || _pxPerUnit <= 0) return zeroY;
    return zeroY - (value / peak) * _pxPerUnit;
  }
}

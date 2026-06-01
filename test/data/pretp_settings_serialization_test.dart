/// Tests for PretpSettings JSON serialization — specifically the
/// ``threshold_pct`` field that drives the per-user "close at 0.3% vs
/// 0.5%" pre-TP dial (2026-06-01).
///
/// What we pin:
///   * ``threshold_pct`` round-trips fromJson → toJsonPartial in RAW
///     PERCENT units (0.30 means 0.30%, NOT a 0.003 fraction).  A unit
///     mismatch here would silently send the engine a value its resolver
///     rejects (bounds [0.05, 5.00]) → falls back to default → the dial
///     does nothing.
///   * toJsonPartial omits null fields (partial-update semantics) so a
///     PUT that only changes the threshold doesn't clobber other columns.
///   * grab_fraction + threshold_pct coexist in one partial.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

void main() {
  group('PretpSettings threshold_pct serialization', () {
    test('fromJson reads threshold_pct as raw percent', () {
      final s = PretpSettings.fromJson({'threshold_pct': 0.30});
      // 0.30 means 0.30% — stored verbatim, no /100 or *100 scaling.
      expect(s.thresholdPct, 0.30);
    });

    test('toJsonPartial emits threshold_pct verbatim', () {
      const s = PretpSettings(thresholdPct: 0.50);
      final j = s.toJsonPartial();
      expect(j['threshold_pct'], 0.50);
    });

    test('round-trips threshold_pct without drift', () {
      const original = PretpSettings(thresholdPct: 0.35);
      final restored = PretpSettings.fromJson(original.toJsonPartial());
      expect(restored.thresholdPct, 0.35);
    });

    test('null threshold_pct is omitted from partial (no clobber)', () {
      const s = PretpSettings(grabFraction: 0.50);
      final j = s.toJsonPartial();
      expect(j.containsKey('threshold_pct'), isFalse);
      expect(j['grab_fraction'], 0.50);
    });

    test('threshold + grab fraction coexist in one partial', () {
      const s = PretpSettings(thresholdPct: 0.40, grabFraction: 0.70);
      final j = s.toJsonPartial();
      expect(j['threshold_pct'], 0.40);
      expect(j['grab_fraction'], 0.70);
    });
  });
}

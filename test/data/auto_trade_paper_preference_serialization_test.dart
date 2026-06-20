/// Tests for the PAPER eligibility triple on AutoTradeSettings —
/// ``paper_symbol_preference`` / ``paper_path_preference`` /
/// ``paper_regime_preference`` (2026-06-20, per-user paper books).
///
/// What we pin:
///   * The paper triple round-trips fromJson → toJsonPartial under the
///     same tri-state contract as the live triple (list / [] / null), and
///     the ``…Set`` flag gates inclusion in the partial.
///   * Paper and live triples are INDEPENDENT — setting one in a partial
///     must not emit the other (so a paper-only save can't clobber the
///     user's live filters, and vice-versa).
///   * A GET payload carrying paper keys hydrates the ``…Set`` flags so a
///     subsequent copy-and-PUT doesn't strip them by accident.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

void main() {
  group('AutoTradeSettings paper eligibility serialization', () {
    test('toJsonPartial emits paper keys only when the Set flag is true', () {
      const s = AutoTradeSettings(
        paperSymbolPreference: ['BTCUSDT', 'ETHUSDT'],
        paperSymbolPreferenceSet: true,
        paperPathPreference: ['DIVERGENCE_CONTINUATION'],
        paperPathPreferenceSet: true,
        paperRegimePreference: ['TRENDING'],
        paperRegimePreferenceSet: true,
      );
      final j = s.toJsonPartial();
      expect(j['paper_symbol_preference'], ['BTCUSDT', 'ETHUSDT']);
      expect(j['paper_path_preference'], ['DIVERGENCE_CONTINUATION']);
      expect(j['paper_regime_preference'], ['TRENDING']);
    });

    test('unset paper fields are omitted (no clobber)', () {
      // Only the live path is being changed — none of the paper keys (nor
      // the other live keys) should appear in the partial.
      const s = AutoTradeSettings(
        pathPreference: ['MA_CROSS'],
        pathPreferenceSet: true,
      );
      final j = s.toJsonPartial();
      expect(j['path_preference'], ['MA_CROSS']);
      expect(j.containsKey('paper_symbol_preference'), isFalse);
      expect(j.containsKey('paper_path_preference'), isFalse);
      expect(j.containsKey('paper_regime_preference'), isFalse);
    });

    test('paper and live triples are independent in one partial', () {
      const s = AutoTradeSettings(
        pathPreference: ['MOMENTUM_BREAKOUT'],
        pathPreferenceSet: true,
        paperPathPreference: ['DIVERGENCE_CONTINUATION'],
        paperPathPreferenceSet: true,
      );
      final j = s.toJsonPartial();
      expect(j['path_preference'], ['MOMENTUM_BREAKOUT']);
      expect(j['paper_path_preference'], ['DIVERGENCE_CONTINUATION']);
    });

    test('block-all ([]) and reset (null) survive the round-trip', () {
      const blockAll = AutoTradeSettings(
        paperSymbolPreference: [],
        paperSymbolPreferenceSet: true,
      );
      expect(blockAll.toJsonPartial()['paper_symbol_preference'], <String>[]);

      const reset = AutoTradeSettings(
        paperSymbolPreference: null,
        paperSymbolPreferenceSet: true,
      );
      final rj = reset.toJsonPartial();
      // Key present (so the engine clears the row) but value null.
      expect(rj.containsKey('paper_symbol_preference'), isTrue);
      expect(rj['paper_symbol_preference'], isNull);
    });

    test('fromJson hydrates paper values and Set flags', () {
      final s = AutoTradeSettings.fromJson({
        'paper_symbol_preference': ['BTCUSDT'],
        'paper_path_preference': ['DIVERGENCE_CONTINUATION'],
        'paper_regime_preference': ['TRENDING_UP', 'TRENDING_DOWN'],
      });
      expect(s.paperSymbolPreference, ['BTCUSDT']);
      expect(s.paperPathPreference, ['DIVERGENCE_CONTINUATION']);
      expect(s.paperRegimePreference, ['TRENDING_UP', 'TRENDING_DOWN']);
      // Present-in-GET → Set flags true so a copy-and-PUT preserves them.
      expect(s.paperSymbolPreferenceSet, isTrue);
      expect(s.paperPathPreferenceSet, isTrue);
      expect(s.paperRegimePreferenceSet, isTrue);
    });

    test('fromJson with a paper key absent leaves it unset', () {
      final s = AutoTradeSettings.fromJson({'mode': 'paper'});
      expect(s.paperSymbolPreference, isNull);
      expect(s.paperSymbolPreferenceSet, isFalse);
      expect(s.paperPathPreferenceSet, isFalse);
      expect(s.paperRegimePreferenceSet, isFalse);
    });
  });
}

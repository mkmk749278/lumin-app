/// Engine vocabulary → reader vocabulary, and what happens to the words this
/// build has never heard of.
///
/// The fallbacks are the point. The engine has 29 setup classes and adds more
/// without asking the app; a map that returns blank for an unknown value would
/// silently hide a real signal's setup or status. Every case below that ends
/// in "…is shown anyway" is guarding that.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/agents/agent_data.dart';
import 'package:lumin/features/signals/signal_language.dart';

void main() {
  group('signalStatusLabel', () {
    test('turns the engine enum into words', () {
      expect(signalStatusLabel('ACTIVE'), 'Active');
      expect(signalStatusLabel('SL_HIT'), 'Stopped out');
      expect(signalStatusLabel('TP1_HIT'), 'Target 1 hit');
      expect(signalStatusLabel('BREAKEVEN_EXIT'), 'Closed at breakeven');
      expect(signalStatusLabel('FULL_TP_HIT'), 'All targets hit');
      expect(signalStatusLabel('INVALIDATED'), 'Setup invalidated');
    });

    test('no mapped status still SHOUTS at the reader', () {
      // The defect being fixed: the card printed the raw enum. Nothing this
      // maps may come back looking like one.
      for (final s in const [
        'ACTIVE',
        'TP1_HIT',
        'TP2_HIT',
        'TP3_HIT',
        'FULL_TP_HIT',
        'SL_HIT',
        'BREAKEVEN_EXIT',
        'INVALIDATED',
        'EXPIRED',
        'CANCELLED',
      ]) {
        expect(signalStatusLabel(s), isNot(contains('_')));
        expect(signalStatusLabel(s), isNot(equals(s)));
      }
    });

    test('a status from a newer engine is shown anyway, sentence-cased', () {
      // Not blank, and not the raw enum: readable, and visibly a status.
      expect(signalStatusLabel('PARTIAL_FILL_TIMEOUT'), 'Partial fill timeout');
      expect(signalStatusLabel('SOMETHING_NEW'), 'Something new');
    });

    test('an empty status does not crash or invent a word', () {
      expect(signalStatusLabel(''), '');
    });
  });

  group('setupTagline', () {
    test('reuses the Agents page copy rather than a second list', () {
      // If these ever diverge, one of the two is a mirror and will drift.
      final reclaimer = kAgents.firstWhere(
        (a) => a.id == 'FAILED_AUCTION_RECLAIM',
      );
      expect(setupTagline('FAILED AUCTION RECLAIM'), reclaimer.tagline);
      expect(setupTagline('FAILED_AUCTION_RECLAIM'), reclaimer.tagline);
    });

    test('matches on the engine\'s spaced form, which is what signals carry',
        () {
      // MockSignal.setupName arrives as "QUIET COMPRESSION BREAK", while the
      // agent ids are underscored. A lookup that only handled one of those
      // would silently describe nothing.
      expect(setupTagline('QUIET COMPRESSION BREAK'), isNotNull);
      expect(setupTagline('quiet compression break'), isNotNull);
    });

    test('returns null for a setup nobody described — never a placeholder',
        () {
      // MOVER_TREND_PULLBACK is most of the delivered book and is NOT in
      // kAgents. An invented description would be worse than none.
      expect(setupTagline('MOVER TREND PULLBACK'), isNull);
      expect(setupTagline('MOVER AVWAP SCALP'), isNull);
      expect(setupTagline(''), isNull);
    });
  });

  group('setupDisplayName', () {
    test('an undescribed setup still reads as words', () {
      expect(setupDisplayName('MOVER_TREND_PULLBACK'), 'Mover trend pullback');
      expect(setupDisplayName('MOVER AVWAP SCALP'), 'Mover avwap scalp');
    });

    test('never returns empty for a non-empty input', () {
      for (final s in const [
        'A',
        'SR_FLIP_RETEST',
        'X_Y_Z',
        'already sentence',
      ]) {
        expect(setupDisplayName(s), isNotEmpty);
      }
    });

    test('empty in, empty out — no placeholder text', () {
      expect(setupDisplayName(''), '');
      expect(setupDisplayName('   '), '');
    });
  });

  // No surface may print the engine's status enum at a subscriber.
  //
  // Four did before 2026-09-21 — the signal card, its detail sheet, the Pulse
  // landing tab and the agent drill-down — so a reader met `BREAKEVEN_EXIT`
  // and `SL_HIT` on the first screen after sign-in. Derived from the files
  // rather than listed, so a fifth surface has to route through the same
  // humaniser instead of quietly reintroducing the raw value.
  group('no surface renders the raw status enum', () {
    const surfaces = [
      'lib/features/signals/signals_page.dart',
      'lib/features/pulse/pulse_page.dart',
      'lib/features/agents/agents_page.dart',
    ];

    test('each interpolates signalStatusLabel, never the bare field', () {
      for (final path in surfaces) {
        final src = File(path).readAsStringSync();
        // Strip comments: they legitimately quote the old broken form.
        final code = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        for (final bad in const [
          r'${sig.status}',
          r'${signal.status}',
        ]) {
          expect(
            code.contains(bad),
            isFalse,
            reason: '\$path interpolates the raw engine enum',
          );
        }
      }
    });

    test('the humaniser is actually imported where status is shown', () {
      for (final path in surfaces) {
        final src = File(path).readAsStringSync();
        if (!src.contains('.status')) continue;
        expect(
          src.contains('signalStatusLabel'),
          isTrue,
          reason: '\$path shows a status without routing it through the map',
        );
      }
    });
  });
}

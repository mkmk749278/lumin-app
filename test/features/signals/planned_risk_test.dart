/// The planned-loss figure on the live-order confirmation (handoff §14).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/signals/planned_risk.dart';

void main() {
  group('plannedLossUsd', () {
    test('a long risking 2% of entry on a 500 USDT position loses 10 USDT', () {
      final loss = plannedLossUsd(entry: 100.0, stopLoss: 98.0, notionalUsd: 500);
      expect(loss, closeTo(10.0, 1e-9));
    });

    test('a short is symmetric — the stop DISTANCE is what is at risk', () {
      // The sheet renders one figure for both directions, so a short whose
      // stop sits the same distance above entry must read identically. If
      // this ever diverged, half the book would show the wrong risk.
      final long = plannedLossUsd(entry: 100.0, stopLoss: 98.0, notionalUsd: 500);
      final short =
          plannedLossUsd(entry: 100.0, stopLoss: 102.0, notionalUsd: 500);
      expect(short, equals(long));
    });

    test('scales linearly with notional — leverage is already inside it', () {
      final small =
          plannedLossUsd(entry: 100.0, stopLoss: 95.0, notionalUsd: 100)!;
      final large =
          plannedLossUsd(entry: 100.0, stopLoss: 95.0, notionalUsd: 1000)!;
      expect(large, closeTo(small * 10, 1e-9));
    });

    test('a sub-dollar mover prices the same as a five-figure one', () {
      // Much of the delivered book is sub-$1. A 3% stop is a 3% stop.
      final cheap =
          plannedLossUsd(entry: 0.0037607, stopLoss: 0.0036479, notionalUsd: 500)!;
      expect(cheap / 500 * 100, closeTo(3.0, 0.01));
    });

    group('refuses rather than returning a misleading zero', () {
      test('a breakeven-ratcheted stop', () {
        // sig.sl == sig.entry after a pre-TP ratchet. On paper that risks
        // nothing; printing zero would tell the reader the trade cannot
        // lose, and slippage and fees mean it can.
        expect(
          plannedLossUsd(entry: 100.0, stopLoss: 100.0, notionalUsd: 500),
          isNull,
        );
      });

      test('a zero or negative entry', () {
        expect(plannedLossUsd(entry: 0, stopLoss: 98, notionalUsd: 500), isNull);
        expect(
            plannedLossUsd(entry: -100, stopLoss: 98, notionalUsd: 500), isNull);
      });

      test('a missing stop', () {
        expect(plannedLossUsd(entry: 100, stopLoss: 0, notionalUsd: 500), isNull);
      });

      test('no position', () {
        expect(plannedLossUsd(entry: 100, stopLoss: 98, notionalUsd: 0), isNull);
      });

      test('non-finite inputs', () {
        expect(
          plannedLossUsd(
              entry: double.nan, stopLoss: 98, notionalUsd: 500),
          isNull,
        );
        expect(
          plannedLossUsd(
              entry: 100, stopLoss: 98, notionalUsd: double.infinity),
          isNull,
        );
      });
    });
  });

  group('plannedLossPct', () {
    test('is the stop distance as a percentage of entry', () {
      expect(plannedLossPct(entry: 100.0, stopLoss: 97.0), closeTo(3.0, 1e-9));
    });

    test('is direction-free like the money figure', () {
      expect(
        plannedLossPct(entry: 100.0, stopLoss: 103.0),
        equals(plannedLossPct(entry: 100.0, stopLoss: 97.0)),
      );
    });

    test('does not need a notional — it is a property of the geometry', () {
      // Which is why it still renders on the server-side path when the
      // engine has not told us the position size.
      expect(plannedLossPct(entry: 0.5, stopLoss: 0.49), isNotNull);
    });

    test('refuses a breakeven stop', () {
      expect(plannedLossPct(entry: 100.0, stopLoss: 100.0), isNull);
    });
  });

  // The wording on the buttons that spend real money.
  //
  // Source-level: these live inside sheets needing Binance keys, per-user
  // settings and an AppConfigScope, none of which this repo can inject into a
  // widget test (see region_gate_test). Copy is what a refactor drops
  // silently, so copy is what is pinned.
  group('a live order never asks for a bare confirmation', () {
    String read(String p) => File(p).readAsStringSync();

    test('the sheet button names the money', () {
      final src = read('lib/features/signals/take_signal_sheet.dart');
      expect(src, contains("'Confirm live order'"));
      expect(
        RegExp(r"'Confirm'").hasMatch(src),
        isFalse,
        reason: 'a bare "Confirm" is back on the screen that places the order',
      );
    });

    test('the signal card CTA says the order is live', () {
      final src = read('lib/features/signals/signals_page.dart');
      expect(src, contains("'Review live order'"));
      expect(src, isNot(contains("'Take signal'")));
    });

    test('the alert CTA says the same thing', () {
      final src = read('lib/features/charts/chart_page.dart');
      expect(src, contains("'Review live order'"));
      expect(src, isNot(contains("'Take trade'")));
    });

    test('the planned loss is on the confirmation, with its caveat', () {
      final src = read('lib/features/signals/take_signal_sheet.dart');
      expect(src, contains('Planned loss if stopped'));
      // A stop is an instruction, not a guarantee. Publishing the figure
      // without saying so is the reassuring-in-the-wrong-direction error.
      expect(src, contains('gap through the stop can cost more'));
    });

    test('both execution paths show it', () {
      // Device-signed and server-side are different branches of the same
      // sheet, and the server-side one is what a connected user actually
      // takes. A figure on one branch only is the seam this repo keeps
      // paying for.
      final src = read('lib/features/signals/take_signal_sheet.dart');
      expect(
        '_plannedLossRow('.allMatches(src).length,
        greaterThanOrEqualTo(3),
        reason: 'expected the definition plus a call in each order card',
      );
    });
  });
}

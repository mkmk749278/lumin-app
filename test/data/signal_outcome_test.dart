// Tests for [SignalOutcome] / [SignalOutcomes] and the placed-row copy
// that used to be a static string.
//
// Owner, 2026-08-31, over screenshots of the Signals tab beside the
// Trade tab: *"why don't we show actually same like signal it's
// outcome, actually what traded in binance ... with that user can
// understand what actually engine produced and what's traded in
// binance"*.
//
// The two objects lived on two tabs and had never been joined.  The
// Signals tab renders the ENGINE's signal and says so in its own
// subtitle.  The Trade tab's only per-signal record was
// [DispatchEvent] — a record of a placement ATTEMPT, with no fill, no
// PnL and no close state — so every placed row asserted "Position is
// open — Lumin manages it from here" in the present tense, forever.
// That is how four such rows came to sit directly beneath "YOUR OPEN
// POSITIONS 0": the card above was engine truth and the rows below
// were copy, each internally right while the page contradicted itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/server_side_execution_models.dart';

DispatchEvent _placed({String signalId = 'sig-A'}) => DispatchEvent(
      eventId: 'evt-1',
      signalId: signalId,
      symbol: 'BTCUSDT',
      direction: 'LONG',
      outcome: 'placed',
      timestamp: DateTime.utc(2026, 8, 31, 12),
      entryPrice: 29000.0,
      totalQty: 0.017,
    );

void main() {
  group('SignalOutcomes.fromJson', () {
    test('indexes by signal id and keeps the window counts', () {
      final o = SignalOutcomes.fromJson({
        'outcomes': [
          {
            'signal_id': 'sig-A',
            'symbol': 'BTCUSDT',
            'direction': 'LONG',
            'status': 'closed',
            'state': 'CLOSED',
            'entry_price_filled': 29005.5,
            'filled_qty': 0.017,
            'realized_pnl_usd': 4.12,
            'close_reason': 'TP1',
            'opened_at': '2026-08-31T08:00:00Z',
            'closed_at': '2026-08-31T10:00:00Z',
            'source': 'auto',
          },
        ],
        'closed_window': 40,
        'closed_truncated': true,
        'events_window': 3,
        'events_truncated': false,
      });
      final row = o['sig-A']!;
      expect(row.isClosed, true);
      expect(row.closeReason, 'TP1');
      expect(row.realizedPnlUsd, 4.12);
      // The fill, not what the signal asked for.  These being different
      // numbers is the entire reason this payload exists.
      expect(row.entryPriceFilled, 29005.5);
      expect(o.closedWindow, 40);
      expect(o.truncated, true);
    });

    test('an absent signal is null, never a manufactured "not traded"', () {
      final o = SignalOutcomes.fromJson({'outcomes': []});
      expect(o['sig-missing'], isNull);
      expect(o.truncated, false);
    });

    test('tolerates a payload with no outcomes key at all', () {
      // An engine that predates the endpoint, or a proxy that ate the
      // body.  Must degrade to "we know nothing", never throw onto the
      // signal feed.
      final o = SignalOutcomes.fromJson(const <String, dynamic>{});
      expect(o.bySignalId, isEmpty);
    });

    test('preference and rejection are different classes', () {
      final o = SignalOutcomes.fromJson({
        'outcomes': [
          {
            'signal_id': 'sig-P',
            'status': 'not_traded',
            'not_traded_class': 'preference',
            'not_traded_reason': 'path_preference',
          },
          {
            'signal_id': 'sig-R',
            'status': 'not_traded',
            'not_traded_class': 'rejected',
            'not_traded_reason': 'OrderRejectedByBinance',
            'binance_code': -2019,
          },
        ],
      });
      expect(o['sig-P']!.declinedByPreference, true);
      expect(o['sig-R']!.declinedByPreference, false);
      expect(o['sig-R']!.binanceCode, -2019);
    });
  });

  group('DispatchEventTranslation.forEvent — the placed row', () {
    test('claims nothing about the position when no outcome is known', () {
      final tx = DispatchEventTranslation.forEvent(_placed());
      expect(tx.headline, 'Placed on Binance');
      // The defect, pinned: the row must not assert an open position
      // from a record that cannot know one.
      expect(tx.action, isNot(contains('Position is open')));
      expect(tx.action, contains('accepted'));
    });

    test('says the position is open only when the engine says it is', () {
      final tx = DispatchEventTranslation.forEvent(
        _placed(),
        outcome: const SignalOutcome(
          signalId: 'sig-A',
          symbol: 'BTCUSDT',
          direction: 'LONG',
          status: 'open',
          state: 'OPEN',
          entryPriceFilled: 29005.5,
        ),
      );
      expect(tx.action, contains('Lumin manages it from here'));
      expect(tx.action, contains('29005.5'));
    });

    test('a closed position reports its exit and realised PnL', () {
      final tx = DispatchEventTranslation.forEvent(
        _placed(),
        outcome: const SignalOutcome(
          signalId: 'sig-A',
          symbol: 'BTCUSDT',
          direction: 'LONG',
          status: 'closed',
          state: 'CLOSED',
          closeReason: 'SL',
          realizedPnlUsd: -6.5,
        ),
      );
      expect(tx.headline, 'Closed on Binance');
      // The engine's token, translated: 2026-09-01.  It used to read
      // "exit SL" — right, and in the engine's vocabulary rather than the
      // reader's.
      expect(tx.action, contains('exit: stop loss'));
      expect(tx.action, contains('-\$6.50'));
      expect(tx.action, isNot(contains('is open')));
    });

    test('the two-hour backstop is named, not printed as a token', () {
      // ``STALE_EXPIRY`` is the reconciler's age ceiling — 39 of 140 matched
      // positions in the 24 Aug – 1 Sep window — and it is the reason a
      // signal can still be running in the feed with nothing left on the
      // account.  Rendered raw it reads as a fault rather than as a rule,
      // which is precisely the confusion this copy exists to end.
      final tx = DispatchEventTranslation.forEvent(
        _placed(),
        outcome: const SignalOutcome(
          signalId: 'sig-A',
          symbol: 'BTCUSDT',
          direction: 'LONG',
          status: 'closed',
          state: 'CLOSED',
          closeReason: 'STALE_EXPIRY',
          realizedPnlUsd: 0.12,
        ),
      );
      expect(tx.action, contains('2-hour position limit'));
      expect(tx.action, isNot(contains('STALE_EXPIRY')));
    });

    test('an untranslated reason falls through to itself', () {
      // A reason nobody has worded yet is still information.  Collapsing it
      // to a generic "closed" is how the NEXT new close reason becomes
      // invisible — the deny-list failure, at the copy layer.
      final tx = DispatchEventTranslation.forEvent(
        _placed(),
        outcome: const SignalOutcome(
          signalId: 'sig-A',
          symbol: 'BTCUSDT',
          direction: 'LONG',
          status: 'closed',
          state: 'CLOSED',
          closeReason: 'SOME_NEW_REASON',
        ),
      );
      expect(tx.action, contains('SOME_NEW_REASON'));
    });
  });

  group('DispatchEventTranslation.forEvent — the skipped row', () {
    test('a preference decline is not worded or coloured as a failure', () {
      final e = DispatchEvent(
        eventId: 'evt-2',
        signalId: 'sig-S',
        symbol: 'SOLUSDT',
        direction: 'LONG',
        outcome: 'skipped',
        timestamp: DateTime.utc(2026, 8, 31, 12),
        entryPrice: 140.0,
        totalQty: 0.0,
        rejectDetail: 'RANGE_FADE is not in your auto-trade setup list.',
        skipReason: 'path_preference',
      );
      expect(e.isSkipped, true);
      final tx = DispatchEventTranslation.forEvent(e);
      expect(tx.headline, 'Not auto-traded');
      expect(tx.action, contains('RANGE_FADE'));
      // Nothing failed — the user's own filter did exactly what they set
      // it to do, so this must not carry a user-action or system chip.
      expect(tx.severity, DispatchEventSeverity.transient);
    });
  });
}

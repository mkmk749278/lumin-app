// The contract between the engine's ``/api/auto-trade/positions`` payload and
// the Trade tab's position card, and between ``/api/auto-trade/close`` and
// what the Close button tells the user.
//
// Owner, 2026-09-01, holding the Binance app beside the Trade tab: *"there we
// have to show exactly how live open traded position shows in binance, and
// also user can close that trade from our app to without visiting binance"*.
//
// Before this the row carried the entry price and the geometry — everything
// the engine INTENDED — and nothing about what the position is worth now, so
// the user left the app to find out and left it again to act.
//
// The cases below are the ones that would render a WRONG number rather than
// no number, which is why they are worth a test each: a null mark defaulting
// to zero, an older engine's missing keys, and the copy the app shows after a
// close resolves.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/server_side_execution_models.dart';

void main() {
  group('ServerSidePosition — the live columns', () {
    test('parses a marked position', () {
      final p = ServerSidePosition.fromJson({
        'signal_id': 'sig-1',
        'symbol': 'BTCUSDT',
        'side': 'LONG',
        'state': 'OPEN',
        'entry_price_target': 29000.0,
        'entry_price_filled': 29005.5,
        'sl_price': 28500.0,
        'tp1_price': 29500.0,
        'total_qty': 0.017,
        'filled_qty': 0.017,
        'realized_pnl_total': 0.0,
        'pretp_fired': false,
        'open_qty': 0.017,
        'mark_price': 29180.0,
        'notional': 496.06,
        'unrealized_pnl': 2.9665,
        'unrealized_pnl_pct': 0.6017,
        'closeable': true,
        'marks_age_sec': 4.0,
      });
      expect(p.markPrice, 29180.0);
      expect(p.unrealizedPnlPct, 0.6017);
      expect(p.closeable, isTrue);
      expect(p.marksAgeSec, 4.0);
      // The price the position is actually working against.
      expect(p.entryPrice, 29005.5);
    });

    test('an unmarked symbol stays null and never becomes zero', () {
      // A dash means "the engine is not marking this symbol", which is a real
      // state with its own cause.  0.0 would render as a position worth
      // nothing — a claim nobody made, and indistinguishable on screen from a
      // position that really is flat.
      final p = ServerSidePosition.fromJson({
        'signal_id': 'sig-1',
        'symbol': 'BTCUSDT',
        'side': 'LONG',
        'state': 'OPEN',
        'entry_price_filled': 100.0,
        'total_qty': 1.0,
        'mark_price': null,
        'unrealized_pnl': null,
        'unrealized_pnl_pct': null,
      });
      expect(p.markPrice, isNull);
      expect(p.unrealizedPnl, isNull);
      expect(p.unrealizedPnlPct, isNull);
      expect(p.notional, isNull);
    });

    test('an engine that predates these fields sends none of them', () {
      // The app ships ahead of a deploy often enough that this is the normal
      // case for a few minutes, not an edge one.
      final p = ServerSidePosition.fromJson({
        'signal_id': 'sig-1',
        'symbol': 'BTCUSDT',
        'side': 'SHORT',
        'state': 'OPEN',
        'entry_price_target': 101.6,
        'total_qty': 0.09,
      });
      expect(p.markPrice, isNull);
      expect(p.marksAgeSec, isNull);
      // False rather than true: the button disappears, and the user can still
      // close on Binance.  Offering it on a position the engine will refuse
      // is the worse half.
      expect(p.closeable, isFalse);
      // No filled price yet — fall back to the target rather than 0.
      expect(p.entryPrice, 101.6);
    });
  });

  group('ClosePositionResult', () {
    test('a close says the signal is still live', () {
      // The single thing a user is most likely to get wrong here: they are
      // exiting their own trade, not cancelling the signal, and the ACTIVE
      // signal card is on screen right beside this answer.
      final r = ClosePositionResult.fromJson({
        'outcome': 'closed',
        'signal_id': 'sig-1',
        'symbol': 'BTCUSDT',
        'signal_still_active': true,
        'detail': 'Position closed at market. The signal stays in the feed.',
      });
      expect(r.isClosed, isTrue);
      expect(r.signalStillActive, isTrue);
      expect(r.message, contains('stays in the feed'));
    });

    test('a refusal surfaces the engine reason, not a generic failure', () {
      final r = ClosePositionResult.fromJson({
        'outcome': 'rejected',
        'reject_class': 'PositionAlreadyClosed',
        'reject_detail': 'This position already closed (STALE_EXPIRY).',
      });
      expect(r.isClosed, isFalse);
      expect(r.message, contains('STALE_EXPIRY'));
    });

    test('queued is not a failure', () {
      // The engine has not answered; the close is in flight.  Rendering this
      // as a failure invites a second tap, and a second close on a flat
      // position is how somebody opens the opposite side by accident.
      final r = ClosePositionResult.fromJson({
        'outcome': 'queued',
        'detail': 'Your close is queued — do not tap again.',
      });
      expect(r.isQueued, isTrue);
      expect(r.isClosed, isFalse);
      expect(r.message, contains('do not tap again'));
    });

    test('a malformed answer is a refusal, never a silent success', () {
      final r = ClosePositionResult.fromJson(<String, dynamic>{});
      expect(r.isClosed, isFalse);
      expect(r.message, 'Could not close the position.');
    });
  });
}

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
      // The price the position is actually working against — the engine's
      // fill here, because this payload carries no exchange entry.
      expect(p.effectiveEntry, 29005.5);
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
      expect(p.effectiveEntry, 101.6);
      // And nothing from the exchange at all.
      expect(p.entryPrice, isNull);
      expect(p.liquidationPrice, isNull);
      expect(p.qtySource, '');
      expect(p.divergence, isNull);
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

  _exchangeColumns();
}

/// The exchange's own columns, and the envelope they arrive in.
///
/// Added 2026-09-01 with the engine change that stopped inferring a position
/// and started reading the one Binance was already describing: the
/// `ACCOUNT_UPDATE` push (size, entry, its own unrealized PnL) and the
/// `positionRisk` row (liquidation price, leverage), both of which were
/// arriving at the engine and being discarded.
void _exchangeColumns() {
  group('ServerSidePosition — the exchange-sourced columns', () {
    ServerSidePosition parse(Map<String, dynamic> extra) =>
        ServerSidePosition.fromJson({
          'signal_id': 'sig-1',
          'symbol': 'BTCUSDT',
          'side': 'LONG',
          'state': 'OPEN',
          'entry_price_filled': 100.0,
          'total_qty': 2.0,
          ...extra,
        });

    test('the exchange answer wins and the row says so', () {
      final p = parse({
        'entry_price': 101.5,
        'open_qty': 1.4,
        'qty_source': 'exchange',
        'entry_source': 'exchange',
        'liquidation_price': 82.5,
        'leverage': 10.0,
        'margin_type': 'cross',
      });
      // The engine's document says the fill was 100.0; Binance says 101.5.
      expect(p.effectiveEntry, 101.5);
      expect(p.entrySource, 'exchange');
      expect(p.qtySource, 'exchange');
      expect(p.liquidationPrice, 82.5);
      expect(p.leverage, 10.0);
      expect(p.marginType, 'cross');
    });

    test('a missing liquidation price stays null, never zero', () {
      // `0.0` beside the word liquidation reads as "you cannot be
      // liquidated", which is a claim nobody made.
      final p = parse({});
      expect(p.liquidationPrice, isNull);
      expect(p.leverage, isNull);
      expect(p.exchangeUnrealizedPnl, isNull);
    });

    test('the divergence the owner saw is carried as a named state', () {
      final p = parse({
        'divergence': 'exchange_flat',
        // Plain digits: this project's Dart language version does not enable
        // the `digit-separators` feature, so `1_700_000_000.0` is a compile
        // error rather than a readability nicety.
        'exchange_flat_since_epoch': 1700000000.0,
        'closeable': false,
      });
      expect(p.isExchangeFlat, isTrue);
      expect(p.exchangeFlatSinceEpoch, 1700000000.0);
      // A close against a position Binance says is flat is a -2022.
      expect(p.closeable, isFalse);
    });

    test('agreement is not a divergence', () {
      expect(parse({'divergence': null}).isExchangeFlat, isFalse);
    });
  });

  group('ServerSidePositions — the envelope', () {
    test('parses rows, unmanaged positions and both clocks', () {
      final b = ServerSidePositions.fromJson({
        'positions': [
          {'signal_id': 'sig-1', 'symbol': 'BTCUSDT', 'side': 'LONG'},
        ],
        'unmanaged': [
          {
            'symbol': 'DOGEUSDT',
            'side': 'SHORT',
            'open_qty': 250.0,
            'entry_price': 0.0851,
            'liquidation_price': 0.0993,
          },
        ],
        'marks_age_sec': 4.0,
        'exchange_state': 'reporting',
        'exchange_age_sec': 3.0,
      });
      expect(b.positions, hasLength(1));
      expect(b.unmanaged, hasLength(1));
      expect(b.unmanaged.first.symbol, 'DOGEUSDT');
      expect(b.unmanaged.first.liquidationPrice, 0.0993);
      // Two clocks, kept apart: a single "as of" over two sources is a
      // freshness claim neither of them made.
      expect(b.marksAgeSec, 4.0);
      expect(b.exchangeAgeSec, 3.0);
      expect(b.exchangeIsReporting, isTrue);
    });

    test('an engine that says nothing is unavailable, never reporting', () {
      // The single most dangerous default here. `reporting` would let the
      // card assert "Binance closed this" on no evidence at all, and tell a
      // user with an open position that their account is flat.
      final b = ServerSidePositions.fromJson(<String, dynamic>{});
      expect(b.exchangeState, 'unavailable');
      expect(b.exchangeIsReporting, isFalse);
      expect(b.positions, isEmpty);
      expect(b.unmanaged, isEmpty);
    });

    test('a malformed body degrades to empty rather than throwing', () {
      final b = ServerSidePositions.fromJson({
        'positions': 'not a list',
        'unmanaged': 42,
      });
      expect(b.positions, isEmpty);
      expect(b.unmanaged, isEmpty);
    });
  });
}

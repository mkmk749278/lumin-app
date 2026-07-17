// Tests for [DispatchEvent.fromJson] + [DispatchEventTranslation.forEvent].
//
// Pins the contract between the engine's
// ``/api/auto-trade/recent-events`` JSON shape and what the Trade-
// tab Recent Activity card renders.  Most importantly: the
// translation layer is the user-facing surface — getting the
// wording wrong on ``-2019 'Margin is insufficient'`` defeats the
// whole purpose of the card (the user has to know "top up your
// Futures wallet" without us telling them what -2019 means).
//
// Test cases follow the structure of the translation switch in
// ``lib/data/server_side_execution_models.dart`` so a future
// addition to the switch shows up here as an obviously-missing
// test rather than a silent fall-through to the generic copy.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/server_side_execution_models.dart';

void main() {
  group('DispatchEvent.fromJson', () {
    test('parses a placed event with full payload', () {
      final e = DispatchEvent.fromJson({
        'event_id': 'evt-1',
        'signal_id': 'sig-A',
        'symbol': 'BTCUSDT',
        'direction': 'LONG',
        'outcome': 'placed',
        'timestamp': '2026-05-20T04:25:00Z',
        'entry_price': 29000.0,
        'total_qty': 0.017,
        'reject_class': null,
        'reject_detail': null,
        'reject_binance_code': null,
        'reject_binance_msg': null,
      });
      expect(e.eventId, 'evt-1');
      expect(e.symbol, 'BTCUSDT');
      expect(e.isPlaced, true);
      expect(e.isRejected, false);
      expect(e.totalQty, 0.017);
      expect(e.rejectBinanceCode, isNull);
    });

    test('parses a rejected event with Binance code/msg', () {
      final e = DispatchEvent.fromJson({
        'event_id': 'evt-2',
        'signal_id': 'sig-B',
        'symbol': 'PROMUSDT',
        'direction': 'SHORT',
        'outcome': 'rejected',
        'timestamp': '2026-05-20T04:25:00Z',
        'entry_price': 0.1278,
        'total_qty': 0.0,
        'reject_class': 'OrderRejectedByBinance',
        'reject_detail': 'long string',
        'reject_binance_code': -2019,
        'reject_binance_msg': 'Margin is insufficient.',
      });
      expect(e.isRejected, true);
      expect(e.rejectBinanceCode, -2019);
      expect(e.rejectBinanceMsg, 'Margin is insufficient.');
    });

    test('tolerates missing fields with safe defaults', () {
      // Server occasionally returns partial docs (PR #461's
      // tolerant deserialisation).  The Dart side must mirror
      // that — never throw on a missing optional.
      final e = DispatchEvent.fromJson({});
      expect(e.eventId, '');
      expect(e.symbol, '');
      expect(e.outcome, '');
      expect(e.entryPrice, 0.0);
      expect(e.rejectBinanceCode, isNull);
    });
  });

  group('DispatchEventTranslation.forEvent', () {
    DispatchEvent _rejected({
      int? code,
      String? msg,
      String rejectClass = 'OrderRejectedByBinance',
      String detail = 'engine-side diagnostic',
    }) =>
        DispatchEvent(
          eventId: 'x',
          signalId: 'x',
          symbol: 'BTCUSDT',
          direction: 'LONG',
          outcome: 'rejected',
          timestamp: DateTime.utc(2026, 5, 20),
          entryPrice: 29000.0,
          totalQty: 0.0,
          rejectClass: rejectClass,
          rejectDetail: detail,
          rejectBinanceCode: code,
          rejectBinanceMsg: msg,
        );

    test('placed → success severity + "Placed on Binance" headline', () {
      final e = DispatchEvent(
        eventId: 'x', signalId: 'x', symbol: 'BTCUSDT', direction: 'LONG',
        outcome: 'placed', timestamp: DateTime.utc(2026, 5, 20),
        entryPrice: 29000.0, totalQty: 0.017,
      );
      final tx = DispatchEventTranslation.forEvent(e);
      expect(tx.severity, DispatchEventSeverity.success);
      expect(tx.headline, 'Placed on Binance');
    });

    test('-2019 Margin insufficient → userAction + actionable copy', () {
      final tx = DispatchEventTranslation.forEvent(
        _rejected(code: -2019, msg: 'Margin is insufficient.'),
      );
      expect(tx.severity, DispatchEventSeverity.userAction);
      expect(tx.headline, contains('margin'));
      expect(tx.action, contains('Futures wallet'));
    });

    test('-2010 Insufficient balance → userAction', () {
      final tx = DispatchEventTranslation.forEvent(
        _rejected(code: -2010, msg: 'Account has insufficient balance.'),
      );
      expect(tx.severity, DispatchEventSeverity.userAction);
      expect(tx.headline, contains('balance'));
    });

    test('-2014/-2015 API key issues → userAction with IP-whitelist guidance',
        () {
      for (final c in [-2014, -2015]) {
        final tx = DispatchEventTranslation.forEvent(_rejected(code: c));
        expect(tx.severity, DispatchEventSeverity.userAction);
        expect(tx.action.toLowerCase(), contains('whitelist'));
      }
    });

    test('-4131/-1013 PERCENT_PRICE → transient', () {
      for (final c in [-4131, -1013]) {
        final tx = DispatchEventTranslation.forEvent(_rejected(code: c));
        expect(tx.severity, DispatchEventSeverity.transient);
        expect(tx.action.toLowerCase(), contains('retry'));
      }
    });

    test('-1111/-4014 precision → system (engine bug)', () {
      for (final c in [-1111, -4014]) {
        final tx = DispatchEventTranslation.forEvent(_rejected(code: c));
        expect(tx.severity, DispatchEventSeverity.system);
        expect(tx.headline.toLowerCase(), contains('precision'));
      }
    });

    test('-4164 min notional → userAction', () {
      final tx = DispatchEventTranslation.forEvent(_rejected(code: -4164));
      expect(tx.severity, DispatchEventSeverity.userAction);
      expect(tx.action, contains('Connect page'));
    });

    test('unknown Binance code → transient with raw msg surfaced', () {
      final tx = DispatchEventTranslation.forEvent(
        _rejected(code: -9999, msg: 'Something brand new.'),
      );
      expect(tx.severity, DispatchEventSeverity.transient);
      expect(tx.headline, contains('-9999'));
      expect(tx.action, contains('Something brand new.'));
    });

    test('SymbolNotInUserPreference → userAction with picker hint', () {
      final tx = DispatchEventTranslation.forEvent(
        _rejected(rejectClass: 'SymbolNotInUserPreference'),
      );
      expect(tx.severity, DispatchEventSeverity.userAction);
      expect(tx.action, contains('Symbol Preference'));
    });

    test('UserNotConnectedError → userAction with Connect page hint', () {
      final tx = DispatchEventTranslation.forEvent(
        _rejected(rejectClass: 'UserNotConnectedError'),
      );
      expect(tx.severity, DispatchEventSeverity.userAction);
      expect(tx.action, contains('Connect page'));
    });

    test('RateLimitExceededError → transient', () {
      final tx = DispatchEventTranslation.forEvent(
        _rejected(rejectClass: 'RateLimitExceededError'),
      );
      expect(tx.severity, DispatchEventSeverity.transient);
    });

    test('PositionCapExceededError → transient', () {
      final tx = DispatchEventTranslation.forEvent(
        _rejected(rejectClass: 'PositionCapExceededError'),
      );
      expect(tx.severity, DispatchEventSeverity.transient);
    });

    test('GlobalKillSwitchActiveError → system, consumer copy only', () {
      // 2026-07-17: the old copy said "global kill switch" — engine
      // vocabulary that reads as alarming jargon to a subscriber.  Pin
      // the consumer phrasing instead.
      final tx = DispatchEventTranslation.forEvent(
        _rejected(rejectClass: 'GlobalKillSwitchActiveError'),
      );
      expect(tx.severity, DispatchEventSeverity.system);
      expect(tx.action.toLowerCase(), isNot(contains('kill switch')));
      expect(tx.action, contains('paused for everyone'));
    });

    test('GlobalKillSwitchEngaged (take-path class name) maps the same', () {
      final tx = DispatchEventTranslation.forEvent(
        _rejected(rejectClass: 'GlobalKillSwitchEngaged'),
      );
      expect(tx.severity, DispatchEventSeverity.system);
      expect(tx.action.toLowerCase(), isNot(contains('kill switch')));
    });

    test('OrderRejectedByBinance without a numeric code → falls back to detail',
        () {
      // Edge case: Binance returned an error without a parseable
      // numeric code (e.g. HTML error page from a CDN intercept).
      // The detail/msg still needs to surface.
      final tx = DispatchEventTranslation.forEvent(_rejected(
        rejectClass: 'OrderRejectedByBinance',
        msg: 'Service unavailable.',
      ));
      expect(tx.severity, DispatchEventSeverity.transient);
      expect(tx.action, contains('Service unavailable.'));
    });

    test('Unknown reject class → generic headline, class name never leaks',
        () {
      // 2026-07-17: the old default branch rendered the raw Python
      // exception class name as the headline.  Now: generic headline +
      // sanitized detail only.
      final tx = DispatchEventTranslation.forEvent(_rejected(
        rejectClass: 'SomeNewExceptionEngineSideDoesntKnowAbout',
      ));
      expect(tx.severity, DispatchEventSeverity.system);
      expect(tx.headline, 'Trade not placed');
      expect(tx.headline, isNot(contains('SomeNew')));
      expect(tx.action, isNot(contains('SomeNew')));
    });

    test('forEvent and forReject produce identical copy for the same reject',
        () {
      final e = _rejected(
        rejectClass: 'OrderRejectedByBinance',
        code: -4411,
        msg: 'Please sign TradFi-Perps agreement contract fapi.',
      );
      final a = DispatchEventTranslation.forEvent(e);
      final b = DispatchEventTranslation.forReject(
        rejectClass: e.rejectClass,
        rejectDetail: e.rejectDetail,
        binanceCode: e.rejectBinanceCode,
        binanceMsg: e.rejectBinanceMsg,
        symbol: e.symbol,
      );
      expect(a.headline, b.headline);
      expect(a.action, b.action);
      expect(a.severity, b.severity);
    });

    test('-4411 → Futures-agreement guidance (the 2026-07-17 subscriber '
        'failure)', () {
      final tx = DispatchEventTranslation.forEvent(_rejected(
        rejectClass: 'OrderRejectedByBinance',
        code: -4411,
        msg: 'Please sign TradFi-Perps agreement contract fapi.',
      ));
      expect(tx.severity, DispatchEventSeverity.userAction);
      expect(tx.headline, contains('Futures agreement'));
      expect(tx.action.toLowerCase(), contains('accept the agreement'));
    });

    test('UserAutoDisabled never surfaces the UID-bearing detail', () {
      const uid = 'RYhAWEcwsNXU2gGROCpbFD95svc2';
      final tx = DispatchEventTranslation.forEvent(_rejected(
        rejectClass: 'UserAutoDisabled',
        detail: 'user $uid is auto-disabled',
      ));
      expect(tx.severity, DispatchEventSeverity.userAction);
      expect(tx.headline, isNot(contains(uid)));
      expect(tx.action, isNot(contains(uid)));
      expect(tx.action.toLowerCase(), contains('support'));
    });
  });
}

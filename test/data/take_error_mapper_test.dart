/// Take-flow error mapping (2026-07-17) — the guard against raw engine
/// strings reaching a subscriber's screen.  The regression that wrote
/// these tests: the take sheet rendered "user RYhAWEcwsNXU2gGROCpbFD95svc2
/// is auto-disabled" and "order placement failed (phase=entry):
/// code=BINANCE_HTTP_ERROR …" verbatim.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/server_side_execution_models.dart';
import 'package:lumin/data/take_error_mapper.dart';

const _uid = 'RYhAWEcwsNXU2gGROCpbFD95svc2';

TakeSignalResult _rejected({
  String? rejectClass,
  String? rejectDetail,
  int? binanceCode,
  String? binanceMsg,
}) =>
    TakeSignalResult(
      outcome: 'rejected',
      rejectClass: rejectClass,
      rejectDetail: rejectDetail,
      rejectBinanceCode: binanceCode,
      rejectBinanceMsg: binanceMsg,
    );

void main() {
  group('sanitizeEngineDetail', () {
    test('replaces the auto-disabled UID string', () {
      final out = DispatchEventTranslation.sanitizeEngineDetail(
          'user $_uid is auto-disabled');
      expect(out, isNotNull);
      expect(out!, isNot(contains(_uid)));
      expect(out.toLowerCase(), contains('switched off'));
    });

    test('handles the circuit-breaker variant without leaking', () {
      final out = DispatchEventTranslation.sanitizeEngineDetail(
          'user $_uid auto-disabled by circuit breaker '
          '(>3 rejections in 300s window)');
      expect(out ?? '', isNot(contains(_uid)));
      expect((out ?? '').toLowerCase(), isNot(contains('circuit breaker')));
    });

    test('drops internal-looking residue entirely', () {
      expect(
        DispatchEventTranslation.sanitizeEngineDetail(
            'global kill switch engaged — orders refused for all users'),
        isNull,
      );
      expect(
        DispatchEventTranslation.sanitizeEngineDetail(
            'order placement failed (phase=entry): code=BINANCE_HTTP_ERROR '
            "status=400 message=Binance returned 400"),
        isNull,
      );
    });

    test('passes benign copy through', () {
      expect(
        DispatchEventTranslation.sanitizeEngineDetail(
            'This signal already closed (SL_HIT).'),
        'This signal already closed (SL_HIT).',
      );
    });

    test('null/empty → null', () {
      expect(DispatchEventTranslation.sanitizeEngineDetail(null), isNull);
      expect(DispatchEventTranslation.sanitizeEngineDetail('  '), isNull);
    });
  });

  group('translateTakeRejection', () {
    test('every known engine reject_class maps without leaking', () {
      const classes = [
        'SignalClosed',
        'TakeRequestStale',
        'NotGloballyEnabledError',
        'GlobalKillSwitchEngaged',
        'GlobalKillSwitchActiveError',
        'UserAutoDisabled',
        'PositionCapExceededError',
        'OrderRejectedByBinance',
        'OrderPlacementKeyError',
        'OrderPlacementUnreachable',
        'OrderPlacementError',
        'RateLimitExceededError',
        'NotionalTooSmall',
      ];
      for (final c in classes) {
        final m = translateTakeRejection(_rejected(
          rejectClass: c,
          rejectDetail: 'user $_uid is auto-disabled',
        ));
        expect(m.headline, isNot(contains(c)),
            reason: 'class name must never be the headline ($c)');
        expect(m.combined, isNot(contains(_uid)),
            reason: 'UID must never surface ($c)');
        expect(m.combined.toLowerCase(), isNot(contains('kill switch')),
            reason: 'engine vocabulary must never surface ($c)');
      }
    });

    test('unknown class falls back without leaking the class name', () {
      final m = translateTakeRejection(_rejected(
        rejectClass: 'SomeFutureExoticError',
        rejectDetail: 'user $_uid is auto-disabled',
      ));
      expect(m.headline, 'Trade not placed');
      expect(m.combined, isNot(contains('SomeFutureExoticError')));
      expect(m.combined, isNot(contains(_uid)));
    });

    test('-4411 gets the Futures-agreement guidance', () {
      final m = translateTakeRejection(_rejected(
        rejectClass: 'OrderRejectedByBinance',
        binanceCode: -4411,
        binanceMsg: 'Please sign TradFi-Perps agreement contract fapi.',
      ));
      expect(m.headline, contains('Futures agreement'));
      expect(m.action.toLowerCase(), contains('accept the agreement'));
      expect(m.combined, isNot(contains('TradFi')));
    });

    test('-2019 keeps the insufficient-margin guidance', () {
      final m = translateTakeRejection(_rejected(
        rejectClass: 'OrderRejectedByBinance',
        binanceCode: -2019,
        binanceMsg: 'Margin is insufficient.',
      ));
      expect(m.headline, 'Insufficient margin');
    });
  });

  group('translateTakeHttpError', () {
    test('mapped statuses never render the raw detail', () {
      const raw = 'user $_uid is auto-disabled';
      for (final status in [401, 403, 409, 503, 0]) {
        final m = translateTakeHttpError(status, raw);
        expect(m.combined, isNot(contains(_uid)), reason: 'status $status');
        expect(m.headline, isNotEmpty);
      }
    });

    test('403 routes to the subscription upsell', () {
      final m = translateTakeHttpError(403, 'whatever');
      expect(m.combined, contains('Subscription'));
    });

    test('unmapped status sanitizes the detail', () {
      final m = translateTakeHttpError(
          418, 'order placement failed (phase=entry): code=X status=400');
      expect(m.combined, isNot(contains('phase=entry')));
    });
  });

  test('translateTakeUnexpected is generic and safe', () {
    final m = translateTakeUnexpected();
    expect(m.headline, isNotEmpty);
    expect(m.combined, isNot(contains('Exception')));
  });
}

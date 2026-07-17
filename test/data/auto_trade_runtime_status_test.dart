// Serialization pins for AutoTradeRuntimeStatus (2026-07-17 truth
// fields) and TakeSignalResult (server-side manual take).
//
// The critical semantics under test:
//  * null vs [] on path/regime preference — "no preference" and the
//    explicit block-all empty set are DIFFERENT states and must survive
//    a JSON round-trip distinctly;
//  * old-engine payloads (keys absent) parse to null/defaults so the
//    armed card hides the new rows instead of lying red or green;
//  * TakeSignalResult outcome mapping (placed / rejected / queued) and
//    the reject fields mirroring DispatchEvent's.

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/server_side_execution_models.dart';

void main() {
  group('AutoTradeRuntimeStatus.fromJson — 2026-07-17 truth fields', () {
    test('parses a full new-engine payload', () {
      final status = AutoTradeRuntimeStatus.fromJson(const {
        'auto_trade_globally_enabled': true,
        'auto_trade_user_disabled': false,
        'binance_key_connected': true,
        'user_mode': 'live',
        'allowed_symbols': ['BTCUSDT', 'ETHUSDT'],
        'effective_allowed_symbols': ['BTCUSDT'],
        'allowed_paths': ['SR_FLIP_RETEST', 'MOVER_TREND_PULLBACK'],
        'regime_options': ['TRENDING', 'RANGING', 'CHOPPY'],
        'armed': false,
        'user_tier': 'free',
        'tier_gate_enabled': true,
        'tier_allows_auto': false,
        'auto_paused': true,
        'path_preference': ['SR_FLIP_RETEST'],
        'regime_preference': <String>[],
        'preferences_block_all': true,
      });
      expect(status.userTier, 'free');
      expect(status.tierAllowsAuto, false);
      expect(status.autoPaused, true);
      expect(status.pathPreference, ['SR_FLIP_RETEST']);
      expect(status.regimePreference, isEmpty);
      expect(status.regimePreference, isNotNull);
      expect(status.preferencesBlockAll, true);
      expect(status.armed, false);
      // Legacy fields keep parsing alongside.
      expect(status.binanceKeyConnected, true);
      expect(status.userMode, 'live');
    });

    test('old-engine payload (keys absent) → nulls + defaults, rows hidden',
        () {
      final status = AutoTradeRuntimeStatus.fromJson(const {
        'auto_trade_globally_enabled': true,
        'auto_trade_user_disabled': false,
        'binance_key_connected': true,
        'user_mode': 'live',
        'allowed_symbols': ['BTCUSDT'],
        'armed': true,
      });
      expect(status.userTier, isNull);
      expect(status.tierAllowsAuto, isNull); // unknown ≠ false
      expect(status.autoPaused, isNull);
      expect(status.pathPreference, isNull); // no preference ≠ block-all
      expect(status.regimePreference, isNull);
      expect(status.preferencesBlockAll, false);
      expect(status.armed, true);
    });

    test('explicit empty path_preference is distinct from absent', () {
      final blockAll = AutoTradeRuntimeStatus.fromJson(const {
        'armed': false,
        'path_preference': <String>[],
      });
      expect(blockAll.pathPreference, isNotNull);
      expect(blockAll.pathPreference, isEmpty);

      final noPref = AutoTradeRuntimeStatus.fromJson(const {'armed': false});
      expect(noPref.pathPreference, isNull);
    });

    test('empty-string tier coerces to null like user_mode does', () {
      final status = AutoTradeRuntimeStatus.fromJson(const {
        'armed': false,
        'user_tier': '',
      });
      expect(status.userTier, isNull);
    });
  });

  group('TakeSignalResult.fromJson', () {
    test('placed outcome carries fill fields', () {
      final r = TakeSignalResult.fromJson(const {
        'outcome': 'placed',
        'signal_id': 'sig-1',
        'symbol': 'BTCUSDT',
        'direction': 'LONG',
        'entry_price': 29000.0,
        'total_qty': 0.017,
      });
      expect(r.placed, true);
      expect(r.queued, false);
      expect(r.symbol, 'BTCUSDT');
      expect(r.totalQty, 0.017);
      expect(r.signalId, 'sig-1');
    });

    test('rejected outcome mirrors DispatchEvent reject fields', () {
      final r = TakeSignalResult.fromJson(const {
        'outcome': 'rejected',
        'signal_id': 'sig-1',
        'reject_class': 'OrderRejectedByBinance',
        'reject_detail': 'code=-2019 Margin is insufficient.',
        'reject_binance_code': -2019,
        'reject_binance_msg': 'Margin is insufficient.',
      });
      expect(r.placed, false);
      expect(r.rejectClass, 'OrderRejectedByBinance');
      expect(r.rejectBinanceCode, -2019);
      expect(r.rejectBinanceMsg, 'Margin is insufficient.');
    });

    test('queued outcome carries server guidance detail', () {
      final r = TakeSignalResult.fromJson(const {
        'outcome': 'queued',
        'signal_id': 'sig-1',
        'detail': 'The engine is taking longer than usual.',
      });
      expect(r.queued, true);
      expect(r.detail, contains('longer than usual'));
    });

    test('empty map fails closed to rejected', () {
      final r = TakeSignalResult.fromJson(const {});
      expect(r.outcome, 'rejected');
      expect(r.placed, false);
      expect(r.queued, false);
    });
  });
}

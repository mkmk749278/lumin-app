// Tests for ManualTradeRequest.toJson + ManualTradeResult.fromJson
// (manual trade builder, 2026-07-18). Pins the wire contract with the
// engine's POST /api/manual-trade/take, and — per this repo's convention —
// keeps fromJson tolerant of a pre-upgrade engine that omits the new fields.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/server_side_execution_models.dart';

void main() {
  group('ManualTradeRequest.toJson', () {
    test('serialises full geometry to the engine snake_case keys', () {
      const req = ManualTradeRequest(
        refId: 'alert-9',
        symbol: 'BTCUSDT',
        direction: 'LONG',
        entryType: 'limit',
        entryPrice: 28900.0,
        slPrice: 28500.0,
        tpPrices: [29500.0, 30000.0],
        validForMinutes: 15,
      );
      expect(req.toJson(), {
        'ref_id': 'alert-9',
        'symbol': 'BTCUSDT',
        'direction': 'LONG',
        'entry_type': 'limit',
        'entry_price': 28900.0,
        'sl_price': 28500.0,
        'tp_prices': [29500.0, 30000.0],
        'valid_for_minutes': 15,
      });
    });

    test('entry-only market trade defaults SL/TP/TTL', () {
      const req = ManualTradeRequest(
        refId: 'a1', symbol: 'OPUSDT', direction: 'SHORT',
        entryType: 'market', entryPrice: 0.0957,
      );
      final j = req.toJson();
      expect(j['sl_price'], 0.0);
      expect(j['tp_prices'], isEmpty);
      expect(j['valid_for_minutes'], 0);
    });
  });

  group('ManualTradeResult.fromJson', () {
    test('parses a placed resting LIMIT', () {
      final r = ManualTradeResult.fromJson({
        'outcome': 'placed',
        'ref_id': 'alert-9',
        'symbol': 'BTCUSDT',
        'direction': 'LONG',
        'entry_price': 28900.0,
        'total_qty': 0.017,
        'entry_type': 'limit',
        'resting': true,
      });
      expect(r.placed, isTrue);
      expect(r.resting, isTrue);
      expect(r.entryType, 'limit');
      expect(r.symbol, 'BTCUSDT');
    });

    test('parses a rejection with reject fields', () {
      final r = ManualTradeResult.fromJson({
        'outcome': 'rejected',
        'ref_id': 'a2',
        'reject_class': 'NotionalTooSmall',
        'reject_detail': 'too small',
        'reject_binance_code': -2019,
      });
      expect(r.placed, isFalse);
      expect(r.rejectClass, 'NotionalTooSmall');
      expect(r.rejectBinanceCode, -2019);
    });

    test('tolerates a minimal payload from an older engine', () {
      final r = ManualTradeResult.fromJson({'outcome': 'queued'});
      expect(r.queued, isTrue);
      expect(r.resting, isFalse); // defaults, no crash
      expect(r.refId, '');
      expect(r.entryType, isNull);
    });
  });
}

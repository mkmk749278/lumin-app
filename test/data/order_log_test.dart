/// Tests for ``lib/data/order_log.dart`` — the per-user idempotency log
/// that prevents Lumin from double-firing a Binance order if the user
/// taps Take twice, the network retries, or AutoTradeWatcher hits the
/// same signal_id on a subsequent tick.
///
/// First-wave coverage:
///   1. ``OrderLogEntry.toJson`` / ``fromJson`` round-trip — including
///      the Phase-4 pre-TP fields that landed in PR #25.
///   2. ``OrderLogService.record`` capacity prune at the 200-entry cap.
///   3. ``OrderLogService.entryFor`` idempotency lookup.
///   4. ``OrderLogService.clear`` wipes only the target user.
///
/// Storage is faked with an in-memory ``Map`` shim implementing the
/// ``SecureKvStore`` seam exposed by ``order_log.dart`` so the tests
/// run under ``flutter test`` without touching platform channels or
/// the ``flutter_secure_storage`` federated-plugin interface.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/order_log.dart';

/// In-memory implementation of OrderLogService's storage seam.  No
/// platform-channel touch, no flutter_secure_storage version coupling.
class _FakeKvStore implements SecureKvStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
}

OrderLogEntry _entry({
  required String id,
  DateTime? placedAt,
  String executionMode = 'manual',
  DateTime? preTpClosedAt,
}) {
  return OrderLogEntry(
    signalId: id,
    symbol: 'BTCUSDT',
    side: 'BUY',
    quantity: 0.01,
    entryOrderId: 100,
    stopOrderId: 200,
    tpOrderId: 300,
    placedAt: placedAt ?? DateTime.utc(2026, 5, 17, 12, 0, 0),
    testnet: true,
    avgFillPrice: 50000.0,
    executionMode: executionMode,
    entryPriceTarget: 50000.0,
    slPrice: 49500.0,
    tpPrice: 50500.0,
    preTpClosedAt: preTpClosedAt,
    preTpQty: preTpClosedAt != null ? 0.005 : null,
    preTpOrderId: preTpClosedAt != null ? 400 : null,
    preTpFillPrice: preTpClosedAt != null ? 50200.0 : null,
    breakevenStopOrderId: preTpClosedAt != null ? 500 : null,
    grabFractionApplied: preTpClosedAt != null ? 0.5 : null,
  );
}

void main() {
  group('OrderLogEntry json round-trip', () {
    test('preserves all fields including Phase-4 pre-TP block', () {
      final original = _entry(
        id: 'sig-42',
        preTpClosedAt: DateTime.utc(2026, 5, 17, 12, 5, 30),
      );
      final restored = OrderLogEntry.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.signalId, 'sig-42');
      expect(restored.symbol, 'BTCUSDT');
      expect(restored.side, 'BUY');
      expect(restored.quantity, 0.01);
      expect(restored.entryOrderId, 100);
      expect(restored.stopOrderId, 200);
      expect(restored.tpOrderId, 300);
      expect(restored.placedAt.toUtc(), DateTime.utc(2026, 5, 17, 12, 0, 0));
      expect(restored.testnet, true);
      expect(restored.avgFillPrice, 50000.0);
      expect(restored.executionMode, 'manual');
      expect(restored.entryPriceTarget, 50000.0);
      expect(restored.slPrice, 49500.0);
      expect(restored.tpPrice, 50500.0);
      expect(restored.preTpClosedAt!.toUtc(),
          DateTime.utc(2026, 5, 17, 12, 5, 30));
      expect(restored.preTpQty, 0.005);
      expect(restored.preTpOrderId, 400);
      expect(restored.preTpFillPrice, 50200.0);
      expect(restored.breakevenStopOrderId, 500);
      expect(restored.grabFractionApplied, 0.5);
      expect(restored.preTpBanked, true);
    });

    test('preTpBanked is false until pre-TP fires', () {
      final entry = _entry(id: 'sig-1');
      expect(entry.preTpBanked, false);
      expect(entry.isPaper, false);
      expect(entry.isAuto, false);
    });

    test('isAuto / isPaper derive from executionMode', () {
      expect(_entry(id: 'a', executionMode: 'auto-live').isAuto, true);
      expect(_entry(id: 'a', executionMode: 'auto-live').isPaper, false);
      expect(_entry(id: 'b', executionMode: 'auto-paper').isAuto, true);
      expect(_entry(id: 'b', executionMode: 'auto-paper').isPaper, true);
      expect(_entry(id: 'c', executionMode: 'manual').isAuto, false);
    });

    test('copyWith.clearStopOrderId nulls the stop_order_id (Phase-4 BE replacement)', () {
      final entry = _entry(id: 'sig-1');
      final cleared = entry.copyWith(clearStopOrderId: true);
      expect(cleared.stopOrderId, isNull);
      // Other fields untouched.
      expect(cleared.entryOrderId, entry.entryOrderId);
      expect(cleared.signalId, entry.signalId);
    });

    test('fromJson with missing optional fields uses defaults (back-compat with v0 logs)', () {
      final minimal = OrderLogEntry.fromJson({
        'signal_id': 'old-1',
        'symbol': 'ETHUSDT',
        'side': 'SELL',
        'quantity': 1.0,
        'placed_at': '2026-05-17T12:00:00Z',
      });
      expect(minimal.entryOrderId, isNull);
      expect(minimal.stopOrderId, isNull);
      expect(minimal.executionMode, 'manual'); // default for v0 entries
      expect(minimal.preTpBanked, false);
      expect(minimal.testnet, false);
    });
  });

  group('OrderLogService idempotency + persistence', () {
    test('record + entryFor round-trip via storage', () async {
      final storage = _FakeKvStore();
      final svc = OrderLogService(store: storage);

      await svc.record(7, _entry(id: 'sig-1'));
      final found = await svc.entryFor(7, 'sig-1');
      expect(found, isNotNull);
      expect(found!.signalId, 'sig-1');

      final missing = await svc.entryFor(7, 'never-seen');
      expect(missing, isNull);
    });

    test('namespaces per userId so users do not collide', () async {
      final storage = _FakeKvStore();
      final svc = OrderLogService(store: storage);

      await svc.record(7, _entry(id: 'sig-1'));
      await svc.record(8, _entry(id: 'sig-2'));

      expect(await svc.entryFor(7, 'sig-2'), isNull);
      expect(await svc.entryFor(8, 'sig-1'), isNull);
      expect((await svc.entryFor(7, 'sig-1'))!.signalId, 'sig-1');
      expect((await svc.entryFor(8, 'sig-2'))!.signalId, 'sig-2');
    });

    test('prunes oldest entries beyond the 200-entry cap, retaining newest by placedAt', () async {
      final storage = _FakeKvStore();
      final svc = OrderLogService(store: storage);

      // Insert 205 entries with increasing placedAt — newest is sig-204.
      // The cap is 200; oldest 5 should be evicted, newest 200 kept.
      final base = DateTime.utc(2026, 5, 1, 0, 0, 0);
      for (var i = 0; i < 205; i++) {
        await svc.record(
          1,
          _entry(
            id: 'sig-$i',
            placedAt: base.add(Duration(minutes: i)),
          ),
        );
      }

      final after = await svc.load(1);
      expect(after.length, 200);
      // Newest must survive.
      expect(after.containsKey('sig-204'), true);
      expect(after.containsKey('sig-200'), true);
      // Oldest 5 must be evicted.
      expect(after.containsKey('sig-0'), false);
      expect(after.containsKey('sig-4'), false);
      // Boundary: sig-5 (the 6th-inserted) is the new oldest survivor.
      expect(after.containsKey('sig-5'), true);
    });

    test('clear wipes one user without disturbing others', () async {
      final storage = _FakeKvStore();
      final svc = OrderLogService(store: storage);

      await svc.record(1, _entry(id: 'sig-a'));
      await svc.record(2, _entry(id: 'sig-b'));

      await svc.clear(1);

      expect((await svc.load(1)).isEmpty, true);
      expect((await svc.load(2)).length, 1);
      expect((await svc.entryFor(2, 'sig-b'))!.signalId, 'sig-b');
    });

    test('load returns empty map on corrupt blob (defensive against partial writes)', () async {
      final storage = _FakeKvStore();
      // Stuff malformed JSON into the user's slot.
      storage.data['order_log.user.5'] = '{not valid json';
      final svc = OrderLogService(store: storage);

      expect((await svc.load(5)).isEmpty, true);
      expect(await svc.entryFor(5, 'anything'), isNull);
    });

    test('load skips malformed individual entries but keeps the rest', () async {
      final storage = _FakeKvStore();
      // One good entry + one entry missing required fields.
      storage.data['order_log.user.9'] = jsonEncode({
        'sig-good': {
          'signal_id': 'sig-good',
          'symbol': 'BTCUSDT',
          'side': 'BUY',
          'quantity': 1.0,
          'placed_at': '2026-05-17T12:00:00Z',
        },
        'sig-bad': {
          'signal_id': 'sig-bad',
          // 'symbol' missing → fromJson throws → entry skipped.
        },
      });
      final svc = OrderLogService(store: storage);
      final log = await svc.load(9);

      expect(log.containsKey('sig-good'), true);
      expect(log.containsKey('sig-bad'), false);
    });

    test('re-recording the same signal_id overwrites, not appends', () async {
      final storage = _FakeKvStore();
      final svc = OrderLogService(store: storage);

      await svc.record(1, _entry(id: 'sig-1'));
      // Same id, post-pre-TP entry — simulates the Phase-4 overwrite flow
      // where executePreTpPartial replaces the original entry with a
      // copyWith(preTpClosedAt: now) version.
      await svc.record(
        1,
        _entry(
          id: 'sig-1',
          preTpClosedAt: DateTime.utc(2026, 5, 17, 12, 30, 0),
        ),
      );

      final log = await svc.load(1);
      expect(log.length, 1);
      expect(log['sig-1']!.preTpBanked, true);
    });
  });
}

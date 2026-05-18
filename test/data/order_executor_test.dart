/// Tests for ``lib/data/order_executor.dart`` — the orchestrator that
/// composes a signal → entry / SL / TP triplet and the Phase-4 pre-TP
/// partial close.
///
/// Scope of this first wave (no broker mocking):
///   * Idempotency short-circuit: ``placeFromSignal`` and ``recordPaper``
///     both must return ``alreadyTaken`` (success=true, no new entry)
///     when the log already has an entry for the signal_id.  This is
///     the primary defence against double-firing real money on retry /
///     watcher race / user double-tap.
///   * Pre-flight settings validation: a missing position-size or
///     leverage cap must produce a clean ``_fail`` ExecutionResult
///     surfacing the user-facing fix instruction — never a crash.
///   * ``recordPaper`` end-to-end: signal in → auto-paper OrderLogEntry
///     out, with the qty derived from simulated equity × pct × leverage.
///
/// Broker-call paths in ``placeFromSignal`` and ``executePreTpPartial``
/// instantiate ``BinanceClient`` internally and are deferred until we
/// add a client factory (test/v2 in this audit summary).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/mock_data.dart';
import 'package:lumin/data/order_executor.dart';
import 'package:lumin/data/order_log.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/data/binance_keys_service.dart';

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

MockSignal _signal({String id = 'sig-1', String direction = 'LONG'}) =>
    MockSignal(
      id: id,
      symbol: 'BTCUSDT',
      direction: direction,
      setupName: 'TEST',
      agentName: 'test',
      entry: 50000.0,
      sl: 49500.0,
      tp1: 50500.0,
      tp2: 51000.0,
      tp3: 52000.0,
      confidence: 85,
      tier: 'A+',
      status: 'ACTIVE',
      pnlPct: 0.0,
      minutesAgo: 1,
    );

BinanceKeys _keys() => const BinanceKeys(
      apiKey: 'TEST_KEY',
      apiSecret: 'TEST_SECRET',
      testnet: true,
    );

OrderLogEntry _seededEntry(String signalId) => OrderLogEntry(
      signalId: signalId,
      symbol: 'BTCUSDT',
      side: 'BUY',
      quantity: 0.01,
      entryOrderId: 100,
      stopOrderId: 200,
      tpOrderId: 300,
      placedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
      testnet: true,
      avgFillPrice: 50000.0,
      executionMode: 'manual',
      entryPriceTarget: 50000.0,
      slPrice: 49500.0,
      tpPrice: 50500.0,
    );

void main() {
  group('OrderExecutor.placeFromSignal idempotency', () {
    test('short-circuits with alreadyTaken when log already has the signal_id', () async {
      final storage = _FakeSecureStorage();
      final logService = OrderLogService(storage: storage);
      final executor = OrderExecutor(logService: logService);

      await logService.record(1, _seededEntry('sig-1'));

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(id: 'sig-1'),
        keys: _keys(),
        settings: const AutoTradeSettings(
          mode: 'live',
          positionSizePct: 2.0,
          leverageCap: 10.0,
        ),
        equity: 1000.0,
      );

      expect(result.success, true);
      expect(result.alreadyTaken, isNotNull);
      expect(result.alreadyTaken!.signalId, 'sig-1');
      expect(result.entry, isNull,
          reason: 'no new entry should be recorded on idempotency hit');
      expect(result.message, contains('Already taken'));
    });

    test('rejects with clean message when positionSizePct missing', () async {
      final storage = _FakeSecureStorage();
      final logService = OrderLogService(storage: storage);
      final executor = OrderExecutor(logService: logService);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        // positionSizePct intentionally null.
        settings: const AutoTradeSettings(mode: 'live', leverageCap: 10.0),
        equity: 1000.0,
      );

      expect(result.success, false);
      expect(result.entry, isNull);
      expect(result.message, contains('position size'));
      // No write to the log on validation failure.
      expect((await logService.load(1)).isEmpty, true);
    });

    test('rejects with clean message when leverageCap missing', () async {
      final storage = _FakeSecureStorage();
      final logService = OrderLogService(storage: storage);
      final executor = OrderExecutor(logService: logService);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: const AutoTradeSettings(mode: 'live', positionSizePct: 2.0),
        equity: 1000.0,
      );

      expect(result.success, false);
      expect(result.message, contains('leverage'));
      expect((await logService.load(1)).isEmpty, true);
    });
  });

  group('OrderExecutor.recordPaper', () {
    test('produces an auto-paper entry with sizing-derived qty', () async {
      final storage = _FakeSecureStorage();
      final logService = OrderLogService(storage: storage);
      final executor = OrderExecutor(logService: logService);

      final result = await executor.recordPaper(
        userId: 1,
        signal: _signal(id: 'sig-paper-1'),
        settings: const AutoTradeSettings(
          mode: 'paper',
          positionSizePct: 2.0, // 2% of simulated equity
          leverageCap: 10.0,
        ),
        simulatedEquity: 10000.0,
      );

      expect(result.success, true);
      expect(result.entry, isNotNull);
      // Notional = 10000 * 2% * 10x = 2000. Qty = 2000 / 50000 = 0.04.
      expect(result.entry!.quantity, closeTo(0.04, 1e-9));
      expect(result.entry!.executionMode, 'auto-paper');
      expect(result.entry!.entryOrderId, isNull,
          reason: 'paper entries never have a broker order id');
      expect(result.entry!.isPaper, true);

      // Persisted to the log.
      final stored = await logService.entryFor(1, 'sig-paper-1');
      expect(stored, isNotNull);
      expect(stored!.executionMode, 'auto-paper');
    });

    test('clamps leverage above 30 down to the B12 hard cap', () async {
      final storage = _FakeSecureStorage();
      final logService = OrderLogService(storage: storage);
      final executor = OrderExecutor(logService: logService);

      final result = await executor.recordPaper(
        userId: 1,
        signal: _signal(id: 'sig-paper-2'),
        settings: const AutoTradeSettings(
          mode: 'paper',
          positionSizePct: 1.0,
          leverageCap: 125.0, // user attempts max; B12 clamps to 30.
        ),
        simulatedEquity: 10000.0,
      );

      expect(result.success, true);
      // Notional = 10000 * 1% * 30x = 3000. Qty = 3000 / 50000 = 0.06.
      expect(result.entry!.quantity, closeTo(0.06, 1e-9));
    });

    test('idempotency: re-recording the same signal_id returns alreadyTaken', () async {
      final storage = _FakeSecureStorage();
      final logService = OrderLogService(storage: storage);
      final executor = OrderExecutor(logService: logService);

      await executor.recordPaper(
        userId: 1,
        signal: _signal(id: 'sig-paper-3'),
        settings: const AutoTradeSettings(
          mode: 'paper',
          positionSizePct: 2.0,
          leverageCap: 10.0,
        ),
        simulatedEquity: 10000.0,
      );

      final replay = await executor.recordPaper(
        userId: 1,
        signal: _signal(id: 'sig-paper-3'),
        settings: const AutoTradeSettings(
          mode: 'paper',
          positionSizePct: 2.0,
          leverageCap: 10.0,
        ),
        simulatedEquity: 10000.0,
      );

      expect(replay.success, true);
      expect(replay.alreadyTaken, isNotNull);
      expect(replay.entry, isNull);
      // Log still only has one entry for that id.
      expect((await logService.load(1)).length, 1);
    });

    test('rejects with clean message when paper settings incomplete', () async {
      final storage = _FakeSecureStorage();
      final logService = OrderLogService(storage: storage);
      final executor = OrderExecutor(logService: logService);

      final result = await executor.recordPaper(
        userId: 1,
        signal: _signal(),
        settings: const AutoTradeSettings(mode: 'paper'), // both null
        simulatedEquity: 10000.0,
      );

      expect(result.success, false);
      expect(result.message, contains('position size'));
      expect(result.message, contains('leverage'));
    });
  });
}

/// Broker-call path tests for ``lib/data/order_executor.dart`` —
/// exercises the network-side of ``placeFromSignal`` (after the
/// idempotency / settings short-circuits covered in
/// ``order_executor_test.dart``) and the full pre-TP partial-close
/// flow in ``executePreTpPartial``.
///
/// A fake :class:`BinanceClientApi` records every broker call and
/// can be programmed to throw :class:`BinanceError` on any method so
/// each partial-failure path the production code handles
/// (SL placement fail / TP placement fail / cancel race / BE
/// placement fail) is independently pinned.
///
/// Filter assumptions match the most-common Binance Futures pair
/// shape (tickSize 0.1, stepSize 0.001, minQty 0.001,
/// minNotional 5 USDT) so qty + price math in the tests is
/// hand-checkable against the production rounding rules.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/binance_client.dart';
import 'package:lumin/data/binance_keys_service.dart';
import 'package:lumin/data/mock_data.dart';
import 'package:lumin/data/order_executor.dart';
import 'package:lumin/data/order_log.dart';
import 'package:lumin/data/repository.dart';

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
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

class _FakeBinanceClient implements BinanceClientApi {
  // Optional override of the default filters response (per-test).
  BinanceSymbolFilters Function(String symbol)? filtersHandler;

  // Programmable errors — when set, the method throws instead of
  // returning the default success response.
  Object? filtersError;
  Object? setLeverageError;
  Object? marketOrderError;
  // ``createStopOrder`` is shared between SL (STOP_MARKET), TP
  // (TAKE_PROFIT_MARKET) and the post-pre-TP BE (STOP_MARKET).  Tests
  // pick the failure they want via stopType-keyed errors.
  Object? stopMarketError; // STOP_MARKET — i.e. entry SL or BE SL
  Object? takeProfitError; // TAKE_PROFIT_MARKET — i.e. TP1
  Object? cancelOrderError;
  Object? closePartialError;

  // Call log — one entry per broker call so tests can assert order +
  // arguments without re-mocking each call.
  final List<Map<String, Object?>> calls = [];
  bool disposed = false;

  // Allocate distinct order ids per method so log entries are
  // distinguishable in assertions.
  int _marketOrderId = 1000;
  int _stopMarketOrderId = 2000;
  int _takeProfitOrderId = 3000;
  int _closePartialOrderId = 4000;

  static const _defaultFilters = BinanceSymbolFilters(
    symbol: 'BTCUSDT',
    tickSize: 0.1,
    stepSize: 0.001,
    minQty: 0.001,
    minNotional: 5.0,
  );

  @override
  Future<BinanceSymbolFilters> getSymbolFilters(String symbol) async {
    calls.add({'method': 'getSymbolFilters', 'symbol': symbol});
    if (filtersError != null) throw filtersError!;
    return filtersHandler?.call(symbol) ?? _defaultFilters;
  }

  @override
  Future<void> setLeverage(String symbol, int leverage) async {
    calls.add({
      'method': 'setLeverage',
      'symbol': symbol,
      'leverage': leverage,
    });
    if (setLeverageError != null) throw setLeverageError!;
  }

  @override
  Future<Map<String, dynamic>> createMarketOrder({
    required String symbol,
    required String side,
    required double quantity,
    String? clientOrderId,
  }) async {
    calls.add({
      'method': 'createMarketOrder',
      'symbol': symbol,
      'side': side,
      'quantity': quantity,
      'clientOrderId': clientOrderId,
    });
    if (marketOrderError != null) throw marketOrderError!;
    return {
      'orderId': _marketOrderId++,
      'avgPrice': '50000.0',
    };
  }

  @override
  Future<Map<String, dynamic>> createStopOrder({
    required String symbol,
    required String side,
    required String stopType,
    required double stopPrice,
    double? quantity,
    bool closePosition = false,
    String? clientOrderId,
  }) async {
    calls.add({
      'method': 'createStopOrder',
      'symbol': symbol,
      'side': side,
      'stopType': stopType,
      'stopPrice': stopPrice,
      'quantity': quantity,
      'closePosition': closePosition,
      'clientOrderId': clientOrderId,
    });
    if (stopType == 'STOP_MARKET' && stopMarketError != null) {
      throw stopMarketError!;
    }
    if (stopType == 'TAKE_PROFIT_MARKET' && takeProfitError != null) {
      throw takeProfitError!;
    }
    return {
      'orderId': stopType == 'STOP_MARKET'
          ? _stopMarketOrderId++
          : _takeProfitOrderId++,
    };
  }

  @override
  Future<Map<String, dynamic>> cancelOrder({
    required String symbol,
    int? orderId,
    String? origClientOrderId,
  }) async {
    calls.add({
      'method': 'cancelOrder',
      'symbol': symbol,
      'orderId': orderId,
      'origClientOrderId': origClientOrderId,
    });
    if (cancelOrderError != null) throw cancelOrderError!;
    return {'orderId': orderId};
  }

  @override
  Future<Map<String, dynamic>> closePartialMarket({
    required String symbol,
    required String side,
    required double quantity,
    String? clientOrderId,
  }) async {
    calls.add({
      'method': 'closePartialMarket',
      'symbol': symbol,
      'side': side,
      'quantity': quantity,
      'clientOrderId': clientOrderId,
    });
    if (closePartialError != null) throw closePartialError!;
    return {
      'orderId': _closePartialOrderId++,
      'avgPrice': '50100.0',
    };
  }

  @override
  void dispose() {
    disposed = true;
  }
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

BinanceKeys _keys({bool testnet = true}) => BinanceKeys(
      apiKey: 'TEST_KEY',
      apiSecret: 'TEST_SECRET',
      testnet: testnet,
    );

AutoTradeSettings _settings({double pct = 2.0, double leverage = 10.0}) =>
    AutoTradeSettings(
      mode: 'live',
      positionSizePct: pct,
      leverageCap: leverage,
    );

OrderLogEntry _liveLongEntry({
  String signalId = 'sig-1',
  double quantity = 0.04,
  double? avgFillPrice = 50000.0,
  int? entryOrderId = 1000,
  int? stopOrderId = 2000,
  DateTime? preTpClosedAt,
}) =>
    OrderLogEntry(
      signalId: signalId,
      symbol: 'BTCUSDT',
      side: 'BUY',
      quantity: quantity,
      entryOrderId: entryOrderId,
      stopOrderId: stopOrderId,
      tpOrderId: 3000,
      placedAt: DateTime.utc(2026, 5, 18, 12, 0, 0),
      testnet: true,
      avgFillPrice: avgFillPrice,
      executionMode: 'auto-live',
      entryPriceTarget: 50000.0,
      slPrice: 49500.0,
      tpPrice: 50500.0,
      preTpClosedAt: preTpClosedAt,
    );

void main() {
  group('OrderExecutor.placeFromSignal broker happy path', () {
    test('places filters → leverage → market → SL → TP in order, records entry with all three ids',
        () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor = OrderExecutor(
        logService: logService,
        clientFactory: (_) => fake,
      );

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
      );

      expect(result.success, true);
      expect(result.entry, isNotNull);
      // Notional = 1000 × 2% × 10x = 200.  Qty = 200 / 50000 = 0.004.
      expect(result.entry!.quantity, closeTo(0.004, 1e-9));
      expect(result.entry!.entryOrderId, 1000);
      expect(result.entry!.stopOrderId, 2000);
      expect(result.entry!.tpOrderId, 3000);
      expect(result.entry!.executionMode, 'manual',
          reason: 'default executionMode when caller omits it');
      // avgFillPrice from market order response, not the signal nominal.
      expect(result.entry!.avgFillPrice, 50000.0);

      // Broker call order is fixed by capital-preservation doctrine:
      // leverage MUST be set before the entry order or Binance rejects
      // it with -4028.  SL is placed before TP so the trade has
      // downside protection before any take-profit triggers.
      final methods = fake.calls.map((c) => c['method']).toList();
      expect(methods, [
        'getSymbolFilters',
        'setLeverage',
        'createMarketOrder',
        'createStopOrder', // SL
        'createStopOrder', // TP
      ]);

      // SL goes first with closePosition=true; TP second with reduceOnly + qty.
      final slCall = fake.calls[3];
      expect(slCall['stopType'], 'STOP_MARKET');
      expect(slCall['closePosition'], true);
      expect(slCall['quantity'], isNull);
      expect(slCall['side'], 'SELL'); // close side of a LONG
      expect(slCall['clientOrderId'], 'lumin-sl-sig-1');

      final tpCall = fake.calls[4];
      expect(tpCall['stopType'], 'TAKE_PROFIT_MARKET');
      expect(tpCall['closePosition'], false);
      expect(tpCall['quantity'], closeTo(0.004, 1e-9));
      expect(tpCall['clientOrderId'], 'lumin-tp1-sig-1');

      expect(fake.disposed, true, reason: 'client.dispose() in finally block');

      // Idempotency log got the entry.
      final stored = await logService.entryFor(1, 'sig-1');
      expect(stored, isNotNull);
      expect(stored!.entryOrderId, 1000);
    });

    test('passes executionMode through to the log entry', () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
        executionMode: 'auto-live',
      );

      expect(result.success, true);
      expect(result.entry!.executionMode, 'auto-live');
    });

    test('SHORT signal inverts side to SELL (entry) / BUY (closes), TP qty matches entry',
        () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      await executor.placeFromSignal(
        userId: 1,
        signal: _signal(direction: 'SHORT'),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
      );

      final marketCall = fake.calls
          .firstWhere((c) => c['method'] == 'createMarketOrder');
      expect(marketCall['side'], 'SELL');

      final slCall = fake.calls
          .firstWhere((c) => c['stopType'] == 'STOP_MARKET');
      expect(slCall['side'], 'BUY', reason: 'close side for a SHORT is BUY');
    });
  });

  group('OrderExecutor.placeFromSignal broker partial-failure paths', () {
    test('SL placement fails: entry recorded, TP still attempted, returns partial-success message',
        () async {
      final fake = _FakeBinanceClient()
        ..stopMarketError = BinanceError(
          statusCode: 400,
          code: -2021,
          message: 'Order would immediately trigger.',
        );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
      );

      expect(result.success, false);
      expect(result.entry, isNotNull,
          reason: 'entry recorded even on bracket-leg failure');
      expect(result.entry!.entryOrderId, 1000);
      expect(result.entry!.stopOrderId, isNull);
      expect(result.entry!.tpOrderId, 3000,
          reason: 'TP attempted despite SL failure');
      expect(result.message, contains('SL placement failed'));
      expect(result.message, contains('immediately trigger'));

      // Log persisted with the partial result so a retry sees alreadyTaken.
      final stored = await logService.entryFor(1, 'sig-1');
      expect(stored, isNotNull);
      expect(stored!.stopOrderId, isNull);
    });

    test('TP placement fails: entry + SL recorded, returns partial-success message',
        () async {
      final fake = _FakeBinanceClient()
        ..takeProfitError = BinanceError(
          statusCode: 400,
          code: -2021,
          message: 'Order would immediately trigger.',
        );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
      );

      expect(result.success, false);
      expect(result.entry!.entryOrderId, 1000);
      expect(result.entry!.stopOrderId, 2000);
      expect(result.entry!.tpOrderId, isNull);
      expect(result.message, contains('TP placement failed'));
    });

    test('both SL and TP fail: both warnings surface, entry still recorded',
        () async {
      final fake = _FakeBinanceClient()
        ..stopMarketError = BinanceError(
            statusCode: 400, code: -2021, message: 'sl boom')
        ..takeProfitError = BinanceError(
            statusCode: 400, code: -2021, message: 'tp boom');
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
      );

      expect(result.success, false);
      expect(result.entry!.entryOrderId, 1000);
      expect(result.entry!.stopOrderId, isNull);
      expect(result.entry!.tpOrderId, isNull);
      expect(result.message, contains('sl boom'));
      expect(result.message, contains('tp boom'));
    });

    test('entry order itself fails: no log entry written', () async {
      final fake = _FakeBinanceClient()
        ..marketOrderError = BinanceError(
          statusCode: 400,
          code: -2014,
          message: 'API-key format invalid.',
        );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
      );

      expect(result.success, false);
      expect(result.entry, isNull);
      expect(result.message, contains('API-key format invalid'));
      expect(result.message, contains('-2014'));

      // No log entry — a retry must be able to attempt this signal again.
      expect((await logService.load(1)).isEmpty, true);
    });

    test('qty rounds to 0 below minQty: fails before any broker order',
        () async {
      final fake = _FakeBinanceClient()
        // Step size enormous — anything below 1 BTC rounds to 0.
        ..filtersHandler = (_) => const BinanceSymbolFilters(
              symbol: 'BTCUSDT',
              tickSize: 0.1,
              stepSize: 1.0,
              minQty: 1.0,
              minNotional: 5.0,
            );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
      );

      expect(result.success, false);
      expect(result.message, contains('minQty'));
      // setLeverage / market / SL / TP must NOT have been called.
      expect(fake.calls.map((c) => c['method']),
          ['getSymbolFilters']);
      expect((await logService.load(1)).isEmpty, true);
    });

    test('notional below minNotional: fails before any broker order',
        () async {
      final fake = _FakeBinanceClient()
        ..filtersHandler = (_) => const BinanceSymbolFilters(
              symbol: 'BTCUSDT',
              tickSize: 0.1,
              stepSize: 0.001,
              minQty: 0.001,
              minNotional: 10000.0, // way above our 200 USDT notional
            );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.placeFromSignal(
        userId: 1,
        signal: _signal(),
        keys: _keys(),
        settings: _settings(),
        equity: 1000.0,
      );

      expect(result.success, false);
      expect(result.message, contains('minNotional'));
      expect(fake.calls.map((c) => c['method']),
          ['getSymbolFilters']);
    });
  });

  group('OrderExecutor.executePreTpPartial — happy path', () {
    test('banks partial, cancels original SL, places BE SL, updates log entry',
        () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final logEntry = _liveLongEntry();
      await logService.record(1, logEntry);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: logEntry,
        keys: _keys(),
        grabFraction: 0.5,
      );

      expect(result.success, true);
      expect(result.entry, isNotNull);
      // 50% of 0.04 = 0.02 (within stepSize 0.001).
      expect(result.entry!.preTpQty, closeTo(0.02, 1e-9));
      expect(result.entry!.preTpOrderId, 4000);
      expect(result.entry!.preTpFillPrice, 50100.0);
      expect(result.entry!.preTpClosedAt, isNotNull);
      expect(result.entry!.breakevenStopOrderId, 2000,
          reason: 'BE SL is a STOP_MARKET — uses _stopMarketOrderId counter');
      expect(result.entry!.stopOrderId, isNull,
          reason: 'original SL cleared after successful cancel + BE replace');
      expect(result.entry!.grabFractionApplied, 0.5);

      // Broker call order pinned: filters → close partial → cancel SL → BE.
      expect(fake.calls.map((c) => c['method']), [
        'getSymbolFilters',
        'closePartialMarket',
        'cancelOrder',
        'createStopOrder',
      ]);

      final closeCall = fake.calls[1];
      expect(closeCall['side'], 'SELL',
          reason: 'close side for a LONG entry is SELL');
      expect(closeCall['clientOrderId'], 'lumin-pretp-sig-1');

      final cancelCall = fake.calls[2];
      expect(cancelCall['orderId'], 2000,
          reason: 'cancels the original stopOrderId from the log');

      final beCall = fake.calls[3];
      expect(beCall['stopType'], 'STOP_MARKET');
      expect(beCall['closePosition'], true);
      expect(beCall['stopPrice'], 50000.0,
          reason: 'BE price = entry avgFillPrice, rounded by tickSize');
      expect(beCall['clientOrderId'], 'lumin-be-sig-1');
    });

    test('clamps grabFraction to 0.30 lower bound (B17)', () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final logEntry = _liveLongEntry();
      await logService.record(1, logEntry);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: logEntry,
        keys: _keys(),
        grabFraction: 0.10, // user passed under floor
      );

      expect(result.success, true);
      // Clamped to 0.30 → partial qty = 0.04 × 0.30 = 0.012.
      expect(result.entry!.preTpQty, closeTo(0.012, 1e-9));
      expect(result.entry!.grabFractionApplied, 0.30);
    });

    test('clamps grabFraction to 1.00 upper bound', () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final logEntry = _liveLongEntry();
      await logService.record(1, logEntry);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: logEntry,
        keys: _keys(),
        grabFraction: 1.50, // user passed above ceiling
      );

      expect(result.success, true);
      expect(result.entry!.preTpQty, closeTo(0.04, 1e-9),
          reason: 'clamped to 1.00 = full entry quantity');
      expect(result.entry!.grabFractionApplied, 1.00);
    });

    test('SHORT entry: close side = BUY, BE price uses ceil rounding',
        () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final logEntry = _liveLongEntry().copyWith(); // base
      // Re-build as SHORT — _liveLongEntry hardcodes side='BUY'; we need a fresh.
      final shortEntry = OrderLogEntry(
        signalId: 'sig-short',
        symbol: 'BTCUSDT',
        side: 'SELL',
        quantity: 0.04,
        entryOrderId: 1500,
        stopOrderId: 2500,
        tpOrderId: 3500,
        placedAt: DateTime.utc(2026, 5, 18),
        testnet: true,
        avgFillPrice: 50000.55, // non-tick price to exercise ceil rounding
        executionMode: 'auto-live',
        entryPriceTarget: 50000.0,
        slPrice: 50500.0,
        tpPrice: 49500.0,
      );
      await logService.record(1, shortEntry);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: shortEntry,
        keys: _keys(),
        grabFraction: 0.5,
      );

      expect(result.success, true);
      final closeCall = fake.calls
          .firstWhere((c) => c['method'] == 'closePartialMarket');
      expect(closeCall['side'], 'BUY');

      final beCall =
          fake.calls.firstWhere((c) => c['method'] == 'createStopOrder');
      // tickSize=0.1, avgFillPrice=50000.55, SHORT → ceil → 50000.6.
      expect(beCall['stopPrice'], closeTo(50000.6, 1e-9));
    });
  });

  group('OrderExecutor.executePreTpPartial — short-circuits + partial-failure', () {
    test('already-banked entry returns success without any broker call',
        () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: _liveLongEntry(
          preTpClosedAt: DateTime.utc(2026, 5, 18, 12, 30, 0),
        ),
        keys: _keys(),
        grabFraction: 0.5,
      );

      expect(result.success, true);
      expect(result.message, contains('already banked'));
      expect(fake.calls, isEmpty);
    });

    test('missing entryOrderId fails before any broker call', () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: _liveLongEntry(entryOrderId: null),
        keys: _keys(),
        grabFraction: 0.5,
      );

      expect(result.success, false);
      expect(result.message, contains('no entry on file'));
      expect(fake.calls, isEmpty);
    });

    test('missing avgFillPrice fails before any broker call', () async {
      final fake = _FakeBinanceClient();
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: _liveLongEntry(avgFillPrice: null),
        keys: _keys(),
        grabFraction: 0.5,
      );

      expect(result.success, false);
      expect(result.message, contains('entry fill price'));
      expect(fake.calls, isEmpty);
    });

    test('partial qty rounds to 0 fails after filters fetch, before close',
        () async {
      final fake = _FakeBinanceClient()
        ..filtersHandler = (_) => const BinanceSymbolFilters(
              symbol: 'BTCUSDT',
              tickSize: 0.1,
              stepSize: 1.0, // step too coarse — 0.04 × 0.5 = 0.02 → 0
              minQty: 1.0,
              minNotional: 5.0,
            );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: _liveLongEntry(),
        keys: _keys(),
        grabFraction: 0.5,
      );

      expect(result.success, false);
      expect(result.message, contains('minQty'));
      // Only the filters fetch ran; closePartial / cancel / BE skipped.
      expect(fake.calls.map((c) => c['method']),
          ['getSymbolFilters']);
    });

    test('cancelOrder returns -2011 (race): proceeds to BE placement', () async {
      final fake = _FakeBinanceClient()
        ..cancelOrderError = BinanceError(
          statusCode: 400,
          code: -2011,
          message: 'Unknown order sent.',
        );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final logEntry = _liveLongEntry();
      await logService.record(1, logEntry);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: logEntry,
        keys: _keys(),
        grabFraction: 0.5,
      );

      // -2011 is a benign race (SL fired concurrently); BE still placed.
      expect(result.success, true);
      expect(result.entry!.breakevenStopOrderId, isNotNull);
      // 4 broker calls — close, cancel (returns error swallowed), BE.
      expect(fake.calls.map((c) => c['method']), [
        'getSymbolFilters',
        'closePartialMarket',
        'cancelOrder',
        'createStopOrder', // BE
      ]);
    });

    test('cancelOrder fails with non-2011: skip BE, success=false, warning surfaced',
        () async {
      final fake = _FakeBinanceClient()
        ..cancelOrderError = BinanceError(
          statusCode: 400,
          code: -2013,
          message: 'No need to change.',
        );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final logEntry = _liveLongEntry();
      await logService.record(1, logEntry);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: logEntry,
        keys: _keys(),
        grabFraction: 0.5,
      );

      expect(result.success, false);
      expect(result.entry!.breakevenStopOrderId, isNull);
      expect(result.entry!.preTpClosedAt, isNotNull,
          reason: 'partial still banked — idempotency requires preTpClosedAt set');
      expect(result.message, contains('SL cancel failed'));
      expect(result.message, contains('BE SL not placed'));
      // BE placement was skipped — only filters/close/cancel ran.
      expect(fake.calls.map((c) => c['method']), [
        'getSymbolFilters',
        'closePartialMarket',
        'cancelOrder',
      ]);
    });

    test('BE placement fails: partial banked, success=false, BE warning surfaced',
        () async {
      final fake = _FakeBinanceClient()
        ..stopMarketError = BinanceError(
          statusCode: 400,
          code: -2021,
          message: 'Order would immediately trigger.',
        );
      final logService = OrderLogService(store: _FakeKvStore());
      final executor =
          OrderExecutor(logService: logService, clientFactory: (_) => fake);

      final logEntry = _liveLongEntry();
      await logService.record(1, logEntry);

      final result = await executor.executePreTpPartial(
        userId: 1,
        logEntry: logEntry,
        keys: _keys(),
        grabFraction: 0.5,
      );

      expect(result.success, false);
      expect(result.entry!.preTpClosedAt, isNotNull,
          reason: 'partial fill persisted so we do not re-bank on next tick');
      expect(result.entry!.breakevenStopOrderId, isNull);
      expect(result.message, contains('BE SL placement failed'));
      expect(result.message, contains('immediately trigger'));
    });
  });

}

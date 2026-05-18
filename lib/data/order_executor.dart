/// Order execution — composes a Binance Futures order triplet from a
/// signal and the user's per-user settings.
///
/// Phase 3b-1.  No autonomy: the caller (TakeSignalSheet) decides
/// when to invoke ``placeFromSignal``; this module only does the
/// composition + the three REST calls + the idempotency wrap.
///
/// Order shape (single entry + single bracket):
///
///   1. Market entry order (BUY for LONG, SELL for SHORT).
///   2. Stop-Market trigger order at the signal's SL.  ``closePosition=true``
///      so it flattens any quantity that's open — including a future DCA
///      add — without us having to track partial fills.
///   3. Take-Profit-Market trigger order at the signal's TP1.
///      ``reduceOnly=true`` + explicit qty so a runner can carry past TP1.
///
/// We do NOT cancel previous orders on the same symbol or check for
/// existing positions — that's an explicit owner trade-off for v0:
/// the user takes ONE signal at a time per symbol, and they're in
/// the confirm loop.  Phase 3b-2 / 3c will add cross-position-state
/// awareness when autonomy is wired.
///
/// Returns an ``ExecutionResult`` that lifts the three broker calls'
/// outcomes into one place so the caller can render success or partial
/// failure cleanly ("entry filled but SL placement failed — go to
/// Binance and place it manually").
library;

import 'binance_client.dart';
import 'binance_keys_service.dart';
import 'mock_data.dart';
import 'order_log.dart';
import 'repository.dart';

class ExecutionResult {
  const ExecutionResult({
    required this.success,
    required this.message,
    this.entry,
    this.alreadyTaken,
  });

  /// True when entry+SL+TP all placed.  False on partial or full
  /// failure; ``message`` carries the user-facing detail.
  final bool success;

  /// User-facing summary.  Caller surfaces this in a SnackBar.
  final String message;

  /// Recorded log entry on success (or partial — the log captures
  /// what got placed so a follow-up can patch the rest).  Null on
  /// hard failure where nothing was placed.
  final OrderLogEntry? entry;

  /// Set when the idempotency log already had an entry for this
  /// signal_id — the caller can short-circuit and show "already
  /// taken @ $X" instead of re-firing.
  final OrderLogEntry? alreadyTaken;
}

/// Factory for the Binance client used by ``OrderExecutor``.  Default
/// constructs a real :class:`BinanceClient`; tests inject a fake that
/// implements :class:`BinanceClientApi` to exercise the broker-call
/// paths without touching the network.
typedef BinanceClientFactory = BinanceClientApi Function(BinanceKeys keys);

BinanceClientApi _defaultBinanceClientFactory(BinanceKeys keys) =>
    BinanceClient(
      apiKey: keys.apiKey,
      apiSecret: keys.apiSecret,
      testnet: keys.testnet,
    );

class OrderExecutor {
  OrderExecutor({
    OrderLogService? logService,
    BinanceClientFactory? clientFactory,
  })  : _logService = logService ?? OrderLogService(),
        _clientFactory = clientFactory ?? _defaultBinanceClientFactory;

  final OrderLogService _logService;
  final BinanceClientFactory _clientFactory;

  /// Compose + place the order triplet for a signal.  ``signal`` is
  /// the engine's view (entry / SL / TP1 / direction / symbol);
  /// ``keys`` is the user's saved Binance credentials; ``settings``
  /// is their per-user auto-trade overrides.  ``equity`` is the
  /// user's current Binance wallet balance (from /fapi/v2/account)
  /// — used to size from ``positionSizePct``.
  ///
  /// ``executionMode`` is recorded in the order log:
  ///   * ``manual``    — user tapped Take Signal (default, 3b-1).
  ///   * ``auto-live`` — :class:`AutoTradeWatcher` fired it (3b-2).
  Future<ExecutionResult> placeFromSignal({
    required int userId,
    required MockSignal signal,
    required BinanceKeys keys,
    required AutoTradeSettings settings,
    required double equity,
    String executionMode = 'manual',
  }) async {
    // Idempotency first — never double-place.
    final existing = await _logService.entryFor(userId, signal.id);
    if (existing != null) {
      return ExecutionResult(
        success: true,
        alreadyTaken: existing,
        message: 'Already taken — order ${existing.entryOrderId} '
            'placed ${_age(existing.placedAt)} ago.',
      );
    }

    // Required settings.  v0 enforces explicit values; defaults from
    // engine-wide are inherited at the API layer so this should
    // always be non-null when the user has clicked through Pre-TP /
    // Auto-trade settings at least once.
    final sizingPct = settings.positionSizePct;
    final leverageReq = settings.leverageCap;
    if (sizingPct == null || sizingPct <= 0) {
      return _fail('Set position size on the Auto-trade page first.');
    }
    if (leverageReq == null || leverageReq <= 0) {
      return _fail('Set leverage cap on the Auto-trade page first.');
    }
    final leverageHardCapped = leverageReq.clamp(1.0, 30.0).toInt();

    // Compose order params.
    final side = signal.direction == 'LONG' ? 'BUY' : 'SELL';
    final closeSide = side == 'BUY' ? 'SELL' : 'BUY';

    final client = _clientFactory(keys);

    try {
      // Symbol filters — required for qty + price rounding to avoid
      // broker rejects.
      final filters = await client.getSymbolFilters(signal.symbol);

      // Size from equity × pct × leverage / price.  Subscriber default
      // leverage is 10x per OWNER_BRIEF B11; we use the user's
      // configured cap as the actual leverage for the position.
      final notional = equity * (sizingPct / 100.0) * leverageHardCapped;
      final rawQty = notional / signal.entry;
      final qty = filters.roundQty(rawQty);
      if (qty <= 0.0) {
        return _fail(
          'Size too small: ${rawQty.toStringAsFixed(6)} ${signal.symbol} '
          'rounds below minQty (${filters.minQty}). Increase position '
          'size or pick a higher-priced pair.',
        );
      }
      if (qty * signal.entry < filters.minNotional) {
        return _fail(
          'Notional too small: ${(qty * signal.entry).toStringAsFixed(2)} USDT '
          '< minNotional ${filters.minNotional} USDT. Increase position size.',
        );
      }

      // Round SL down (LONG) or up (SHORT) so the trigger sits at a
      // valid tick.  Same for TP in the opposite direction.
      final slPrice = filters.roundPrice(
        signal.sl,
        floor: signal.direction == 'LONG',
      );
      final tpPrice = filters.roundPrice(
        signal.tp1,
        floor: signal.direction == 'SHORT',
      );

      // Set leverage before the entry order — Binance requires the
      // per-symbol leverage to match the order's implicit leverage,
      // and a wrong call here returns -4028 "Leverage XX is not
      // valid".
      await client.setLeverage(signal.symbol, leverageHardCapped);

      // 1. Market entry.  signal_id as client order ID = idempotency
      //    at the broker layer too.
      final entryClientId = 'lumin-entry-${signal.id}';
      final entryOrder = await client.createMarketOrder(
        symbol: signal.symbol,
        side: side,
        quantity: qty,
        clientOrderId: entryClientId,
      );
      final entryId = (entryOrder['orderId'] as num?)?.toInt();
      final avgPrice = (entryOrder['avgPrice'] as num?)?.toDouble() ?? 0.0;

      // 2. Stop-Loss — closePosition flattens the lot at trigger.
      int? stopId;
      String? slError;
      try {
        final stopOrder = await client.createStopOrder(
          symbol: signal.symbol,
          side: closeSide,
          stopType: 'STOP_MARKET',
          stopPrice: slPrice,
          closePosition: true,
          clientOrderId: 'lumin-sl-${signal.id}',
        );
        stopId = (stopOrder['orderId'] as num?)?.toInt();
      } on BinanceError catch (e) {
        slError = 'SL placement failed: ${e.message}';
      }

      // 3. Take-Profit — reduceOnly + explicit qty so a runner can
      //    carry past TP1 if Phase 3b-2 adds laddered TP2/TP3.
      int? tpId;
      String? tpError;
      try {
        final tpOrder = await client.createStopOrder(
          symbol: signal.symbol,
          side: closeSide,
          stopType: 'TAKE_PROFIT_MARKET',
          stopPrice: tpPrice,
          quantity: qty,
          clientOrderId: 'lumin-tp1-${signal.id}',
        );
        tpId = (tpOrder['orderId'] as num?)?.toInt();
      } on BinanceError catch (e) {
        tpError = 'TP placement failed: ${e.message}';
      }

      final entry = OrderLogEntry(
        signalId: signal.id,
        symbol: signal.symbol,
        side: side,
        quantity: qty,
        entryOrderId: entryId,
        stopOrderId: stopId,
        tpOrderId: tpId,
        placedAt: DateTime.now().toUtc(),
        testnet: keys.testnet,
        avgFillPrice: avgPrice > 0 ? avgPrice : null,
        executionMode: executionMode,
        entryPriceTarget: signal.entry,
        slPrice: slPrice,
        tpPrice: tpPrice,
      );
      await _logService.record(userId, entry);

      if (slError != null || tpError != null) {
        // Partial success: entry placed but bracket incomplete.  Caller
        // surfaces a clear warning so the user can go fix it on Binance.
        return ExecutionResult(
          success: false,
          entry: entry,
          message: [
            'Entry placed (qty $qty @ ~${avgPrice.toStringAsFixed(2)})',
            if (slError != null) slError,
            if (tpError != null) tpError,
            'Place missing leg(s) manually on Binance.',
          ].join('\n'),
        );
      }
      return ExecutionResult(
        success: true,
        entry: entry,
        message: 'Order placed: $qty ${signal.symbol} '
            '@ ${avgPrice > 0 ? "\$${avgPrice.toStringAsFixed(4)}" : "market"}, '
            'SL ${slPrice.toStringAsFixed(4)}, TP1 ${tpPrice.toStringAsFixed(4)}.',
      );
    } on BinanceError catch (e) {
      return _fail('${e.message} (code ${e.code ?? "?"})');
    } catch (e) {
      return _fail('$e');
    } finally {
      client.dispose();
    }
  }

  /// Phase 4 — per-user pre-TP partial close.
  ///
  /// Called by :class:`AutoTradeWatcher` (live mode only) when it
  /// detects an ACTIVE signal where the engine reports
  /// ``preTpHit == true`` and the local order log has no
  /// ``preTpClosedAt`` for the user's entry.  Capital-preservation
  /// doctrine (OWNER_BRIEF §3.2a, B17): bank the user-configured
  /// fraction (clamped 0.30-1.00) at market, then replace the
  /// original SL with a new STOP_MARKET at entry price (breakeven)
  /// on the residual position.
  ///
  /// Idempotency layers:
  ///   1. Caller checks ``logEntry.preTpClosedAt == null`` before
  ///      invoking — local first-line guard.
  ///   2. Each broker call uses a deterministic ``clientOrderId``
  ///      (``lumin-pretp-{signalId}`` and ``lumin-be-{signalId}``)
  ///      so Binance rejects duplicates returned by the same call.
  ///   3. On success the updated entry is overwritten in the log
  ///      with ``preTpClosedAt`` set so a duplicate watcher tick
  ///      short-circuits at layer (1).
  ///
  /// Partial failure handling: cancel-then-replace splits the SL
  /// move into two broker calls.  We accept the partial-close fill
  /// even if the BE-SL replacement fails — the residual is left
  /// without an SL until the user notices.  Failure mode is logged
  /// in ``ExecutionResult.message`` and surfaced as a status banner
  /// by the watcher so the user can place the BE SL on Binance.
  Future<ExecutionResult> executePreTpPartial({
    required int userId,
    required OrderLogEntry logEntry,
    required BinanceKeys keys,
    required double grabFraction,
  }) async {
    // First-line idempotency.  Caller should already have checked
    // this; redundant check guards against direct callers (tests).
    if (logEntry.preTpClosedAt != null) {
      return ExecutionResult(
        success: true,
        entry: logEntry,
        message: 'Pre-TP already banked at '
            '${logEntry.preTpClosedAt!.toIso8601String()}.',
      );
    }

    // Clamp the user fraction into the B17 bounds defensively even
    // though the settings page already constrains the slider and the
    // backend rejects out-of-range writes.  ``clamp`` returns ``num``
    // when called on ``double``; coerce back so we keep ``double``
    // throughout the qty math.
    final double fraction = grabFraction.clamp(0.30, 1.00).toDouble();
    if (logEntry.entryOrderId == null || logEntry.quantity <= 0) {
      return _fail(
        'Pre-TP skipped: no entry on file for ${logEntry.symbol}.',
      );
    }
    if (logEntry.avgFillPrice == null || logEntry.avgFillPrice! <= 0) {
      return _fail(
        'Pre-TP skipped: missing entry fill price for ${logEntry.symbol}.',
      );
    }

    final client = _clientFactory(keys);
    try {
      final filters = await client.getSymbolFilters(logEntry.symbol);
      final partialQtyRaw = logEntry.quantity * fraction;
      final partialQty = filters.roundQty(partialQtyRaw);
      if (partialQty <= 0.0) {
        return _fail(
          'Pre-TP skipped: ${fraction * 100}% of ${logEntry.quantity} '
          '${logEntry.symbol} rounds below minQty (${filters.minQty}).',
        );
      }

      // Close side is the opposite of the entry side.  reduce-only
      // is enforced inside ``closePartialMarket``.
      final closeSide = logEntry.side == 'BUY' ? 'SELL' : 'BUY';

      // 1. MARKET reduce-only close for the partial.
      final partialFill = await client.closePartialMarket(
        symbol: logEntry.symbol,
        side: closeSide,
        quantity: partialQty,
        clientOrderId: 'lumin-pretp-${logEntry.signalId}',
      );
      final partialOrderId = (partialFill['orderId'] as num?)?.toInt();
      final partialAvg = (partialFill['avgPrice'] as num?)?.toDouble() ?? 0.0;

      // 2. Cancel the original SL.  closePosition=true on the
      //    original SL would flatten the residual at trigger time,
      //    which we now want at breakeven instead.  Swallow the
      //    "-2011 Unknown order" race — if the SL fired in the
      //    same window we'll detect it on the next status poll.
      String? cancelWarning;
      if (logEntry.stopOrderId != null) {
        try {
          await client.cancelOrder(
            symbol: logEntry.symbol,
            orderId: logEntry.stopOrderId,
          );
        } on BinanceError catch (e) {
          if (e.code != -2011) {
            cancelWarning =
                'Original SL cancel failed (${e.message}); BE SL not placed.';
          }
        }
      }

      // 3. Place new STOP_MARKET at entry price (breakeven) on the
      //    residual.  closePosition=true so any DCA add or residual
      //    gets flattened on trigger.
      int? beStopId;
      String? beWarning;
      if (cancelWarning == null) {
        final bePrice = filters.roundPrice(
          logEntry.avgFillPrice!,
          floor: logEntry.side == 'BUY', // LONG: floor; SHORT: ceil
        );
        try {
          final beOrder = await client.createStopOrder(
            symbol: logEntry.symbol,
            side: closeSide,
            stopType: 'STOP_MARKET',
            stopPrice: bePrice,
            closePosition: true,
            clientOrderId: 'lumin-be-${logEntry.signalId}',
          );
          beStopId = (beOrder['orderId'] as num?)?.toInt();
        } on BinanceError catch (e) {
          beWarning = 'BE SL placement failed: ${e.message}';
        }
      }

      final updated = logEntry.copyWith(
        preTpClosedAt: DateTime.now().toUtc(),
        preTpQty: partialQty,
        preTpOrderId: partialOrderId,
        preTpFillPrice: partialAvg > 0 ? partialAvg : null,
        breakevenStopOrderId: beStopId,
        grabFractionApplied: fraction,
        // Clear the original stopOrderId if cancel succeeded so the
        // log reflects what's actually live on Binance.
        clearStopOrderId: cancelWarning == null,
      );
      await _logService.record(userId, updated);

      if (cancelWarning != null || beWarning != null) {
        return ExecutionResult(
          success: false,
          entry: updated,
          message: [
            'Pre-TP banked: ${(fraction * 100).toStringAsFixed(0)}% '
                '(${partialQty} @ ~${partialAvg.toStringAsFixed(4)})',
            if (cancelWarning != null) cancelWarning,
            if (beWarning != null) beWarning,
            'Residual still open; place BE SL on Binance.',
          ].join('\n'),
        );
      }
      return ExecutionResult(
        success: true,
        entry: updated,
        message: 'Pre-TP banked ${(fraction * 100).toStringAsFixed(0)}% '
            '($partialQty ${logEntry.symbol} @ '
            '${partialAvg > 0 ? "\$${partialAvg.toStringAsFixed(4)}" : "market"}), '
            'SL moved to breakeven on residual.',
      );
    } on BinanceError catch (e) {
      return _fail('Pre-TP: ${e.message} (code ${e.code ?? "?"})');
    } catch (e) {
      return _fail('Pre-TP: $e');
    } finally {
      client.dispose();
    }
  }

  /// Paper-mode recording — same shape as a live entry but without
  /// any Binance call.  Used by :class:`AutoTradeWatcher` when the
  /// user's auto-trade mode is ``paper``.  Sizes against the same
  /// math live would have used (equity × pct × leverage) so the
  /// paper log shows realistic "would have been" qty.  No equity
  /// fetch here — the watcher passes a fake equity (default 10k USDT)
  /// or zero; either way the math is honest about being a simulation.
  Future<ExecutionResult> recordPaper({
    required int userId,
    required MockSignal signal,
    required AutoTradeSettings settings,
    required double simulatedEquity,
  }) async {
    final existing = await _logService.entryFor(userId, signal.id);
    if (existing != null) {
      return ExecutionResult(
        success: true,
        alreadyTaken: existing,
        message: 'Paper: already recorded.',
      );
    }
    final sizingPct = settings.positionSizePct;
    final leverage = settings.leverageCap;
    if (sizingPct == null || leverage == null) {
      return _fail('Set position size + leverage on Auto-trade page first.');
    }
    final leverageCapped = leverage.clamp(1.0, 30.0).toInt();
    final side = signal.direction == 'LONG' ? 'BUY' : 'SELL';
    // Round qty to 6 decimals — Binance step sizes vary, but paper
    // mode skips the exchangeInfo round-trip; this is good enough for
    // a "would have placed" log.
    final qty = double.parse(
      ((simulatedEquity * (sizingPct / 100.0) * leverageCapped) / signal.entry)
          .toStringAsFixed(6),
    );
    final entry = OrderLogEntry(
      signalId: signal.id,
      symbol: signal.symbol,
      side: side,
      quantity: qty,
      entryOrderId: null,
      stopOrderId: null,
      tpOrderId: null,
      placedAt: DateTime.now().toUtc(),
      testnet: false,
      avgFillPrice: signal.entry,
      executionMode: 'auto-paper',
      entryPriceTarget: signal.entry,
      slPrice: signal.sl,
      tpPrice: signal.tp1,
    );
    await _logService.record(userId, entry);
    return ExecutionResult(
      success: true,
      entry: entry,
      message:
          'Paper: $qty ${signal.symbol} @ ${signal.entry.toStringAsFixed(4)} '
          '(simulated, no broker call).',
    );
  }

  ExecutionResult _fail(String message) =>
      ExecutionResult(success: false, message: message);

  String _age(DateTime t) {
    final delta = DateTime.now().toUtc().difference(t.toUtc());
    if (delta.inMinutes < 1) return '${delta.inSeconds}s';
    if (delta.inHours < 1) return '${delta.inMinutes}m';
    if (delta.inDays < 1) return '${delta.inHours}h';
    return '${delta.inDays}d';
  }
}

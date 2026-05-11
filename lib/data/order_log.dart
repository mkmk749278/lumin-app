/// Per-user order log — idempotency for signal-driven order placement.
///
/// Phase 3b-1.  When a user taps "Take signal" we want to fire one
/// entry / SL / TP triplet against Binance and never double-fire if
/// the user taps again, the app retries on a network blip, or
/// (Phase 3b-2) the auto-loop hits the same signal twice.
///
/// The log lives in ``flutter_secure_storage`` (same encryption +
/// per-device persistence as the keys themselves) under a per-user
/// key.  We could put it in shared_preferences but secure_storage is
/// where we already namespace per-user data, so keeping the model
/// consistent wins.
///
/// Format: one JSON object per user, mapping ``signal_id`` →
/// :class:`OrderLogEntry`.  Pruned to the most-recent 200 entries on
/// every write so the blob stays small (each entry is ~200 bytes).
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OrderLogEntry {
  const OrderLogEntry({
    required this.signalId,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.entryOrderId,
    required this.stopOrderId,
    required this.tpOrderId,
    required this.placedAt,
    required this.testnet,
    this.avgFillPrice,
    this.executionMode = 'manual',
    this.entryPriceTarget,
    this.slPrice,
    this.tpPrice,
  });

  /// Engine's signal_id — the idempotency key.  Also wired into
  /// each Binance order's ``newClientOrderId`` so even a retry that
  /// bypasses this log can't double-submit.
  final String signalId;

  final String symbol;
  final String side; // BUY / SELL (the entry side; SL/TP are inverted)
  final double quantity;

  /// Binance's broker-side order ID for the entry market order.  Null
  /// when the entry placement itself failed; also null for paper-mode
  /// auto-trades (no broker call was made).
  final int? entryOrderId;

  /// Reduce-only stop-loss trigger order.  Null when SL placement
  /// failed after entry succeeded (UX surfaces this with a warning),
  /// or for paper-mode entries.
  final int? stopOrderId;

  /// Take-profit trigger order at TP1.  Null when TP placement failed
  /// or for paper-mode entries.
  final int? tpOrderId;

  final DateTime placedAt;
  final bool testnet;

  /// avgPrice from the entry order response.  Useful for "Taken @ $X"
  /// display next to the signal once filled.  For paper entries this
  /// is the signal's nominal entry price.
  final double? avgFillPrice;

  /// How this entry was triggered:
  ///   * ``manual``    — user tapped Take Signal on the detail sheet
  ///                     (Phase 3b-1).  Default for backwards-compat
  ///                     with already-persisted entries.
  ///   * ``auto-live`` — :class:`AutoTradeWatcher` fired this on new
  ///                     signal arrival; real Binance orders placed.
  ///   * ``auto-paper`` — watcher would-have-fired; no broker call.
  ///                     Used for trust-building before flipping to
  ///                     live.
  final String executionMode;

  /// Nominal entry price from the signal.  For manual entries we have
  /// ``avgFillPrice`` post-fill; for paper entries we record the
  /// signal's entry as a notional "if you'd taken it" price.
  final double? entryPriceTarget;

  /// Rounded SL price actually sent to Binance (or recorded for paper).
  final double? slPrice;

  /// Rounded TP1 price actually sent (or recorded for paper).
  final double? tpPrice;

  bool get isPaper => executionMode == 'auto-paper';
  bool get isAuto => executionMode.startsWith('auto-');

  Map<String, dynamic> toJson() => {
        'signal_id': signalId,
        'symbol': symbol,
        'side': side,
        'quantity': quantity,
        if (entryOrderId != null) 'entry_order_id': entryOrderId,
        if (stopOrderId != null) 'stop_order_id': stopOrderId,
        if (tpOrderId != null) 'tp_order_id': tpOrderId,
        'placed_at': placedAt.toIso8601String(),
        'testnet': testnet,
        if (avgFillPrice != null) 'avg_fill_price': avgFillPrice,
        'execution_mode': executionMode,
        if (entryPriceTarget != null) 'entry_price_target': entryPriceTarget,
        if (slPrice != null) 'sl_price': slPrice,
        if (tpPrice != null) 'tp_price': tpPrice,
      };

  factory OrderLogEntry.fromJson(Map<String, dynamic> j) => OrderLogEntry(
        signalId: j['signal_id'] as String,
        symbol: j['symbol'] as String,
        side: j['side'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        entryOrderId: (j['entry_order_id'] as num?)?.toInt(),
        stopOrderId: (j['stop_order_id'] as num?)?.toInt(),
        tpOrderId: (j['tp_order_id'] as num?)?.toInt(),
        placedAt: DateTime.parse(j['placed_at'] as String),
        testnet: j['testnet'] as bool? ?? false,
        avgFillPrice: (j['avg_fill_price'] as num?)?.toDouble(),
        executionMode: j['execution_mode'] as String? ?? 'manual',
        entryPriceTarget: (j['entry_price_target'] as num?)?.toDouble(),
        slPrice: (j['sl_price'] as num?)?.toDouble(),
        tpPrice: (j['tp_price'] as num?)?.toDouble(),
      );
}

class OrderLogService {
  OrderLogService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kPrefix = 'order_log.user.';
  static const _kMaxEntries = 200;

  /// Read the log for ``userId``.  Returns empty map when no log
  /// exists or the blob is corrupt.
  Future<Map<String, OrderLogEntry>> load(int userId) async {
    final raw = await _storage.read(key: '$_kPrefix$userId');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, OrderLogEntry>{};
      decoded.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          try {
            result[k as String] = OrderLogEntry.fromJson(v);
          } catch (_) {
            // Skip malformed individual entries.
          }
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Returns the log entry for ``signalId`` if the user has already
  /// taken this signal, else null.  Used as the idempotency check
  /// before placing any Binance order.
  Future<OrderLogEntry?> entryFor(int userId, String signalId) async {
    final log = await load(userId);
    return log[signalId];
  }

  /// Append (or overwrite) the entry for ``signalId``.  Prunes the
  /// oldest entries beyond ``_kMaxEntries`` so the encrypted blob
  /// doesn't grow without bound.
  Future<void> record(int userId, OrderLogEntry entry) async {
    final log = await load(userId);
    log[entry.signalId] = entry;
    if (log.length > _kMaxEntries) {
      final sorted = log.entries.toList()
        ..sort((a, b) => b.value.placedAt.compareTo(a.value.placedAt));
      log
        ..clear()
        ..addEntries(sorted.take(_kMaxEntries));
    }
    final out = <String, dynamic>{
      for (final e in log.entries) e.key: e.value.toJson(),
    };
    await _storage.write(
      key: '$_kPrefix$userId',
      value: jsonEncode(out),
    );
  }

  /// Wipe — called from the Disconnect path on the API keys page so
  /// a user who's reconnected from scratch doesn't see stale "already
  /// taken" badges on signals that pre-date the reconnect.
  Future<void> clear(int userId) async {
    await _storage.delete(key: '$_kPrefix$userId');
  }
}

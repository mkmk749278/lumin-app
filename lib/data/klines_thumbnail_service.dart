/// Cached kline fetcher for the alert-card mini charts.
///
/// The Alerts feed shows a 100eyes-style chart thumbnail on every card;
/// naively that's one Binance klines request per visible card on every
/// rebuild.  This service makes it cheap and polite:
///
/// * memory cache keyed `symbol|tf` — a thumbnail is static context, so
///   entries live for max(one timeframe period, 5 min);
/// * in-flight de-duplication — N visible cards for the same symbol+tf
///   share one request;
/// * a small concurrency gate (3 parallel fetches) so the first paint of
///   a full feed doesn't burst dozens of requests;
/// * best-effort SharedPreferences disk layer (LRU-pruned) so a reopened
///   feed paints instantly offline.
///
/// All traffic goes to Binance public REST (`BinanceMarketData.klines`)
/// directly from the phone — zero load on the Lumin engine.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/charts/models/candle.dart';
import 'binance_market_data.dart';

class KlinesThumbnailService {
  KlinesThumbnailService._(this._md);

  @visibleForTesting
  KlinesThumbnailService.forTest(BinanceMarketData md) : _md = md;

  static KlinesThumbnailService? _instance;
  static KlinesThumbnailService get instance =>
      _instance ??= KlinesThumbnailService._(BinanceMarketData());

  final BinanceMarketData _md;

  static const Map<String, int> _tfSeconds = {
    '15m': 900,
    '1h': 3600,
    '4h': 14400,
  };

  /// Bars fetched per thumbnail: enough for ~60 painted candles plus the
  /// zone-start headroom (`first_touch_bars_ago` is capped engine-side).
  static const int fetchLimit = 96;

  static const int _maxDiskKeys = 40;
  static const int _maxParallel = 3;
  static const String _diskPrefix = 'thumb.';
  static const String _diskIndexKey = 'thumb.index';

  final Map<String, _CacheEntry> _memory = {};
  final Map<String, Future<List<Candle>>> _inFlight = {};
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  /// Disk writes are chained so concurrent fetches can't interleave the
  /// read-modify-write of the LRU index.  Exposed for tests to await.
  @visibleForTesting
  Future<void> diskWritesSettled = Future.value();

  static String _key(String symbol, String tf) => '$symbol|$tf';

  static Duration _ttl(String tf) =>
      Duration(seconds: (_tfSeconds[tf] ?? 3600).clamp(300, 14400).toInt());

  /// Candles for one thumbnail, newest last.  Serves memory → disk →
  /// network; concurrent callers for the same key share one fetch.
  Future<List<Candle>> get(String symbol, String tf) {
    final key = _key(symbol, tf);
    final cached = _memory[key];
    if (cached != null && !cached.isExpired(_ttl(tf))) {
      return Future.value(cached.candles);
    }
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _load(symbol, tf, key);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<List<Candle>> _load(String symbol, String tf, String key) async {
    final fromDisk = await _readDisk(key, _ttl(tf));
    if (fromDisk != null) {
      _memory[key] = fromDisk;
      return fromDisk.candles;
    }
    await _acquire();
    try {
      final candles = await _md.klines(
        symbol: symbol,
        interval: BinanceMarketData.intervals[tf] ?? tf,
        limit: fetchLimit,
      );
      final entry = _CacheEntry(candles, DateTime.now());
      _memory[key] = entry;
      diskWritesSettled =
          diskWritesSettled.then((_) => _writeDisk(key, entry));
      return candles;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < _maxParallel) {
      _active++;
      return;
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    await waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(); // hand the slot to the next waiter
    } else {
      _active--;
    }
  }

  // -------------------------------------------------------------------
  // Disk layer — best-effort, never throws, LRU-pruned
  // -------------------------------------------------------------------

  Future<_CacheEntry?> _readDisk(String key, Duration ttl) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_diskPrefix$key');
      if (raw == null) return null;
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      final fetchedAt = DateTime.fromMillisecondsSinceEpoch(
        (j['fetchedAt'] as num?)?.toInt() ?? 0,
      );
      final entry = _CacheEntry(
        [
          for (final row in (j['rows'] as List? ?? const []))
            if (row is List && row.length >= 6)
              Candle(
                time: (row[0] as num).toInt(),
                open: (row[1] as num).toDouble(),
                high: (row[2] as num).toDouble(),
                low: (row[3] as num).toDouble(),
                close: (row[4] as num).toDouble(),
                volume: (row[5] as num).toDouble(),
              ),
        ],
        fetchedAt,
      );
      if (entry.candles.isEmpty || entry.isExpired(ttl)) return null;
      return entry;
    } catch (_) {
      return null; // disk problems fall through to network
    }
  }

  Future<void> _writeDisk(String key, _CacheEntry entry) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        '$_diskPrefix$key',
        jsonEncode({
          'fetchedAt': entry.fetchedAt.millisecondsSinceEpoch,
          'rows': [
            for (final c in entry.candles)
              [c.time, c.open, c.high, c.low, c.close, c.volume],
          ],
        }),
      );
      // LRU index: most-recently-written last; prune the oldest beyond cap.
      final index = (p.getStringList(_diskIndexKey) ?? <String>[])
        ..remove(key)
        ..add(key);
      while (index.length > _maxDiskKeys) {
        final evicted = index.removeAt(0);
        await p.remove('$_diskPrefix$evicted');
      }
      await p.setStringList(_diskIndexKey, index);
    } catch (_) {/* best-effort */}
  }
}

class _CacheEntry {
  _CacheEntry(this.candles, this.fetchedAt);
  final List<Candle> candles;
  final DateTime fetchedAt;

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(fetchedAt) > ttl;
}

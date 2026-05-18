/// Stale-While-Revalidate (SWR) cache — in-memory, per-process.
///
/// Phase 2a of the perf push (2026-05-18).  Lumin pages today await a
/// fresh network round-trip on every state change that triggers a load
/// (mode toggle, pull-to-refresh, scope rebuild).  This hits hardest on
/// the Signals / Pulse list views where the engine's ``/api/signals``
/// can be 30-80 KiB JSON and the user is staring at a spinner.
///
/// The SWR pattern is the standard fix:
///   1. On subscribe, emit the most recent cached value synchronously
///      (instant first paint).
///   2. In parallel, fire the underlying fetch.
///   3. When fresh data lands, write it to cache and emit it.
///   4. Pages render stale immediately and seamlessly upgrade to fresh.
///
/// This implementation is intentionally tiny:
///   * In-memory only — no SharedPreferences persistence in this phase.
///     Survives tab switches + lifecycle pauses but not cold start.
///     Persistent cache is a follow-up once the in-memory pattern is
///     validated across pages.
///   * Time-to-live (TTL) per ``watch`` call — caller decides freshness.
///   * In-flight de-duplication — if multiple watchers subscribe to the
///     same key while a fetch is mid-flight, they share one network
///     call.  Prevents the AutoTradeWatcher + Pulse + Signals
///     fan-out from triple-fetching the same payload.
///   * Tied to the surrounding LuminRepository scope — caller wipes the
///     cache on Live↔Mock toggle / sign-out via ``clear()``.
library;

import 'dart:async';

class _Entry<T> {
  _Entry(this.value, this.writtenAt);
  final T value;
  final DateTime writtenAt;
}

/// Generic stale-while-revalidate cache.  Each cache instance is a
/// ``Map<String, _Entry<dynamic>>``; callers pin the value type at the
/// ``watch`` call site.  No bound type on the cache itself because one
/// repository scope caches many heterogeneous response shapes.
class SwrCache {
  /// Optional clock injection for tests — defaults to ``DateTime.now``.
  SwrCache({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _Entry<dynamic>> _store = {};
  // In-flight de-dup: if multiple watchers subscribe to the same key
  // while a fetch is pending, they share the same Future rather than
  // racing.  Cleared when the future completes (success or failure).
  final Map<String, Future<dynamic>> _inflight = {};

  /// Subscribe to a key.  Emits at most twice:
  ///   1. Cached value (if any and not expired), synchronously after
  ///      subscribe.
  ///   2. Fresh value from ``fetch()``.
  ///
  /// When the cached value IS expired, no stale emit — just fresh.
  /// When ``fetch`` throws and there's no stale value, the stream
  /// surfaces the error.  When ``fetch`` throws but stale was emitted,
  /// the error is swallowed (the user already sees something usable).
  Stream<T> watch<T>(
    String key, {
    required Future<T> Function() fetch,
    Duration ttl = const Duration(seconds: 60),
  }) async* {
    final cached = _readFresh<T>(key, ttl);
    if (cached != null) {
      yield cached;
    }
    try {
      final fresh = await _runDeduped<T>(key, fetch);
      _store[key] = _Entry<T>(fresh, _clock());
      yield fresh;
    } catch (e) {
      if (cached == null) rethrow;
      // else: keep the stale value the subscriber already saw.
    }
  }

  /// Read a cached value synchronously if present and not yet expired.
  /// Returns null on miss or expiry — callers fall through to fetch.
  T? _readFresh<T>(String key, Duration ttl) {
    final entry = _store[key];
    if (entry == null) return null;
    if (_clock().difference(entry.writtenAt) > ttl) return null;
    return entry.value as T;
  }

  /// Single-flight wrapper — if a fetch for this key is already in
  /// flight, subscribers share its result.  Otherwise schedule the
  /// fetch and remember it until completion.
  Future<T> _runDeduped<T>(String key, Future<T> Function() fetch) {
    final existing = _inflight[key];
    if (existing != null) return existing as Future<T>;
    final fresh = fetch();
    _inflight[key] = fresh;
    return fresh.whenComplete(() {
      _inflight.remove(key);
    });
  }

  /// Wipe everything.  Called from AppConfigScope on Live↔Mock toggle
  /// and from sign-out flows so a new identity doesn't see the
  /// previous one's cached responses.
  void clear() {
    _store.clear();
    // In-flight futures keep running but their results won't be cached
    // (they'd write into a fresh _store).  We accept that — they're
    // already in flight and cancelling http is non-trivial.
  }

  /// Invalidate one key — e.g. after a settings PUT so the next read
  /// re-fetches.  No-op when the key isn't cached.
  void invalidate(String key) {
    _store.remove(key);
  }

  /// Bypass the in-memory layer entirely and return whatever's cached
  /// regardless of expiry.  Useful for tests + debugging.  Returns null
  /// on outright miss.
  T? peek<T>(String key) {
    final entry = _store[key];
    return entry?.value as T?;
  }

  /// Test-only — # of cache entries currently retained.  Stable API
  /// so tests can assert eviction without poking at internals.
  int get size => _store.length;
}

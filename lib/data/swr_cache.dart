/// Stale-While-Revalidate (SWR) cache — in-memory with optional
/// SharedPreferences persistence.
///
/// Phase 2a (2026-05-18): in-memory SWR pattern — instant tab re-entry
/// within the same session.
/// Phase 2b (2026-05-29): optional persistence — callers pass [persistKey],
/// [toJson], and [fromJson] to survive cold app restarts.  On cold open the
/// stored value is emitted synchronously before the network fetch completes,
/// eliminating the blank-screen-until-data window.
///
/// Persistence is opt-in per [watch] call — callers that omit [persistKey]
/// behave exactly as before.  If SharedPreferences throws, the cache degrades
/// gracefully to in-memory-only.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
  SwrCache({
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefsFactory,
  })  : _clock = clock ?? DateTime.now,
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _prefsFactory;

  final Map<String, _Entry<dynamic>> _store = {};
  // In-flight de-dup: if multiple watchers subscribe to the same key
  // while a fetch is pending, they share the same Future rather than
  // racing.  Cleared when the future completes (success or failure).
  final Map<String, Future<dynamic>> _inflight = {};
  // Keys that were explicitly invalidated (via pull-to-refresh).  The
  // next watch() call consumes the flag and skips the SharedPreferences
  // warm-emit so the spinner only releases when real server data lands.
  final Set<String> _bypassed = {};

  SharedPreferences? _prefs;
  bool _prefsLoaded = false;

  Future<SharedPreferences?> _getPrefs() async {
    if (_prefsLoaded) return _prefs;
    _prefsLoaded = true;
    try {
      _prefs = await _prefsFactory();
    } catch (_) {
      // SharedPreferences unavailable — degrade to in-memory-only.
    }
    return _prefs;
  }

  /// Subscribe to a key.  Emits at most three times:
  ///   1. In-memory cached value (if any and not expired), synchronously.
  ///   2. Persisted value from SharedPreferences (cold-open warm-start),
  ///      if [persistKey] + [fromJson] are provided and the stored value
  ///      is within [maxPersistAge].  Skipped when in-memory already hit.
  ///   3. Fresh value from ``fetch()``.
  ///
  /// When the cached value IS expired, no stale emit — just fresh.
  /// When ``fetch`` throws and there's no stale value, the stream
  /// surfaces the error.  When ``fetch`` throws but stale was emitted,
  /// the error is swallowed (the user already sees something usable).
  Stream<T> watch<T>(
    String key, {
    required Future<T> Function() fetch,
    Duration ttl = const Duration(seconds: 60),
    String? persistKey,
    String Function(T)? toJson,
    T? Function(String)? fromJson,
    Duration maxPersistAge = const Duration(hours: 4),
  }) async* {
    // Consume the bypass flag — set by invalidate() on pull-to-refresh.
    // When set, skip both in-memory and SharedPreferences so the spinner
    // only releases when real server data arrives, not stale persisted data.
    final skipCached = _bypassed.remove(key);
    final cached = skipCached ? null : _readFresh<T>(key, ttl);
    if (cached != null) {
      yield cached;
    } else if (!skipCached && persistKey != null && fromJson != null) {
      // Cold-start: no in-memory value — check SharedPreferences.
      final prefs = await _getPrefs();
      final raw = prefs?.getString(persistKey);
      if (raw != null) {
        try {
          final wrapper = jsonDecode(raw) as Map<String, dynamic>;
          final storedAt = wrapper['t'] as int? ?? 0;
          final age = _clock().millisecondsSinceEpoch - storedAt;
          if (age < maxPersistAge.inMilliseconds) {
            final v = wrapper['v'] as String?;
            if (v != null) {
              final parsed = fromJson(v);
              if (parsed != null) {
                // Seed in-memory so within-session subsequent calls hit cache.
                _store[key] = _Entry<T>(parsed, _clock());
                yield parsed;
              }
            }
          }
        } catch (_) {
          // Malformed stored value — ignore and fetch fresh.
        }
      }
    }
    try {
      final fresh = await _runDeduped<T>(key, fetch);
      _store[key] = _Entry<T>(fresh, _clock());
      if (persistKey != null && toJson != null) {
        // Persist with timestamp for cold-open warm-start on next launch.
        final prefs = await _getPrefs();
        if (prefs != null) {
          final wrapper = jsonEncode({
            'v': toJson(fresh),
            't': _clock().millisecondsSinceEpoch,
          });
          prefs.setString(persistKey, wrapper);
        }
      }
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
    _bypassed.clear();
    // In-flight futures keep running but their results won't be cached
    // (they'd write into a fresh _store).  We accept that — they're
    // already in flight and cancelling http is non-trivial.
  }

  /// Invalidate one key — forces the next watch() call to skip both
  /// in-memory and SharedPreferences and go straight to a network fetch.
  /// Used by pull-to-refresh so the spinner only releases when real
  /// server data lands, not when stale persisted data is re-emitted.
  void invalidate(String key) {
    _store.remove(key);
    _bypassed.add(key);
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

/// Tests for ``lib/data/swr_cache.dart`` — the in-memory
/// stale-while-revalidate cache that the Phase-2a perf push wires into
/// ``HttpRepository.watchSignals``.
///
/// What we pin here:
///   * Cold subscribe (no cache yet) yields fresh once.
///   * Warm subscribe (cached + within TTL) yields stale immediately
///     then fresh — the SWR semantic the page-side perceived-speed
///     win depends on.
///   * Expired cache (past TTL) yields fresh only, no stale.
///   * In-flight de-duplication — concurrent watch calls on the same
///     key share a single fetch.  This is what makes the watcher +
///     pulse + signals fan-out NOT triple-fetch the same endpoint.
///   * Fetch errors surface to the stream when no stale was emitted,
///     and are swallowed when stale was emitted (user already sees
///     something usable).
///   * ``clear()`` + ``invalidate(key)`` drop entries as documented.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/swr_cache.dart';

void main() {
  group('SwrCache cold + warm + expired', () {
    test('cold subscribe yields fresh once (no stale emit)', () async {
      final cache = SwrCache();
      var fetchCalls = 0;
      final values = await cache
          .watch<int>('k', fetch: () async {
            fetchCalls++;
            return 42;
          })
          .toList();

      expect(values, [42]);
      expect(fetchCalls, 1);
    });

    test('warm subscribe (within TTL) yields stale then fresh', () async {
      final cache = SwrCache();
      // Prime the cache.
      await cache.watch<int>('k', fetch: () async => 1).toList();

      // Second subscribe should see stale immediately + fresh again.
      var fetchCalls = 0;
      final values = await cache.watch<int>('k', fetch: () async {
        fetchCalls++;
        return 2;
      }).toList();

      expect(values, [1, 2]);
      expect(fetchCalls, 1);
    });

    test('expired cache (past TTL) yields fresh only, no stale', () async {
      var now = DateTime.utc(2026, 5, 18, 12, 0, 0);
      final cache = SwrCache(clock: () => now);
      await cache
          .watch<int>('k', fetch: () async => 1, ttl: const Duration(seconds: 5))
          .toList();
      // Advance past TTL.
      now = now.add(const Duration(seconds: 10));

      final values = await cache
          .watch<int>('k', fetch: () async => 2, ttl: const Duration(seconds: 5))
          .toList();

      expect(values, [2],
          reason: 'stale entry is past TTL and must not emit');
    });
  });

  group('SwrCache in-flight dedup', () {
    test('two concurrent watchers on the same key share one fetch', () async {
      final cache = SwrCache();
      var fetchCalls = 0;
      final fetchCompleter = Completer<int>();

      Future<int> fetch() {
        fetchCalls++;
        return fetchCompleter.future;
      }

      final s1 = cache.watch<int>('k', fetch: fetch).toList();
      final s2 = cache.watch<int>('k', fetch: fetch).toList();
      // Let event loop deliver subscriptions before completing.
      await Future<void>.delayed(Duration.zero);

      fetchCompleter.complete(7);
      final r1 = await s1;
      final r2 = await s2;

      expect(r1, [7]);
      expect(r2, [7]);
      expect(fetchCalls, 1,
          reason: 'concurrent subscribers must share one network round-trip');
    });

    test('a new fetch runs after the in-flight slot is freed', () async {
      final cache = SwrCache();
      var fetchCalls = 0;
      Future<int> fetch() async {
        fetchCalls++;
        return fetchCalls;
      }

      await cache.watch<int>('a', fetch: fetch).toList();
      // Different key → fresh in-flight slot, fresh fetch.
      await cache.watch<int>('b', fetch: fetch).toList();

      expect(fetchCalls, 2);
    });
  });

  group('SwrCache error semantics', () {
    test('fetch error surfaces to stream when no stale was emitted', () async {
      final cache = SwrCache();
      final stream = cache.watch<int>(
        'k',
        fetch: () => Future.error(Exception('boom')),
      );
      await expectLater(stream, emitsError(isA<Exception>()));
    });

    test('fetch error is swallowed when stale was already emitted', () async {
      final cache = SwrCache();
      await cache.watch<int>('k', fetch: () async => 1).toList();

      // Subscribe again — stale=1 should emit, then fetch throws.  The
      // stream should close cleanly with just the stale value (user
      // already has something usable; an error toast on top would be
      // noise).
      final values = await cache
          .watch<int>('k', fetch: () => Future.error(Exception('boom')))
          .toList();

      expect(values, [1]);
    });
  });

  group('SwrCache invalidation', () {
    test('clear() drops every entry', () async {
      final cache = SwrCache();
      await cache.watch<int>('a', fetch: () async => 1).toList();
      await cache.watch<int>('b', fetch: () async => 2).toList();
      expect(cache.size, 2);

      cache.clear();
      expect(cache.size, 0);
    });

    test('invalidate(key) drops only that entry', () async {
      final cache = SwrCache();
      await cache.watch<int>('a', fetch: () async => 1).toList();
      await cache.watch<int>('b', fetch: () async => 2).toList();

      cache.invalidate('a');
      expect(cache.peek<int>('a'), isNull);
      expect(cache.peek<int>('b'), 2);
    });

    test('peek<T>() returns regardless of TTL (debug helper)', () async {
      var now = DateTime.utc(2026, 5, 18);
      final cache = SwrCache(clock: () => now);
      await cache
          .watch<int>('k',
              fetch: () async => 1, ttl: const Duration(seconds: 1))
          .toList();
      now = now.add(const Duration(hours: 1)); // wildly past TTL

      // watch() would re-fetch, but peek bypasses TTL.
      expect(cache.peek<int>('k'), 1);
    });
  });
}

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

  group('SwrCache.read — the one-shot sibling of watch', () {
    // Added 2026-09-01 for the track record, whose every interaction (a
    // window chip, a month step, tapping a day, changing the size) fired two
    // or three UNCACHED round trips at ~0.8s each.  Stepping back to a month
    // already on screen re-fetched it.  That is what "always laggy" meant.

    test('a repeat inside the TTL is answered from memory', () async {
      var now = DateTime(2026, 9, 1, 12);
      final cache = SwrCache(clock: () => now);
      var calls = 0;
      Future<int> fetch() async {
        calls++;
        return 7;
      }

      expect(await cache.read<int>('k', fetch: fetch), 7);
      expect(await cache.read<int>('k', fetch: fetch), 7);
      expect(calls, 1);

      // Past the TTL it goes back to the network — the cache is a latency
      // fix, not a claim that the book stopped changing.
      now = now.add(const Duration(seconds: 61));
      expect(await cache.read<int>('k', fetch: fetch), 7);
      expect(calls, 2);
    });

    test('concurrent reads of one key share a single request', () async {
      // The track record's loaders fire together by design: a month step
      // calls the summary and the signal list in the same frame.
      final cache = SwrCache();
      var calls = 0;
      final gate = Completer<int>();
      Future<int> fetch() {
        calls++;
        return gate.future;
      }

      final a = cache.read<int>('k', fetch: fetch);
      final b = cache.read<int>('k', fetch: fetch);
      gate.complete(3);
      expect(await a, 3);
      expect(await b, 3);
      expect(calls, 1);
    });

    test('a different question is never served a cached answer', () async {
      final cache = SwrCache();
      var calls = 0;
      Future<String> fetch(String v) async {
        calls++;
        return v;
      }

      expect(await cache.read<String>('r:30::', fetch: () => fetch('a')), 'a');
      expect(
        await cache.read<String>('r::2026-08:250', fetch: () => fetch('b')),
        'b',
      );
      expect(calls, 2);
    });

    test('invalidate outranks a fresh entry', () async {
      // Pull-to-refresh must reach the network even one second after the
      // last read, or the spinner is theatre.
      final cache = SwrCache();
      var calls = 0;
      Future<int> fetch() async {
        calls++;
        return calls;
      }

      expect(await cache.read<int>('k', fetch: fetch), 1);
      cache.invalidate('k');
      expect(await cache.read<int>('k', fetch: fetch), 2);
    });

    test('invalidatePrefix drops every argument-keyed variant', () async {
      // ``read`` keys carry their arguments, so a refresh has no single name
      // to drop.  Dropping only some of them is worse than dropping none:
      // half the screen reaches the network and half is served from memory,
      // and it looks like it worked.
      final cache = SwrCache();
      var calls = 0;
      Future<int> fetch() async => ++calls;

      await cache.read<int>('track_record:30::', fetch: fetch);
      await cache.read<int>('track_record_signals:30:2026-08-31:200:',
          fetch: fetch);
      await cache.read<int>('pulse_bundle', fetch: fetch);
      expect(calls, 3);

      cache.invalidatePrefix('track_record');

      await cache.read<int>('track_record:30::', fetch: fetch);
      await cache.read<int>('track_record_signals:30:2026-08-31:200:',
          fetch: fetch);
      expect(calls, 5);
      // The unrelated key is untouched.
      await cache.read<int>('pulse_bundle', fetch: fetch);
      expect(calls, 5);
    });
  });
}

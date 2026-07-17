/// Tests for the per-user Binance API key store (2026-07-17).
///
/// This is the client-side execution path's key custody layer: the device
/// signs Binance Futures REST itself, so a bug here signs REAL orders with
/// the wrong user's keys or leaks keys across a sign-out → different-user
/// sign-in.  The properties pinned:
///
/// * strict per-user namespacing (`binance.user.<id>`) — user B's save
///   never touches user A's blob, and A's keys survive B's session;
/// * a corrupt blob is wiped and reads as "no keys", never a decode error
///   surfaced to the trade sheet;
/// * `save` stamps `savedAt` but never invents `lastVerifiedAt` — only a
///   successful Test-connection round-trip (`markVerified`) sets that;
/// * `clear` removes exactly one user's keys;
/// * serialization round-trips with defaults tolerant of older blobs.
///
/// Storage is faked in-memory at the constructor seam — no platform
/// channels, and (mirroring the hard limit) no key material ever leaves
/// the fake map.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/binance_keys_service.dart';

class _FakeStorage extends Fake implements FlutterSecureStorage {
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
}

const _keys = BinanceKeys(apiKey: 'key-A', apiSecret: 'secret-A', testnet: false);

void main() {
  late _FakeStorage storage;
  late BinanceKeysService service;

  setUp(() {
    storage = _FakeStorage();
    service = BinanceKeysService(storage: storage);
  });

  group('per-user isolation', () {
    test('keys are stored under the binance.user.<id> namespace', () async {
      await service.save(7, _keys);
      expect(storage.data.keys, ['binance.user.7']);
    });

    test('user B signing in does not see or disturb user A keys', () async {
      await service.save(1, _keys);
      await service.save(
        2,
        const BinanceKeys(apiKey: 'key-B', apiSecret: 'secret-B', testnet: true),
      );

      final a = await service.load(1);
      final b = await service.load(2);
      expect(a!.apiKey, 'key-A');
      expect(b!.apiKey, 'key-B');
      expect(b.testnet, isTrue);
      expect(a.testnet, isFalse);
    });

    test('clear wipes exactly one user', () async {
      await service.save(1, _keys);
      await service.save(
        2,
        const BinanceKeys(apiKey: 'key-B', apiSecret: 'secret-B', testnet: false),
      );
      await service.clear(1);
      expect(await service.load(1), isNull);
      expect((await service.load(2))!.apiKey, 'key-B');
    });
  });

  group('load', () {
    test('returns null when nothing is saved', () async {
      expect(await service.load(42), isNull);
    });

    test('corrupt blob is wiped and reads as no keys', () async {
      storage.data['binance.user.9'] = '{not valid json';
      expect(await service.load(9), isNull);
      // Wiped, so the next save starts clean instead of shadowing garbage.
      expect(storage.data.containsKey('binance.user.9'), isFalse);
    });

    test('blob with missing fields defaults instead of crashing', () async {
      // Tolerant-defaults convention: older blobs must not null-crash.
      storage.data['binance.user.9'] = '{}';
      final loaded = await service.load(9);
      expect(loaded, isNotNull);
      expect(loaded!.apiKey, '');
      expect(loaded.isValid, isFalse);
    });
  });

  group('save / markVerified', () {
    test('save stamps savedAt but never lastVerifiedAt', () async {
      final stamped = await service.save(7, _keys);
      expect(stamped.savedAt, isNotNull);
      // Only a successful /fapi/v2/account round-trip may set this.
      expect(stamped.lastVerifiedAt, isNull);

      final reloaded = await service.load(7);
      expect(reloaded!.savedAt, isNotNull);
      expect(reloaded.lastVerifiedAt, isNull);
    });

    test('markVerified stamps lastVerifiedAt without touching the keys',
        () async {
      await service.save(7, _keys);
      final verified = await service.markVerified(7);
      expect(verified!.lastVerifiedAt, isNotNull);
      expect(verified.apiKey, 'key-A');
      expect(verified.apiSecret, 'secret-A');
    });

    test('markVerified on a user with no keys is a null no-op', () async {
      expect(await service.markVerified(404), isNull);
      expect(storage.data, isEmpty);
    });
  });

  group('BinanceKeys model', () {
    test('isValid requires both key and secret', () {
      expect(_keys.isValid, isTrue);
      expect(
        const BinanceKeys(apiKey: '', apiSecret: 's', testnet: false).isValid,
        isFalse,
      );
      expect(
        const BinanceKeys(apiKey: 'k', apiSecret: '', testnet: false).isValid,
        isFalse,
      );
    });

    test('toJson/fromJson round-trips including timestamps', () {
      final now = DateTime.utc(2026, 7, 17, 12);
      final full = _keys.copyWith(savedAt: now, lastVerifiedAt: now);
      final back = BinanceKeys.fromJson(full.toJson());
      expect(back.apiKey, 'key-A');
      expect(back.savedAt, now);
      expect(back.lastVerifiedAt, now);
    });

    test('unparseable timestamps degrade to null, not a crash', () {
      final back = BinanceKeys.fromJson({
        'api_key': 'k',
        'api_secret': 's',
        'testnet': true,
        'saved_at': 'garbage',
      });
      expect(back.savedAt, isNull);
      expect(back.testnet, isTrue);
    });
  });
}

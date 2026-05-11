/// Per-user Binance API keys — encrypted local storage.
///
/// Phase 3 of the per-user expansion.  Each user's key+secret+testnet-flag
/// is stored in flutter_secure_storage under a per-user namespace so a
/// sign-out → sign-in-different-user flow doesn't leak the previous
/// user's keys.  The engine never sees the keys.
///
/// Storage shape: a single JSON blob per user_id at key
/// ``binance.user.<id>``.  One read / one write per save — small,
/// atomic, easy to audit on disk inspection.
///
/// Lifecycle:
///   * AuthService.signOut() does NOT clear binance keys for the
///     signed-out user — they're per-user, not per-session.  If user
///     A signs in on this device next time, A's saved keys load
///     automatically.  If user B signs in, B's keys load and A's
///     sit untouched.
///   * To wipe a user's keys explicitly, call ``clear``.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BinanceKeys {
  const BinanceKeys({
    required this.apiKey,
    required this.apiSecret,
    required this.testnet,
    this.savedAt,
    this.lastVerifiedAt,
  });

  final String apiKey;
  final String apiSecret;
  final bool testnet;

  /// When the keys were last persisted (ISO-8601 UTC).
  final DateTime? savedAt;

  /// When the keys last passed a Test-connection (HTTP 200 from
  /// /fapi/v2/account).  Drives the "Verified Xm ago" indicator on
  /// the API keys page.
  final DateTime? lastVerifiedAt;

  bool get isValid =>
      apiKey.isNotEmpty && apiSecret.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'api_key': apiKey,
        'api_secret': apiSecret,
        'testnet': testnet,
        if (savedAt != null) 'saved_at': savedAt!.toIso8601String(),
        if (lastVerifiedAt != null)
          'last_verified_at': lastVerifiedAt!.toIso8601String(),
      };

  factory BinanceKeys.fromJson(Map<String, dynamic> j) => BinanceKeys(
        apiKey: j['api_key'] as String? ?? '',
        apiSecret: j['api_secret'] as String? ?? '',
        testnet: j['testnet'] as bool? ?? false,
        savedAt: j['saved_at'] != null
            ? DateTime.tryParse(j['saved_at'] as String)
            : null,
        lastVerifiedAt: j['last_verified_at'] != null
            ? DateTime.tryParse(j['last_verified_at'] as String)
            : null,
      );

  BinanceKeys copyWith({
    String? apiKey,
    String? apiSecret,
    bool? testnet,
    DateTime? savedAt,
    DateTime? lastVerifiedAt,
  }) =>
      BinanceKeys(
        apiKey: apiKey ?? this.apiKey,
        apiSecret: apiSecret ?? this.apiSecret,
        testnet: testnet ?? this.testnet,
        savedAt: savedAt ?? this.savedAt,
        lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      );
}

class BinanceKeysService {
  BinanceKeysService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kPrefix = 'binance.user.';

  /// Read the saved keys for ``userId`` (null if none saved).
  Future<BinanceKeys?> load(int userId) async {
    final raw = await _storage.read(key: '$_kPrefix$userId');
    if (raw == null || raw.isEmpty) return null;
    try {
      return BinanceKeys.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt blob — wipe so next save starts clean rather than
      // surfacing a confusing decode error.
      await clear(userId);
      return null;
    }
  }

  /// Persist ``keys`` for ``userId``.  Stamps ``savedAt`` to NOW; the
  /// caller decides whether to also stamp ``lastVerifiedAt`` (only set
  /// after a successful Test-connection round-trip).
  Future<BinanceKeys> save(int userId, BinanceKeys keys) async {
    final stamped = keys.copyWith(savedAt: DateTime.now().toUtc());
    await _storage.write(
      key: '$_kPrefix$userId',
      value: jsonEncode(stamped.toJson()),
    );
    return stamped;
  }

  /// Update only the ``lastVerifiedAt`` timestamp without touching the
  /// stored keys.  Called after a successful round-trip to
  /// /fapi/v2/account.
  Future<BinanceKeys?> markVerified(int userId) async {
    final existing = await load(userId);
    if (existing == null) return null;
    final updated = existing.copyWith(lastVerifiedAt: DateTime.now().toUtc());
    await _storage.write(
      key: '$_kPrefix$userId',
      value: jsonEncode(updated.toJson()),
    );
    return updated;
  }

  /// Wipe the saved keys for ``userId``.
  Future<void> clear(int userId) async {
    await _storage.delete(key: '$_kPrefix$userId');
  }
}

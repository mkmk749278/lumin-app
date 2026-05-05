/// Auth service — anonymous JWT lifecycle.
///
/// First launch: posts to ``/api/auth/anonymous`` and stores the JWT in
/// flutter_secure_storage (encrypted at-rest).  Subsequent calls reuse
/// the cached token until it's within the refresh window or has expired.
///
/// On a 401 from any API call, ``handleUnauthorized()`` clears the cached
/// JWT and forces the next request to re-mint anonymously.  This makes
/// server-side secret rotation invisible to the user — they see at most
/// a 200ms blip on one request.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthError implements Exception {
  AuthError(this.message);
  final String message;
  @override
  String toString() => 'AuthError: $message';
}

/// Refresh the JWT this many seconds *before* expiry to avoid a race
/// where the token was valid when sent but expired by the time the
/// server validates it.
const int _kRefreshLeadSeconds = 86400;

class _CachedToken {
  _CachedToken({required this.token, required this.expiresAt});
  final String token;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get needsRefresh =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: _kRefreshLeadSeconds)));

  Map<String, dynamic> toJson() => {
        'token': token,
        'expiresAt': expiresAt.toIso8601String(),
      };

  static _CachedToken fromJson(Map<String, dynamic> j) => _CachedToken(
        token: j['token'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
      );
}

class AuthService {
  AuthService({
    required this.baseUrl,
    FlutterSecureStorage? storage,
    http.Client? client,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  final String baseUrl;
  final FlutterSecureStorage _storage;
  final http.Client _client;

  static const _kStorageKey = 'lumin.auth.jwt';

  // In-memory cache so we don't hit secure storage on every request.
  // Reset on signOut() and after handleUnauthorized().
  _CachedToken? _cached;

  /// Returns a JWT suitable for use in an Authorization: Bearer header.
  /// Mints, refreshes, or reuses the cached token transparently.
  Future<String> getValidToken() async {
    // 1. In-memory cache
    if (_cached != null && !_cached!.isExpired && !_cached!.needsRefresh) {
      return _cached!.token;
    }

    // 2. Disk-backed cache
    if (_cached == null) {
      _cached = await _loadFromStorage();
    }

    // 3. Refresh window — try to extend without re-minting
    if (_cached != null && !_cached!.isExpired && _cached!.needsRefresh) {
      try {
        await _refresh(_cached!.token);
        return _cached!.token;
      } catch (_) {
        // Refresh failed — fall through to anonymous mint
      }
    }

    // 4. Cached token still valid?
    if (_cached != null && !_cached!.isExpired) {
      return _cached!.token;
    }

    // 5. Mint a fresh anonymous token
    await _mintAnonymous();
    return _cached!.token;
  }

  /// Called by the API client when a request returns 401.  Drops the
  /// cached token so the next ``getValidToken`` re-mints from scratch.
  /// The caller should then retry the original request once.
  Future<void> handleUnauthorized() async {
    _cached = null;
    await _storage.delete(key: _kStorageKey);
  }

  /// Hard reset — used by Settings → "Reset connection".
  Future<void> signOut() async {
    await handleUnauthorized();
  }

  // ---- internals --------------------------------------------------------

  Future<_CachedToken?> _loadFromStorage() async {
    try {
      final raw = await _storage.read(key: _kStorageKey);
      if (raw == null) return null;
      return _CachedToken.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt entry — wipe so next mint starts clean.
      await _storage.delete(key: _kStorageKey);
      return null;
    }
  }

  Future<void> _persist(_CachedToken t) async {
    _cached = t;
    await _storage.write(key: _kStorageKey, value: jsonEncode(t.toJson()));
  }

  Future<void> _mintAnonymous() async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/api/auth/anonymous');
    final resp = await _client
        .post(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw AuthError(
        'mint failed (${resp.statusCode}): ${_decodeDetail(resp.body)}',
      );
    }
    await _persist(_parseTokenResponse(resp.body));
  }

  Future<void> _refresh(String token) async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/api/auth/refresh');
    final resp = await _client
        .post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'token': token}),
        )
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw AuthError(
        'refresh failed (${resp.statusCode}): ${_decodeDetail(resp.body)}',
      );
    }
    await _persist(_parseTokenResponse(resp.body));
  }

  _CachedToken _parseTokenResponse(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final token = j['token'] as String;
    final expSeconds = (j['exp_seconds'] as num).toInt();
    return _CachedToken(
      token: token,
      // Subtract 30s to give us margin against clock skew between
      // device and server.
      expiresAt: DateTime.now().add(Duration(seconds: expSeconds - 30)),
    );
  }

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  static String _decodeDetail(String body) {
    if (body.isEmpty) return 'empty body';
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return '${j['detail']}';
    } catch (_) {}
    return body;
  }

  void dispose() => _client.close();
}

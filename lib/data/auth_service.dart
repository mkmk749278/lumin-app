/// Auth service — JWT lifecycle.
///
/// Phase 2 introduces phone-OTP authentication.  First launch shows a
/// phone-signin page that calls :func:`requestOtp` then
/// :func:`verifyOtpAndStore`.  The resulting user-id JWT is persisted to
/// flutter_secure_storage (encrypted at-rest) and reused/refreshed
/// transparently across app launches.
///
/// On a 401 from any API call, ``handleUnauthorized()`` clears the cached
/// JWT.  In production this surfaces as a sign-in re-prompt at the next
/// boot; in :const:`kDebugMode` the dev-bypass path on the phone-signin
/// page can re-mint an anonymous JWT.
///
/// The engine still supports ``/api/auth/anonymous`` post-Phase-2 — it
/// returns ``tier=all-access``.  We expose :func:`mintAnonymous` for
/// the dev-bypass path on the phone-signin page (debug builds) so the
/// CI / manual-test workflow doesn't require a working OTP delivery
/// stack.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Result of a successful ``POST /api/auth/request-otp``.
class OtpRequestResult {
  OtpRequestResult({required this.channelUsed, required this.expiresInSeconds});
  final String channelUsed; // "whatsapp" | "sms" | "log"
  final int expiresInSeconds;
}

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
  _CachedToken({required this.token, required this.expiresAt, this.tier});
  final String token;
  final DateTime expiresAt;
  // `tier` from the JWT payload (``owner`` / ``paid`` / ``free`` /
  // ``all-access``).  Surfaced by [AuthService.currentTier] so UI layers
  // can hide write controls on tier-gated endpoints (engine returns 403
  // for non-owner writes per PR #355; the app should not display the
  // Save button to a tier that can't use it).  Nullable for backwards
  // compatibility with persisted tokens from before this field shipped.
  final String? tier;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get needsRefresh =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: _kRefreshLeadSeconds)));

  Map<String, dynamic> toJson() => {
        'token': token,
        'expiresAt': expiresAt.toIso8601String(),
        if (tier != null) 'tier': tier,
      };

  static _CachedToken fromJson(Map<String, dynamic> j) => _CachedToken(
        token: j['token'] as String,
        expiresAt: DateTime.parse(j['expiresAt'] as String),
        tier: j['tier'] as String?,
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

  /// Quick boot-time check: does the device have a (non-corrupt, possibly
  /// expired) token in secure storage?  Used by main.dart to decide
  /// whether to show the phone-signin page on launch.  An expired token
  /// counts as "stored" — the in-flight refresh path will renew it; if
  /// refresh fails the user falls back to phone-signin via the 401 path.
  Future<bool> hasStoredToken() async {
    if (_cached != null) return true;
    final loaded = await _loadFromStorage();
    if (loaded == null) return false;
    _cached = loaded;
    return true;
  }

  /// Mint a fresh anonymous JWT (``sub=device-<uuid>``, ``tier=all-access``).
  /// Public so the debug-build phone-signin page can offer a "skip" path
  /// for CI / manual testing without a working OTP delivery stack.
  Future<void> mintAnonymous() => _mintAnonymous();

  /// Sign in with the engine's static ``API_AUTH_TOKEN``.  This is the
  /// owner-only bypass: the engine treats this exact bearer string as
  /// ``tier=owner`` (PR #355).  Validates by hitting an authenticated
  /// endpoint (`/api/pulse`); on success persists the token to secure
  /// storage with a long expiry so subsequent API calls just work.
  ///
  /// Owner uses this on first launch to skip the phone-OTP flow
  /// entirely.  If the engine rotates the static token, the next
  /// refresh attempt will 401 and the user will be punted back to
  /// signin — same path as a normal session expiry.
  Future<void> signInWithAdminToken(String token) async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/api/pulse');
    final resp = await _client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      throw AuthError(
        'admin-token signin failed (${resp.statusCode}): '
        '${_decodeDetail(resp.body)}',
      );
    }
    // Static token has no expiry server-side; pick a long window so the
    // refresh path (which would 401 against a non-JWT bearer) doesn't
    // fire during normal use.  If the token is ever rotated, the next
    // 401 from any API call clears the cache via handleUnauthorized.
    //
    // Tier is hard-coded to "owner" — engine PR #355 treats the static
    // admin token as owner-tier regardless of any tier claim, so the
    // UI should reflect that.  The /api/pulse 200 above confirmed the
    // token is valid; if it's not really admin-tier, the engine will
    // 403 on the first write attempt and the cache will clear.
    await _persist(_CachedToken(
      token: token,
      expiresAt: DateTime.now().add(const Duration(days: 365)),
      tier: 'owner',
    ));
  }

  /// Phase 2 — phone-OTP signin, step 1.  Asks the engine to send a
  /// 6-digit code to ``phone`` (E.164).  Returns the channel used so
  /// the caller can render the right hint ("check WhatsApp" vs "check
  /// SMS" vs "see logs").  Throws :class:`AuthError` on 429
  /// (rate-limited), 502 (delivery failed), 503 (auth not configured).
  Future<OtpRequestResult> requestOtp(String phone) async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/api/auth/request-otp');
    final resp = await _client
        .post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'phone': phone}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw AuthError(
        'request-otp failed (${resp.statusCode}): ${_decodeDetail(resp.body)}',
      );
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return OtpRequestResult(
      channelUsed: j['channel_used'] as String,
      expiresInSeconds: (j['expires_in_seconds'] as num).toInt(),
    );
  }

  /// Phase 2 — phone-OTP signin, step 2.  Submits ``code`` for ``phone``;
  /// on success the engine returns a user-id JWT carrying ``sub=user-<id>``
  /// and ``tier=<paid|free|owner>``.  We persist it the same way as the
  /// anonymous path, so all subsequent API calls flow unchanged.
  Future<void> verifyOtpAndStore(String phone, String code) async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/api/auth/verify-otp');
    final resp = await _client
        .post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'phone': phone, 'code': code}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw AuthError(
        'verify-otp failed (${resp.statusCode}): ${_decodeDetail(resp.body)}',
      );
    }
    await _persist(_parseTokenResponse(resp.body));
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

  /// Current tier from the cached JWT, or ``null`` if not yet signed in.
  /// Returned values match the engine's tier constants:
  /// ``"owner"`` / ``"paid"`` / ``"free"`` / ``"all-access"``.  UI layers
  /// use this to gate write controls (Save buttons on settings pages are
  /// hidden when the tier can't successfully POST/PUT — engine enforces
  /// 403 per PR #355).
  String? currentTier() => _cached?.tier;

  _CachedToken _parseTokenResponse(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final token = j['token'] as String;
    final expSeconds = (j['exp_seconds'] as num).toInt();
    // Engine returns the tier alongside the token on every mint /
    // refresh path.  Older payloads (pre-Phase-2) may omit it; in that
    // case we leave tier=null and the UI defaults to "non-owner".
    final tier = j['tier'] as String?;
    return _CachedToken(
      token: token,
      // Subtract 30s to give us margin against clock skew between
      // device and server.
      expiresAt: DateTime.now().add(Duration(seconds: expSeconds - 30)),
      tier: tier,
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

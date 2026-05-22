/// Auth service — Firebase-backed session lifecycle.
///
/// Replaces the previous local HS256 JWT mint/refresh path with the
/// Firebase Authentication SDK.  After this migration:
///
///   * SMS path: Firebase Phone Auth handles delivery + verification
///     directly (Play Integrity / SafetyNet on Android, no engine
///     round-trip for the code itself).
///   * Telegram path: app POSTs to the engine's
///     `/api/auth/telegram-otp/issue` and `/verify` endpoints; verify
///     returns a Firebase **custom token** which we exchange for a
///     real Firebase session via `signInWithCustomToken`.
///   * Every authorized engine API call carries
///     `Authorization: Bearer <Firebase ID token>`; the SDK
///     auto-refreshes the ID token on a ~1h cycle so the HTTP client
///     just calls [currentIdToken] before each request.
///
/// Tier / user_id / needs_onboarding used to be parsed out of the
/// local JWT payload.  Post-migration the engine returns them on the
/// telegram-otp verify response and (for SMS-only signins) when the
/// app first calls `/api/profile`.  We cache the latest values in
/// memory so the existing `AppConfigScope.tier` / `.userId` /
/// `.needsOnboarding` getters keep working without async plumbing
/// through every widget.
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Result of a successful `POST /api/auth/telegram-otp/issue`.
///
/// `channelUsed` is always `"telegram"` for this path — kept as a
/// field so the OTP-entry page can render a channel-aware hint
/// without special-casing.  `expiresInSeconds` drives the resend
/// countdown.
class TelegramOtpIssueResult {
  TelegramOtpIssueResult({
    required this.channelUsed,
    required this.expiresInSeconds,
  });
  final String channelUsed;
  final int expiresInSeconds;
}

class AuthError implements Exception {
  AuthError(this.message);
  final String message;
  @override
  String toString() => 'AuthError: $message';
}

/// Surface called by API client / auth pages / settings.
///
/// All Firebase interaction is funneled through this class so unit
/// tests (when we add them — deferred for this PR) can swap a
/// `FirebaseAuth` mock in via the optional constructor parameter.
class AuthService {
  AuthService({
    required this.baseUrl,
    FirebaseAuth? firebaseAuth,
    FlutterSecureStorage? storage,
    http.Client? client,
  })  : _auth = firebaseAuth ?? FirebaseAuth.instance,
        _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  final String baseUrl;
  final FirebaseAuth _auth;
  final FlutterSecureStorage _storage;
  final http.Client _client;

  // Cached metadata from the most recent telegram-otp verify response.
  // Populated on signin via custom token; survives until signOut /
  // process restart.  SMS-only signins leave this null — call sites
  // already tolerate that (they treat null as "not yet known, render
  // the safe default").
  int? _cachedUserId;
  String? _cachedTier;
  String? _cachedPaidUntil;
  bool _cachedNeedsOnboarding = false;

  // ---- Firebase session surface ----------------------------------------

  /// Live stream of the current Firebase user (null when signed out).
  /// Used by [_AuthGate] in `main.dart` to drive sign-in / nav-shell
  /// routing reactively.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Synchronous read of the current Firebase user.  Null when no
  /// session is active.  Prefer [authStateChanges] for UI; this is
  /// for one-shot boot-time checks.
  User? get currentUser => _auth.currentUser;

  /// Returns the current Firebase ID token, or null if no user is
  /// signed in.  Passing `forceRefresh: true` bypasses the SDK's
  /// in-memory cache and round-trips to Firebase — the API client
  /// uses that path on a 401 to handle the rare case where our
  /// cached token expired between auto-refresh cycles.
  Future<String?> currentIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return await user.getIdToken(forceRefresh);
  }

  // ---- SMS path (Firebase Phone Auth) ----------------------------------

  /// Kick off Firebase Phone Auth.  Three things can happen:
  ///
  ///   * `onCodeSent` fires once the SMS is dispatched (most common).
  ///     The caller advances to the OTP page; later calls
  ///     [confirmSmsCode] with the captured `verificationId`.
  ///   * `onAutoVerified` fires on devices where Play Integrity
  ///     completes invisible verification — there's no code to type.
  ///   * `onVerificationFailed` fires on any error before code-sent
  ///     (invalid number, quota exceeded, reCAPTCHA dismissed, etc.).
  Future<void> startSmsSignIn({
    required String phoneE164,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException error) onVerificationFailed,
    required void Function(UserCredential credential) onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      // SDK default is 30s — too tight for Indian carriers, where SMS
      // delivery routinely takes 30–60s.  By the time the user opens
      // the SMS, reads, and types, the verificationId is past its
      // server-side window and `signInWithCredential` rejects with
      // "The sms code has expired."  3 minutes covers worst-case
      // delivery + tester typing comfortably while still staying inside
      // Firebase's documented 5-minute max.
      timeout: const Duration(seconds: 180),
      verificationCompleted: (credential) async {
        final result = await _auth.signInWithCredential(credential);
        onAutoVerified(result);
      },
      verificationFailed: onVerificationFailed,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Exchange the `verificationId` (received via `onCodeSent`) and the
  /// user-typed 6-digit `code` for a Firebase session.
  Future<UserCredential> confirmSmsCode(
    String verificationId,
    String code,
  ) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: code,
    );
    return await _auth.signInWithCredential(credential);
  }

  // ---- Telegram path (engine-mediated custom token) --------------------

  /// Ask the engine to deliver a 6-digit code via Telegram to
  /// `phoneE164`.  Returns the channel hint + TTL so the OTP page can
  /// render the same UX as the legacy WhatsApp/SMS paths.
  Future<TelegramOtpIssueResult> startTelegramSignIn(String phoneE164) async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/api/auth/telegram-otp/issue');
    final resp = await _client
        .post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'phone_e164': phoneE164}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw AuthError(
        'telegram-otp/issue failed (${resp.statusCode}): '
        '${_decodeDetail(resp.body)}',
      );
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return TelegramOtpIssueResult(
      channelUsed: j['channel_used'] as String? ?? 'telegram',
      expiresInSeconds: (j['expires_in_seconds'] as num?)?.toInt() ?? 300,
    );
  }

  /// Submit `code` for `phoneE164`; on success the engine returns a
  /// Firebase **custom token** which we exchange for a real Firebase
  /// session.  The verify response also carries the user's tier /
  /// paid_until / needs_onboarding — we cache those here so the
  /// existing `AppConfigScope.tier` / `.userId` / `.needsOnboarding`
  /// getters keep returning sensible values without a follow-up
  /// engine round-trip.
  Future<UserCredential> confirmTelegramCode(
    String phoneE164,
    String code,
  ) async {
    final uri =
        Uri.parse('${_trimSlash(baseUrl)}/api/auth/telegram-otp/verify');
    final resp = await _client
        .post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'phone_e164': phoneE164, 'code': code}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw AuthError(
        'telegram-otp/verify failed (${resp.statusCode}): '
        '${_decodeDetail(resp.body)}',
      );
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final customToken = j['custom_token'] as String?;
    if (customToken == null || customToken.isEmpty) {
      throw AuthError('telegram-otp/verify response missing custom_token');
    }
    _cachedUserId = (j['user_id'] as num?)?.toInt();
    _cachedTier = j['tier'] as String?;
    _cachedPaidUntil = j['paid_until'] as String?;
    _cachedNeedsOnboarding = j['needs_onboarding'] as bool? ?? false;
    return await _auth.signInWithCustomToken(customToken);
  }

  // ---- Sign out + legacy cleanup ---------------------------------------

  /// Wipe the Firebase session.  Drops the cached engine metadata
  /// alongside so the next signin's getters don't surface stale tier.
  Future<void> signOut() async {
    _cachedUserId = null;
    _cachedTier = null;
    _cachedPaidUntil = null;
    _cachedNeedsOnboarding = false;
    await _auth.signOut();
  }

  /// One-shot cleanup on first post-migration launch: wipe any local
  /// JWT entries left behind by the pre-Firebase auth service so they
  /// don't sit in secure storage forever.  Idempotent — running it on
  /// every launch is harmless (`delete` is a no-op for missing keys).
  ///
  /// Called from `main.dart` after `Firebase.initializeApp` and before
  /// `runApp` so the keys are gone before any code path can read them.
  Future<void> cleanupLegacyJwtStorage() async {
    // The pre-migration key from the old AuthService (`_kStorageKey`).
    await _storage.delete(key: 'lumin.auth.jwt');
    // Defensive: a generic name some earlier iterations may have used.
    await _storage.delete(key: 'jwt_token');
  }

  // ---- Cached engine metadata (back-compat with old call sites) --------

  /// Current tier from the most recent telegram-otp verify, or null
  /// when not yet known (SMS-only signin, or pre-signin).  UI layers
  /// treat null as "show controls, let the engine 403 if needed".
  String? currentTier() => _cachedTier;

  /// Current `paid_until` ISO timestamp, or null when not yet known.
  String? currentPaidUntil() => _cachedPaidUntil;

  /// Current engine `user_id`, or null when not yet known.  Used as
  /// the per-user secure-storage namespace key for Binance API keys
  /// (Phase 3) so signing out as A and back in as B doesn't leak A's
  /// locally-stored keys to B.
  int? currentUserId() => _cachedUserId;

  /// Current `needs_onboarding` value.  False as the default so the
  /// existing signed-in user's first launch after this build doesn't
  /// get bounced into onboarding when the cache is empty — the
  /// engine recomputes it on the next `/api/profile` round-trip.
  bool currentNeedsOnboarding() => _cachedNeedsOnboarding;

  /// Mark the cached state as onboarded — called by SignupPage after
  /// a successful `PUT /api/profile` so the in-memory bit matches
  /// what the engine now stores.
  Future<void> markOnboarded() async {
    _cachedNeedsOnboarding = false;
  }

  /// Quick boot-time check: is a Firebase user currently signed in?
  /// Retained for back-compat with the splash-page gate; new code
  /// should subscribe to [authStateChanges] instead.
  Future<bool> hasStoredToken() async => _auth.currentUser != null;

  // ---- internals -------------------------------------------------------

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

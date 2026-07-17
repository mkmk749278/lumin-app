/// Persisted engine metadata (tier / user_id / paid_until / …) so a
/// signed-in user's entitlement survives an app restart.
///
/// Why this exists (2026-07-17): `AuthService` cached tier + user_id in
/// memory only, populated solely at OTP sign-in or Play purchase.  On a
/// cold start the Firebase session restores but the cache is empty, so a
/// paying Auto subscriber saw the free-tier upsell sheet and "Sign in
/// with phone first" until they happened to visit the Profile page.
/// This store is a **display cache only** — the engine remains the
/// entitlement source of truth (server-side gates enforce tier
/// regardless of what's persisted here), and the AuthGate refreshes it
/// from `GET /api/profile` on every cold start.
///
/// Keyed by Firebase UID so sign-out / sign-in-as-someone-else never
/// leaks tier or user_id across accounts (mirrors the per-user
/// namespacing of the Binance key store).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class EngineMetadata {
  const EngineMetadata({
    this.userId,
    this.tier,
    this.paidUntil,
    this.needsOnboarding = false,
    this.displayName,
  });

  final int? userId;
  final String? tier;
  final String? paidUntil;
  final bool needsOnboarding;
  final String? displayName;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'tier': tier,
        'paid_until': paidUntil,
        'needs_onboarding': needsOnboarding,
        'display_name': displayName,
      };

  factory EngineMetadata.fromJson(Map<String, dynamic> j) => EngineMetadata(
        userId: (j['user_id'] as num?)?.toInt(),
        tier: j['tier'] as String?,
        paidUntil: j['paid_until'] as String?,
        needsOnboarding: j['needs_onboarding'] as bool? ?? false,
        displayName: j['display_name'] as String?,
      );
}

class EngineMetadataStore {
  static String _key(String firebaseUid) => 'lumin.engineMeta.$firebaseUid';

  static Future<void> save(String firebaseUid, EngineMetadata meta) async {
    if (firebaseUid.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(firebaseUid), jsonEncode(meta.toJson()));
  }

  /// Null when nothing is stored for this UID or the stored blob is
  /// unreadable (never throws — a corrupt entry degrades to "not yet
  /// known", same as a fresh install).
  static Future<EngineMetadata?> load(String firebaseUid) async {
    if (firebaseUid.isEmpty) return null;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(firebaseUid));
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return EngineMetadata.fromJson(j);
    } catch (_) {}
    return null;
  }

  static Future<void> clear(String firebaseUid) async {
    if (firebaseUid.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(firebaseUid));
  }
}

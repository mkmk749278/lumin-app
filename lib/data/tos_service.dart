/// ToS acceptance state — per-device storage of the user's click-
/// through opt-in.
///
/// Stored in SharedPreferences with the key
/// :data:`_kTosAcceptanceKey`.  Doctrine reminder per OWNER_BRIEF
/// B18 + the resolved-decisions table in engine #431:
///
///   * Non-custodial of funds.
///   * Custodial of trade-authorisation keys only.
///   * No warranty / no insurance.
///   * Bounded blast radius (withdraw=off, IP whitelist, symbol
///     allowlist, position cap, circuit breakers).
///   * Not available to US users.
///
/// When the doctrine changes, bump :data:`latestTosVersion`.  Users
/// with a stale acceptance see the ToS page again on next attempt
/// to reach a doctrine-gated surface (currently: the server-side
/// execution connect page).
///
/// Known limitation: per-device storage means a re-install OR a new
/// device requires re-acceptance.  Acceptable for v1 because (a) the
/// gate is enforced before any sensitive action and (b) the user
/// must in any case re-connect their Binance key on a new device.
///
/// Future hardening: sync the acceptance state to Firestore
/// (engine-side endpoint or cloud_firestore dep) so it persists
/// across devices + carries IP / user-agent metadata for legal
/// audit.  Tracked in the 14-PR roadmap as a PR-13 follow-up.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';

/// The current ToS version.  Bump this when the doctrine changes
/// to force every user to re-accept.  Major bumps only — patch-level
/// text edits (typo fixes, formatting) keep the same version so we
/// don't re-prompt for trivial changes.
const String latestTosVersion = '1.0';

/// SharedPreferences key for the stored acceptance JSON.
const String _kTosAcceptanceKey = 'tos_acceptance';


class TosAcceptance {
  const TosAcceptance({
    required this.version,
    required this.acceptedAt,
    required this.userAgent,
  });

  final String version;
  final DateTime acceptedAt;
  final String userAgent;

  Map<String, dynamic> toJson() => {
        'version': version,
        'accepted_at': acceptedAt.toIso8601String(),
        'user_agent': userAgent,
      };

  factory TosAcceptance.fromJson(Map<String, dynamic> j) => TosAcceptance(
        version: j['version'] as String? ?? '',
        acceptedAt: DateTime.tryParse(j['accepted_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        userAgent: j['user_agent'] as String? ?? '',
      );
}


class TosService {
  /// Production constructor — uses ``SharedPreferences.getInstance``
  /// internally on first access.  Tests can pass a pre-built
  /// SharedPreferences via the injected getter so they don't need
  /// platform plugins.
  TosService({Future<SharedPreferences> Function()? prefsFactory})
      : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  /// True when the user has accepted at the current
  /// :data:`latestTosVersion` (or newer).  Older accepted versions
  /// return false so the user must re-accept after a doctrine
  /// change.
  Future<bool> isCurrentVersionAccepted() async {
    final accepted = await readAcceptance();
    if (accepted == null) return false;
    return _versionMeetsCurrent(accepted.version);
  }

  Future<TosAcceptance?> readAcceptance() async {
    final prefs = await _prefsFactory();
    final raw = prefs.getString(_kTosAcceptanceKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return TosAcceptance.fromJson(j);
    } catch (_) {
      // Corrupted JSON — treat as no acceptance so the gate fires.
      return null;
    }
  }

  /// Record a fresh acceptance at the current
  /// :data:`latestTosVersion`.  Overwrites any prior acceptance —
  /// upgrades (older → current) and downgrades (current → older,
  /// shouldn't happen) both replace the stored doc.
  Future<TosAcceptance> recordAcceptance() async {
    final acceptance = TosAcceptance(
      version: latestTosVersion,
      acceptedAt: DateTime.now().toUtc(),
      userAgent: _currentUserAgent(),
    );
    final prefs = await _prefsFactory();
    await prefs.setString(
      _kTosAcceptanceKey,
      jsonEncode(acceptance.toJson()),
    );
    return acceptance;
  }

  /// Test / debug helper — drop the stored acceptance so the gate
  /// fires on next check.  NOT exposed in production UI.
  Future<void> clearAcceptance() async {
    final prefs = await _prefsFactory();
    await prefs.remove(_kTosAcceptanceKey);
  }
}


bool _versionMeetsCurrent(String accepted) {
  // Lexicographic compare on the major version digit.  For v1.x
  // this is sufficient — every released ToS bumps the major when
  // the legal substance changes.  Patch-level edits keep the same
  // version and don't re-prompt.
  return accepted.compareTo(latestTosVersion) >= 0;
}


String _currentUserAgent() {
  // Best-effort user-agent string from dart:io.  On Web this throws
  // (no Platform); we wrap in try/catch and fall back to a generic
  // string.  Future hardening: use ``device_info_plus`` for richer
  // device fingerprint.
  try {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  } catch (_) {
    return 'unknown';
  }
}

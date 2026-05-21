/// Consent storage — persists the user's acknowledgement of the Play
/// Store-required first-run gates (18+ age + crypto trading risk +
/// "signals are not financial advice").
///
/// **Why this exists:** Google Play's Financial Services policy plus
/// the Cryptocurrency Exchanges & Software Wallets policy
/// (https://support.google.com/googleplay/android-developer/answer/16329703,
/// effective 2025-10-29) require apps with financial features to
/// surface risk disclosures before the user engages with the product.
/// We satisfy this with a one-shot first-run gate that captures
/// affirmative consent and stores it locally.
///
/// **Versioning:** if we ever materially update the risk disclosure
/// (e.g. add a new permission, change the data-collection scope), we
/// bump ``currentConsentVersion`` — any user whose stored version is
/// lower than the current value re-sees the gate.  This is the same
/// pattern the Apple Tracking Transparency and GDPR cookie-banner
/// libraries use.
library;

import 'package:shared_preferences/shared_preferences.dart';

class ConsentStorage {
  ConsentStorage._();

  /// Bump this when the disclosure copy materially changes (new data
  /// category, new permission, new feature with separate risk).
  /// Patch-level edits (typos, formatting) do NOT bump — the user
  /// shouldn't have to re-tap for cosmetic changes.
  static const int currentConsentVersion = 1;

  static const String _kVersionKey = 'consent.version';
  static const String _kAtKey = 'consent.acceptedAt';
  static const String _kWelcomeSeenKey = 'onboarding.welcomeSeen';

  /// Returns the stored consent version, or 0 if no consent recorded.
  static Future<int> storedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kVersionKey) ?? 0;
  }

  /// True iff the user has accepted a consent version that's still
  /// current.  False on first run AND on any release that bumps
  /// ``currentConsentVersion``.
  static Future<bool> isUpToDate() async {
    final v = await storedVersion();
    return v >= currentConsentVersion;
  }

  /// True iff the user has seen the first-launch welcome screen.
  /// Set once when the user taps "Get Started" on the welcome page.
  /// Independent of consent — welcome is brand intro + value-prop;
  /// consent is the legal acknowledgement that follows.  Tracking
  /// them separately means a consent-version bump doesn't re-show
  /// the welcome (which would feel like a regression).
  static Future<bool> welcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kWelcomeSeenKey) ?? false;
  }

  /// Mark the welcome page as seen.  One-shot — no version bump
  /// rationale here because the welcome page never re-shows once
  /// dismissed.
  static Future<void> recordWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWelcomeSeenKey, true);
  }

  /// Mark consent at the current version.  Persists the ISO 8601
  /// timestamp alongside in case we ever need it for support /
  /// audit / "when did the user agree to v2" troubleshooting.
  static Future<void> recordAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kVersionKey, currentConsentVersion);
    await prefs.setString(_kAtKey, DateTime.now().toUtc().toIso8601String());
  }

  /// Test / settings hook — drops the consent record AND the
  /// welcome-seen flag so the next app launch shows the full
  /// first-run flow again.  Not currently exposed in UI but useful
  /// for QA + a future "review consent" Settings entry.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kVersionKey);
    await prefs.remove(_kAtKey);
    await prefs.remove(_kWelcomeSeenKey);
  }
}

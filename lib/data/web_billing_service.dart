/// Web billing (Phase 3) client glue — the PWA's crypto (NOWPayments) rail.
///
/// The website sells the SAME two paid tiers as Google Play (`assist` /
/// `auto`) but through its own rails, because Play/Apple billing is
/// store-bound and a website is neither.  This service is the thin client
/// glue over the engine endpoints (the engine is the entitlement source of
/// truth — `docs/WEB_BILLING_DESIGN.md`):
///
///   1. `loadConfig()` — ask the engine which rails + prices to render.
///   2. `startCheckout(tier)` — the engine creates a NOWPayments invoice
///      server-side (its API key never touches the client, and it sets the
///      price — the client only names a tier), and we open the hosted
///      checkout page.
///   3. `pollEntitlement(...)` — crypto settles asynchronously on-chain, so
///      the client CANNOT know locally when funds land.  The signature-
///      verified IPN webhook grants the tier on the engine; we poll
///      `GET /api/profile` until the tier reaches what was bought, then
///      refresh the cached entitlement so the gate unlocks.
///
/// Web-only by construction: only the web build instantiates this (the Play
/// build keeps Play Billing), so it never ships inside the Play APK — Play's
/// anti-steering policy is honoured at compile time via `kDistribution`.
import 'dart:async';

import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'repository.dart';

class WebBillingService {
  WebBillingService({
    required this.repo,
    required this.auth,
    Future<bool> Function(Uri)? launcher,
  }) : _launch = launcher ??
            ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final LuminRepository repo;
  final AuthService auth;
  final Future<bool> Function(Uri) _launch;

  /// Tier precedence — a higher tier satisfies a lower purchase check.
  static const List<String> _order = ['free', 'assist', 'auto', 'owner'];

  Future<WebBillingConfig> loadConfig() => repo.fetchWebBillingConfig();

  /// Create a checkout for [tier] and open the hosted NOWPayments page.
  /// Returns the checkout so the caller can then poll for entitlement.
  Future<WebCheckout> startCheckout(String tier) async {
    final checkout = await repo.createWebCheckout(tier);
    if (checkout.invoiceUrl.isEmpty) {
      throw StateError('The payment provider returned no checkout URL.');
    }
    final ok = await _launch(Uri.parse(checkout.invoiceUrl));
    if (!ok) {
      throw StateError('Could not open the checkout page.');
    }
    return checkout;
  }

  /// Poll the engine until the tier reaches [wantTier] (or better) or
  /// [timeout] elapses.  On success, refreshes the cached entitlement so the
  /// free-tier gate unlocks without a restart.  Returns true iff entitled.
  Future<bool> pollEntitlement({
    required String wantTier,
    Duration timeout = const Duration(minutes: 10),
    Duration interval = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await checkEntitlementOnce(wantTier)) return true;
      await Future<void>.delayed(interval);
    }
    return false;
  }

  /// One-shot entitlement check — backs the "I've paid — check now" button.
  /// Swallows transient errors (returns false) so the caller can retry.
  Future<bool> checkEntitlementOnce(String wantTier) async {
    try {
      final profile = await repo.fetchProfile();
      final tier = profile.tier ?? 'free';
      if (_tierSatisfies(tier, wantTier)) {
        auth.applyEntitlement(tier: tier, paidUntil: profile.paidUntil);
        return true;
      }
    } catch (_) {
      // transient network / auth refresh — caller retries
    }
    return false;
  }

  bool _tierSatisfies(String have, String want) {
    if (have == want) return true;
    if (have == 'owner') return true;
    // 'paid' is the legacy single paid tier — counts for either paid SKU.
    if (have == 'paid') return want == 'assist' || want == 'auto';
    final h = _order.indexOf(have);
    final w = _order.indexOf(want);
    return h >= 0 && w >= 0 && h >= w;
  }
}

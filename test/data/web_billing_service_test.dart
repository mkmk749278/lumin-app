/// Tests for the web-billing client glue (Phase 3).
///
/// Doctrine under test: the ENGINE is the entitlement source of truth. The
/// client's only jobs are (1) create a checkout and open the hosted page,
/// (2) poll the engine for the tier the signature-verified webhook grants —
/// never a locally-derived one, (3) apply exactly what the engine returns.
/// A higher tier satisfies a lower purchase check; legacy `paid` counts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/auth_service.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/data/web_billing_service.dart';

class _FakeRepo extends Fake implements LuminRepository {
  WebCheckout checkout = const WebCheckout(
    ok: true,
    tier: 'auto',
    amountUsd: 25,
    invoiceUrl: 'https://nowpayments.example/pay/x',
    invoiceId: 'inv_1',
    orderId: 'luminweb:1:auto:abc',
  );
  Object? checkoutError;
  final List<String> checkoutCalls = [];

  /// Successive tiers returned by fetchProfile (simulates the webhook
  /// landing on a later poll). The last value repeats.
  List<String> tierSequence = ['free'];
  int _profileCalls = 0;

  @override
  Future<WebCheckout> createWebCheckout(String tier) async {
    checkoutCalls.add(tier);
    if (checkoutError != null) throw checkoutError!;
    return checkout;
  }

  @override
  Future<Profile> fetchProfile() async {
    final i =
        _profileCalls < tierSequence.length ? _profileCalls : tierSequence.length - 1;
    _profileCalls++;
    return Profile(tier: tierSequence[i], needsOnboarding: false);
  }
}

class _FakeAuth extends Fake implements AuthService {
  final List<(String, String?)> applied = [];

  @override
  void applyEntitlement({required String tier, String? paidUntil}) {
    applied.add((tier, paidUntil));
  }
}

void main() {
  late _FakeRepo repo;
  late _FakeAuth auth;
  final launched = <Uri>[];

  WebBillingService build({bool launchOk = true}) => WebBillingService(
        repo: repo,
        auth: auth,
        launcher: (u) async {
          launched.add(u);
          return launchOk;
        },
      );

  setUp(() {
    repo = _FakeRepo();
    auth = _FakeAuth();
    launched.clear();
  });

  group('startCheckout', () {
    test('creates the checkout and opens the invoice URL', () async {
      final c = await build().startCheckout('auto');
      expect(repo.checkoutCalls.single, 'auto');
      expect(c.orderId, 'luminweb:1:auto:abc');
      expect(launched.single.toString(), 'https://nowpayments.example/pay/x');
    });

    test('throws when the provider returns no URL', () async {
      repo.checkout = const WebCheckout(
        ok: true, tier: 'auto', amountUsd: 25,
        invoiceUrl: '', invoiceId: 'i', orderId: 'o',
      );
      expect(build().startCheckout('auto'), throwsStateError);
    });

    test('throws when the launcher cannot open the page', () async {
      expect(build(launchOk: false).startCheckout('auto'), throwsStateError);
    });
  });

  group('checkEntitlementOnce', () {
    test('applies the entitlement when the tier has been granted', () async {
      repo.tierSequence = ['auto'];
      final ok = await build().checkEntitlementOnce('auto');
      expect(ok, true);
      expect(auth.applied.single.$1, 'auto');
    });

    test('returns false and applies nothing while still free', () async {
      repo.tierSequence = ['free'];
      final ok = await build().checkEntitlementOnce('auto');
      expect(ok, false);
      expect(auth.applied, isEmpty);
    });

    test('a higher tier satisfies a lower purchase', () async {
      repo.tierSequence = ['auto'];
      expect(await build().checkEntitlementOnce('assist'), true);
    });

    test('owner satisfies any tier', () async {
      repo.tierSequence = ['owner'];
      expect(await build().checkEntitlementOnce('auto'), true);
    });

    test('legacy paid satisfies assist and auto', () async {
      repo.tierSequence = ['paid'];
      expect(await build().checkEntitlementOnce('auto'), true);
    });

    test('a lower tier does NOT satisfy a higher purchase', () async {
      repo.tierSequence = ['assist'];
      expect(await build().checkEntitlementOnce('auto'), false);
      expect(auth.applied, isEmpty);
    });
  });

  group('pollEntitlement', () {
    test('resolves true once the webhook-granted tier appears', () async {
      repo.tierSequence = ['free', 'free', 'auto'];
      final ok = await build().pollEntitlement(
        wantTier: 'auto',
        timeout: const Duration(seconds: 5),
        interval: const Duration(milliseconds: 1),
      );
      expect(ok, true);
      expect(auth.applied.single.$1, 'auto');
    });

    test('resolves false on timeout when no grant lands', () async {
      repo.tierSequence = ['free'];
      final ok = await build().pollEntitlement(
        wantTier: 'auto',
        timeout: const Duration(milliseconds: 10),
        interval: const Duration(milliseconds: 1),
      );
      expect(ok, false);
      expect(auth.applied, isEmpty);
    });
  });
}

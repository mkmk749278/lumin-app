/// Tests for the Play Billing client glue (B16, 2026-07-17).
///
/// Doctrine under test: the ENGINE is the entitlement source of truth.
/// The client's only jobs are (1) hand every purchased/restored token to
/// `POST /api/billing/play/verify`, (2) apply the tier the engine returned
/// — never a locally-derived one, (3) ALWAYS `completePurchase` so Play
/// stops re-delivering, even when verification fails (the engine's RTDN
/// reconciles later; "Restore purchases" is the user path).  A regression
/// on (3) makes Play re-deliver forever; on (2) it grants entitlement the
/// engine never confirmed.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lumin/data/auth_service.dart';
import 'package:lumin/data/play_billing_service.dart';
import 'package:lumin/data/repository.dart';

class _FakeIap extends Fake implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();
  final List<PurchaseDetails> completed = [];
  int listenCount = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    listenCount++;
    return controller.stream;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }
}

class _FakeRepo extends Fake implements LuminRepository {
  PlayVerifyResult result = const PlayVerifyResult(
    ok: true,
    tier: 'assist',
    subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
    paidUntil: '2026-08-17T00:00:00Z',
  );
  Object? error;
  final List<(String, String)> verifyCalls = [];

  @override
  Future<PlayVerifyResult> verifyPlayPurchase({
    required String productId,
    required String purchaseToken,
  }) async {
    verifyCalls.add((productId, purchaseToken));
    if (error != null) throw error!;
    return result;
  }
}

class _FakeAuth extends Fake implements AuthService {
  final List<(String, String?)> applied = [];

  @override
  void applyEntitlement({required String tier, String? paidUntil}) {
    applied.add((tier, paidUntil));
  }
}

PurchaseDetails _purchase(
  PurchaseStatus status, {
  String productId = 'lumin.assist.monthly',
  String token = 'play-token-1',
  bool pendingComplete = true,
}) {
  final pd = PurchaseDetails(
    purchaseID: 'order-1',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: token,
      source: 'google_play',
    ),
    transactionDate: '1752750000000',
    status: status,
  );
  pd.pendingCompletePurchase = pendingComplete;
  return pd;
}

void main() {
  late _FakeIap iap;
  late _FakeRepo repo;
  late _FakeAuth auth;
  late PlayBillingService service;
  late List<PlayBillingEvent> events;
  late StreamSubscription eventsSub;

  setUp(() {
    iap = _FakeIap();
    repo = _FakeRepo();
    auth = _FakeAuth();
    service = PlayBillingService(repo: repo, auth: auth, iap: iap);
    events = [];
    eventsSub = service.events.listen(events.add);
    service.start();
  });

  tearDown(() async {
    await eventsSub.cancel();
    await service.dispose();
    await iap.controller.close();
  });

  Future<void> deliver(PurchaseDetails pd) async {
    iap.controller.add([pd]);
    // Let the stream handler and its awaited verify round-trip settle.
    await pumpEventQueue();
  }

  group('verified purchase', () {
    test('token goes to the engine and the engine tier is applied', () async {
      await deliver(_purchase(PurchaseStatus.purchased));

      expect(repo.verifyCalls.single,
          ('lumin.assist.monthly', 'play-token-1'));
      // The tier applied is the one the ENGINE returned — not derived
      // client-side from the product id.
      expect(auth.applied.single, ('assist', '2026-08-17T00:00:00Z'));
      expect(events.single.status, PlayBillingStatus.entitled);
      expect(iap.completed, hasLength(1));
    });

    test('restored purchases verify exactly like fresh ones', () async {
      await deliver(_purchase(PurchaseStatus.restored));
      expect(repo.verifyCalls, hasLength(1));
      expect(events.single.status, PlayBillingStatus.entitled);
    });

    test('engine saying not-entitled applies NO tier locally', () async {
      repo.result = const PlayVerifyResult(
        ok: true,
        tier: 'free',
        subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED',
      );
      await deliver(_purchase(PurchaseStatus.purchased));

      expect(auth.applied, isEmpty);
      expect(events.single.status, PlayBillingStatus.notEntitled);
      expect(events.single.message, 'SUBSCRIPTION_STATE_EXPIRED');
      // Still completed — Play must stop re-delivering regardless.
      expect(iap.completed, hasLength(1));
    });

    test('verification failure still completes the purchase', () async {
      // RTDN reconciles entitlement later; an incomplete purchase would
      // make Play re-deliver forever.
      repo.error = Exception('engine unreachable');
      await deliver(_purchase(PurchaseStatus.purchased));

      expect(auth.applied, isEmpty);
      expect(events.single.status, PlayBillingStatus.error);
      expect(iap.completed, hasLength(1));
    });

    test('already-completed purchases are not re-completed', () async {
      await deliver(
          _purchase(PurchaseStatus.purchased, pendingComplete: false));
      expect(iap.completed, isEmpty);
      expect(events.single.status, PlayBillingStatus.entitled);
    });
  });

  group('non-purchase events', () {
    test('pending emits pending and nothing else happens', () async {
      await deliver(_purchase(PurchaseStatus.pending, pendingComplete: false));
      expect(events.single.status, PlayBillingStatus.pending);
      expect(repo.verifyCalls, isEmpty);
      expect(auth.applied, isEmpty);
    });

    test('canceled emits canceled and finishes the purchase', () async {
      await deliver(_purchase(PurchaseStatus.canceled));
      expect(events.single.status, PlayBillingStatus.canceled);
      expect(repo.verifyCalls, isEmpty);
      expect(iap.completed, hasLength(1));
    });

    test('error emits the store message and finishes', () async {
      final pd = _purchase(PurchaseStatus.error);
      pd.error = IAPError(
        source: 'google_play',
        code: 'purchase_error',
        message: 'card declined',
      );
      await deliver(pd);
      expect(events.single.status, PlayBillingStatus.error);
      expect(events.single.message, 'card declined');
      expect(iap.completed, hasLength(1));
    });
  });

  group('lifecycle', () {
    test('start is idempotent — one stream subscription', () {
      service.start();
      service.start();
      expect(iap.listenCount, 1);
    });

    test('dispose closes the event stream safely', () async {
      await service.dispose();
      // A second dispose must not throw on the already-closed controller.
      await service.dispose();
    });
  });
}

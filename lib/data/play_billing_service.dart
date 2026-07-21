/// Google Play Billing integration (B16).
///
/// Telegram is banned in-region, so the bot paywall reaches no one.
/// Subscriptions are purchased through Google Play Billing; the resulting
/// `purchaseToken` is verified **server-side** by the engine
/// (`POST /api/billing/play/verify`) which is the entitlement source of
/// truth.  This service is the thin client glue:
///
///   1. query the subscription products configured in Play Console,
///   2. start a purchase,
///   3. on a purchased/restored event, hand the token to the engine,
///   4. on a verified-paid result, refresh the locally-cached tier and
///      `completePurchase` so Play stops re-delivering.
///
/// The engine's RTDN handler keeps the entitlement live afterwards
/// (renewals / cancellations / expiries) — this client only handles the
/// foreground purchase moment.
import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'auth_service.dart';
import 'repository.dart';

/// The Play offer id a [ProductDetails] entry represents, or null for a
/// plain base-plan entry.  On Android the billing plugin returns ONE
/// [ProductDetails] per subscription offer (base plan included); the
/// referral 50%-off first cycle lives under a dedicated offer id
/// (`referral50`, engine `REFERRAL_DISCOUNT_OFFER_ID`) created in Play
/// Console with developer-determined eligibility.
String? googlePlayOfferIdOf(ProductDetails product) {
  if (product is GooglePlayProductDetails) {
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index != null && offers != null && index < offers.length) {
      return offers[index].offerId;
    }
  }
  return null;
}

/// Pick which [ProductDetails] entry the paywall should sell for
/// [productId].
///
/// Eligible referee + the referral offer exists → the discounted offer
/// entry (Play enforces nothing here — the ENGINE decides eligibility;
/// this developer-determined offer must only ever be surfaced when
/// `ReferralStats.discountEligible`).  Everyone else gets the base-plan
/// entry, so pre-referral behaviour is unchanged.  Falls back to the
/// base plan when the offer isn't configured in Play Console yet.
/// [offerIdOf] is injectable so tests don't need Android plugin types.
ProductDetails? pickPlanOffer({
  required List<ProductDetails> products,
  required String productId,
  required bool discountEligible,
  String? discountOfferId,
  String? Function(ProductDetails) offerIdOf = googlePlayOfferIdOf,
}) {
  final candidates = products.where((p) => p.id == productId).toList();
  if (candidates.isEmpty) return null;
  ProductDetails? base;
  ProductDetails? discounted;
  for (final p in candidates) {
    final offerId = offerIdOf(p);
    if (offerId == null) {
      base ??= p;
    } else if (discountOfferId != null && offerId == discountOfferId) {
      discounted ??= p;
    }
  }
  if (discountEligible && discounted != null) return discounted;
  return base ?? candidates.first;
}

/// What happened with a purchase, surfaced to the subscription page.
enum PlayBillingStatus { pending, entitled, notEntitled, canceled, error }

class PlayBillingEvent {
  const PlayBillingEvent(this.status, {this.message, this.result});
  final PlayBillingStatus status;
  final String? message;
  final PlayVerifyResult? result;
}

class PlayBillingService {
  PlayBillingService({
    required this.repo,
    required this.auth,
    InAppPurchase? iap,
  }) : _iap = iap ?? InAppPurchase.instance;

  final LuminRepository repo;
  final AuthService auth;
  final InAppPurchase _iap;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final StreamController<PlayBillingEvent> _events =
      StreamController<PlayBillingEvent>.broadcast();

  /// Purchase lifecycle events for the UI to react to.
  Stream<PlayBillingEvent> get events => _events.stream;

  /// True when the device can transact (Play Store present + signed in).
  Future<bool> isAvailable() => _iap.isAvailable();

  /// Begin listening to the purchase stream.  Idempotent.
  void start() {
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) =>
          _emit(PlayBillingStatus.error, message: e.toString()),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    if (!_events.isClosed) await _events.close();
  }

  /// Fetch the Play product details for [ids].  Unknown ids are dropped
  /// (Play returns them in `notFoundIDs`); the caller renders whatever
  /// came back.
  Future<List<ProductDetails>> loadProducts(Set<String> ids) async {
    final resp = await _iap.queryProductDetails(ids);
    return resp.productDetails;
  }

  /// Launch the Play purchase sheet for [product].  Subscriptions are
  /// non-consumable from the store's perspective; entitlement lifetime is
  /// governed by the subscription, not by consumption.
  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Restore prior purchases (Play → purchaseStream → verify).  Used by
  /// the "Restore purchases" affordance Google requires.
  Future<void> restore() => _iap.restorePurchases();

  // ---- internals -------------------------------------------------------

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final pd in purchases) {
      switch (pd.status) {
        case PurchaseStatus.pending:
          _emit(PlayBillingStatus.pending);
          break;
        case PurchaseStatus.canceled:
          _emit(PlayBillingStatus.canceled);
          await _finish(pd);
          break;
        case PurchaseStatus.error:
          _emit(
            PlayBillingStatus.error,
            message: pd.error?.message ?? 'Purchase failed',
          );
          await _finish(pd);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(pd);
          break;
      }
    }
  }

  Future<void> _verify(PurchaseDetails pd) async {
    try {
      // On Android, serverVerificationData is the Play purchaseToken the
      // engine looks up against the Developer API.
      final token = pd.verificationData.serverVerificationData;
      final result = await repo.verifyPlayPurchase(
        productId: pd.productID,
        purchaseToken: token,
      );
      if (result.isPaid) {
        auth.applyEntitlement(tier: result.tier, paidUntil: result.paidUntil);
        _emit(PlayBillingStatus.entitled, result: result);
      } else {
        _emit(
          PlayBillingStatus.notEntitled,
          message: result.subscriptionState,
          result: result,
        );
      }
    } catch (e) {
      _emit(PlayBillingStatus.error, message: 'Verification failed: $e');
    } finally {
      // Always finish so Play stops re-delivering this purchase.  Even if
      // verification hit a transient error, the engine's RTDN will
      // reconcile entitlement, and the user can "Restore purchases".
      await _finish(pd);
    }
  }

  Future<void> _finish(PurchaseDetails pd) async {
    if (pd.pendingCompletePurchase) {
      await _iap.completePurchase(pd);
    }
  }

  void _emit(PlayBillingStatus status, {String? message, PlayVerifyResult? result}) {
    if (!_events.isClosed) {
      _events.add(PlayBillingEvent(status, message: message, result: result));
    }
  }
}

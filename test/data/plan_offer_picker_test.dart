/// pickPlanOffer (referral Phase 2, 2026-07-21) — which Play offer entry
/// the paywall sells.  Pure logic with an injectable offer-id extractor,
/// so no Android billing plugin types are needed here.
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:lumin/data/play_billing_service.dart';

ProductDetails _pd(String id, String marker, {double price = 0}) =>
    ProductDetails(
      id: id,
      title: id,
      // The marker rides in the description so the fake extractor can
      // identify which offer this entry represents.
      description: marker,
      price: '₹$price',
      rawPrice: price,
      currencyCode: 'INR',
    );

String? _offerIdOf(ProductDetails p) =>
    p.description == 'base' ? null : p.description;

void main() {
  final products = <ProductDetails>[
    _pd('lumin_auto_monthly', 'base', price: 2000),
    _pd('lumin_auto_monthly', 'referral50', price: 1000),
    _pd('lumin_assist_monthly', 'base', price: 1000),
    _pd('lumin_assist_monthly', 'some_other_offer', price: 1),
  ];

  test('ineligible user always gets the base plan', () {
    final pick = pickPlanOffer(
      products: products,
      productId: 'lumin_auto_monthly',
      discountEligible: false,
      discountOfferId: 'referral50',
      offerIdOf: _offerIdOf,
    );
    expect(pick!.description, 'base');
    expect(pick.rawPrice, 2000);
  });

  test('eligible referee gets the referral offer entry', () {
    final pick = pickPlanOffer(
      products: products,
      productId: 'lumin_auto_monthly',
      discountEligible: true,
      discountOfferId: 'referral50',
      offerIdOf: _offerIdOf,
    );
    expect(pick!.description, 'referral50');
    expect(pick.rawPrice, 1000);
  });

  test('eligible but offer missing in Play Console → base plan fallback', () {
    final pick = pickPlanOffer(
      products: products,
      productId: 'lumin_assist_monthly',
      discountEligible: true,
      discountOfferId: 'referral50',
      offerIdOf: _offerIdOf,
    );
    expect(pick!.description, 'base');
  });

  test('a non-referral offer entry is never sold, eligible or not', () {
    for (final eligible in [true, false]) {
      final pick = pickPlanOffer(
        products: products,
        productId: 'lumin_assist_monthly',
        discountEligible: eligible,
        discountOfferId: 'referral50',
        offerIdOf: _offerIdOf,
      );
      expect(pick!.description, 'base');
    }
  });

  test('unknown product returns null', () {
    expect(
      pickPlanOffer(
        products: products,
        productId: 'ghost',
        discountEligible: true,
        discountOfferId: 'referral50',
        offerIdOf: _offerIdOf,
      ),
      isNull,
    );
  });

  test('no base entry (offers only) still sells something', () {
    final offersOnly = [_pd('lumin_auto_monthly', 'referral50', price: 1000)];
    final pick = pickPlanOffer(
      products: offersOnly,
      productId: 'lumin_auto_monthly',
      discountEligible: false,
      discountOfferId: 'referral50',
      offerIdOf: _offerIdOf,
    );
    expect(pick, isNotNull);
  });
}

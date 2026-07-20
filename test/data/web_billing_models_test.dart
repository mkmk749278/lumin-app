/// Serialization tests for the web-billing models (Phase 3).
///
/// The engine is the source of truth for rails + prices; these pin that the
/// client parses its shapes and defaults tolerantly (a pre-upgrade / partial
/// payload must not null-crash — repo convention).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

void main() {
  group('WebBillingConfig.fromJson', () {
    test('parses rails, tiers and prices', () {
      final c = WebBillingConfig.fromJson({
        'enabled': true,
        'test_mode': false,
        'country_code': 'IN',
        'rails': [
          {
            'id': 'crypto',
            'provider': 'nowpayments',
            'currency': 'USD',
            'period_days': 30,
            'tiers': {
              'assist': {'amount': 15, 'display': r'$15/mo'},
              'auto': {'amount': 25, 'display': r'$25/mo'},
            },
          },
          {'id': 'manual', 'note': 'contact the owner'},
        ],
      });
      expect(c.enabled, true);
      expect(c.testMode, false);
      expect(c.countryCode, 'IN');
      expect(c.hasCrypto, true);
      expect(c.crypto!.provider, 'nowpayments');
      expect(c.crypto!.periodDays, 30);
      expect(c.crypto!.tiers['assist']!.amount, 15);
      expect(c.crypto!.tiers['auto']!.display, r'$25/mo');
      expect(c.railById('manual')!.note, 'contact the owner');
    });

    test('defaults tolerantly on an empty / partial payload', () {
      final c = WebBillingConfig.fromJson({});
      expect(c.enabled, false);
      expect(c.testMode, false);
      expect(c.countryCode, 'unknown');
      expect(c.rails, isEmpty);
      expect(c.hasCrypto, false);
      expect(c.crypto, isNull);
    });

    test('manual-only payload exposes no crypto rail', () {
      final c = WebBillingConfig.fromJson({
        'enabled': false,
        'rails': [
          {'id': 'manual', 'note': 'contact'}
        ],
      });
      expect(c.hasCrypto, false);
      expect(c.railById('manual'), isNotNull);
    });
  });

  group('WebCheckout.fromJson', () {
    test('parses the checkout handoff', () {
      final w = WebCheckout.fromJson({
        'ok': true,
        'tier': 'auto',
        'amount_usd': 25,
        'invoice_url': 'https://nowpayments.example/pay/x',
        'invoice_id': 'inv_1',
        'order_id': 'luminweb:7:auto:abc',
      });
      expect(w.ok, true);
      expect(w.tier, 'auto');
      expect(w.amountUsd, 25);
      expect(w.invoiceUrl, 'https://nowpayments.example/pay/x');
      expect(w.orderId, 'luminweb:7:auto:abc');
    });

    test('defaults on missing fields', () {
      final w = WebCheckout.fromJson({});
      expect(w.ok, false);
      expect(w.invoiceUrl, '');
      expect(w.amountUsd, 0);
    });
  });
}

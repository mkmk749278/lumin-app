/// Referral Phase 2 model serialization (2026-07-21).
///
/// The repo convention under test: every Phase-2 field defaults so a
/// pre-upgrade engine (Phase-1 payload) parses cleanly — fields default
/// rather than null-crash on older backends.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

void main() {
  group('ReferralStats.fromJson', () {
    test('parses a full Phase-2 payload', () {
      final stats = ReferralStats.fromJson({
        'code': '267NP54',
        'referred_count': 4,
        'rewards_enabled': true,
        'reward_days_per_invite': 7,
        'reward_tier': 'auto',
        'reward_days_earned': 28,
        'reward_active_tier': 'auto',
        'reward_active_until': '2026-08-04T00:00:00+00:00',
        'paid_referred_count': 2,
        'commission_rate': 0.5,
        'commission_max_periods': 3,
        'commission_totals': [
          {'currency': 'INR', 'accrued': 1500.0, 'paid': 500.0},
          {'currency': 'USD', 'accrued': 12.5, 'paid': 0.0},
        ],
        'discount_eligible': true,
        'discount_offer_id': 'referral50',
        'discount_percent': 50,
      });
      expect(stats.code, '267NP54');
      expect(stats.referredCount, 4);
      expect(stats.rewardsEnabled, isTrue);
      expect(stats.rewardDaysPerInvite, 7);
      expect(stats.rewardTier, 'auto');
      expect(stats.rewardDaysEarned, 28);
      expect(stats.rewardActiveTier, 'auto');
      expect(stats.rewardActiveUntil, '2026-08-04T00:00:00+00:00');
      expect(stats.paidReferredCount, 2);
      expect(stats.commissionRate, 0.5);
      expect(stats.commissionMaxPeriods, 3);
      expect(stats.commissionTotals, hasLength(2));
      expect(stats.commissionTotals.first.currency, 'INR');
      expect(stats.commissionTotals.first.accrued, 1500.0);
      expect(stats.commissionTotals.last.paid, 0.0);
      expect(stats.discountEligible, isTrue);
      expect(stats.discountOfferId, 'referral50');
      expect(stats.discountPercent, 50);
    });

    test('tolerates a Phase-1 (pre-rewards) engine payload', () {
      final stats = ReferralStats.fromJson({
        'code': 'ABC1234',
        'referred_count': 1,
      });
      expect(stats.code, 'ABC1234');
      expect(stats.referredCount, 1);
      expect(stats.rewardsEnabled, isFalse);
      expect(stats.rewardDaysEarned, 0);
      expect(stats.rewardActiveUntil, isNull);
      expect(stats.commissionTotals, isEmpty);
      expect(stats.discountEligible, isFalse);
      expect(stats.discountPercent, 0);
    });
  });

  group('ReferralClaimResult.fromJson', () {
    test('parses discount_eligible and defaults it off', () {
      final ok = ReferralClaimResult.fromJson(
          {'ok': true, 'reason': null, 'discount_eligible': true});
      expect(ok.ok, isTrue);
      expect(ok.discountEligible, isTrue);

      final old = ReferralClaimResult.fromJson({'ok': true});
      expect(old.ok, isTrue);
      expect(old.discountEligible, isFalse);
    });
  });

  group('WebCheckout.fromJson referral fields', () {
    test('parses discounted invoice and defaults on old engines', () {
      final discounted = WebCheckout.fromJson({
        'ok': true,
        'tier': 'auto',
        'amount_usd': 12.5,
        'invoice_url': 'https://x/pay',
        'invoice_id': 'i1',
        'order_id': 'o1',
        'discounted': true,
        'discount_percent': 50,
      });
      expect(discounted.discounted, isTrue);
      expect(discounted.discountPercent, 50);
      expect(discounted.amountUsd, 12.5);

      final old = WebCheckout.fromJson({
        'ok': true,
        'tier': 'auto',
        'amount_usd': 25.0,
        'invoice_url': 'https://x/pay',
        'invoice_id': 'i1',
        'order_id': 'o1',
      });
      expect(old.discounted, isFalse);
      expect(old.discountPercent, 0);
    });
  });
}

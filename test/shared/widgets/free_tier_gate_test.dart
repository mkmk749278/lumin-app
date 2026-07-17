/// Tier helpers behind the subscription-status surfaces (2026-07-17).
///
/// `tierDisplayName` / `isPaidTier` / `playManageSubscriptionUrl` drive
/// the CurrentPlanCard, the Profile subscription card, and the Menu
/// subtitle — pin their vocabulary so an engine tier value never leaks
/// raw and the Play deep links can't drift from the Console SKUs.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/widgets/free_tier_gate.dart';

void main() {
  group('tierRank', () {
    test('ranks the B16 ladder', () {
      expect(tierRank(null), 0);
      expect(tierRank('free'), 0);
      expect(tierRank('garbage'), 0);
      expect(tierRank('assist'), 1);
      expect(tierRank('auto'), 2);
      expect(tierRank('paid'), 2);
      expect(tierRank('all-access'), 3);
      expect(tierRank('owner'), 3);
      expect(tierRank('AUTO'), 2, reason: 'case-insensitive');
    });
  });

  group('isPaidTier', () {
    test('any paying tier counts', () {
      expect(isPaidTier('assist'), isTrue);
      expect(isPaidTier('auto'), isTrue);
      expect(isPaidTier('paid'), isTrue);
      expect(isPaidTier('all-access'), isTrue);
      expect(isPaidTier('owner'), isTrue);
    });
    test('free / null / unknown do not', () {
      expect(isPaidTier(null), isFalse);
      expect(isPaidTier(''), isFalse);
      expect(isPaidTier('free'), isFalse);
      expect(isPaidTier('mystery'), isFalse);
    });
  });

  group('tierDisplayName', () {
    test('consumer names, never engine vocabulary', () {
      expect(tierDisplayName('auto'), 'Auto');
      expect(tierDisplayName('assist'), 'Assist');
      expect(tierDisplayName('paid'), 'Auto');
      expect(tierDisplayName('all-access'), 'All Access');
      expect(tierDisplayName('owner'), 'All Access');
      expect(tierDisplayName('free'), 'Free');
      expect(tierDisplayName(null), 'Free');
      expect(tierDisplayName(''), 'Free');
    });
    test('unknown future tier renders capitalised, not raw', () {
      expect(tierDisplayName('platinum'), 'Platinum');
    });
  });

  group('playManageSubscriptionUrl', () {
    test('deep-links the owned SKU', () {
      expect(
        playManageSubscriptionUrl('auto'),
        'https://play.google.com/store/account/subscriptions'
        '?sku=lumin_auto_monthly&package=org.luminapp.lumin',
      );
      expect(
        playManageSubscriptionUrl('assist'),
        'https://play.google.com/store/account/subscriptions'
        '?sku=lumin_assist_monthly&package=org.luminapp.lumin',
      );
    });
    test('legacy / unknown tiers land on the subscriptions list', () {
      expect(
        playManageSubscriptionUrl('paid'),
        'https://play.google.com/store/account/subscriptions',
      );
      expect(
        playManageSubscriptionUrl(null),
        'https://play.google.com/store/account/subscriptions',
      );
    });
  });
}

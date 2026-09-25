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
      // 2026-09-25: the Signals plan (live signals only) sits below Assist,
      // mirroring the engine's _TIER_RANK.
      expect(tierRank('signals'), 1);
      expect(tierRank('assist'), 2);
      expect(tierRank('auto'), 3);
      expect(tierRank('paid'), 3);
      expect(tierRank('all-access'), 4);
      expect(tierRank('owner'), 4);
      expect(tierRank('AUTO'), 3, reason: 'case-insensitive');
      expect(canAssist('signals'), isFalse,
          reason: 'the Signals plan is live signals, not trading');
      expect(tierIncludesLiveSignals('signals'), isTrue);
      expect(tierIncludesLiveSignals('free'), isFalse);
    });
  });

  group('isPaidTier', () {
    test('any paying tier counts', () {
      expect(isPaidTier('signals'), isTrue);
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
      expect(tierDisplayName('signals'), 'Signals');
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

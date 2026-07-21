/// Growth banners (2026-07-21) — surface the subscription value prop and the
/// referral reward deal on the feed tabs so free users see them without digging
/// into Settings.  We test the *pure* cards (tier / stats in, copy + callbacks
/// out), mirroring the CurrentPlanCard approach — the scope/Future wrappers have
/// no test-injection seam (same call RegionGate made).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/shared/widgets/upsell_banners.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('UpgradeBannerCard', () {
    testWidgets('free tier pitches the whole ladder', (tester) async {
      await tester.pumpWidget(_wrap(
        UpgradeBannerCard(tier: null, onSeePlans: () {}),
      ));
      expect(find.text('Automate your signals'), findsOneWidget);
      expect(find.text('See plans'), findsOneWidget);
    });

    testWidgets('assist tier is nudged the one rung to Auto', (tester) async {
      await tester.pumpWidget(_wrap(
        UpgradeBannerCard(tier: 'assist', onSeePlans: () {}),
      ));
      expect(find.text('Go fully hands-off'), findsOneWidget);
      expect(find.text('Upgrade to Auto'), findsOneWidget);
    });

    testWidgets('Auto tier renders nothing — no upsell left to make',
        (tester) async {
      await tester.pumpWidget(_wrap(
        UpgradeBannerCard(tier: 'auto', onSeePlans: () {}),
      ));
      expect(find.text('Automate your signals'), findsNothing);
      expect(find.text('Go fully hands-off'), findsNothing);
    });

    testWidgets('owner / all-access is treated as fully unlocked',
        (tester) async {
      await tester.pumpWidget(_wrap(
        UpgradeBannerCard(tier: 'owner', onSeePlans: () {}),
      ));
      expect(find.byIcon(Icons.workspace_premium_rounded), findsNothing);
    });

    testWidgets('tapping the card fires the CTA', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        UpgradeBannerCard(tier: null, onSeePlans: () => tapped = true),
      ));
      await tester.tap(find.text('See plans'));
      expect(tapped, isTrue);
    });

    testWidgets('dismiss control appears only when a handler is given',
        (tester) async {
      await tester.pumpWidget(_wrap(
        UpgradeBannerCard(tier: null, onSeePlans: () {}),
      ));
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      var dismissed = false;
      await tester.pumpWidget(_wrap(
        UpgradeBannerCard(
          tier: null,
          onSeePlans: () {},
          onDismiss: () => dismissed = true,
        ),
      ));
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(dismissed, isTrue);
    });
  });

  group('InviteBannerCard', () {
    const rewarded = ReferralStats(
      code: 'ABC123',
      referredCount: 2,
      rewardsEnabled: true,
      rewardDaysPerInvite: 7,
      rewardTier: 'auto',
      commissionRate: 0.5,
      commissionMaxPeriods: 3,
      discountPercent: 50,
    );

    testWidgets('renders the engine reward deal when rewards are on',
        (tester) async {
      await tester.pumpWidget(_wrap(
        InviteBannerCard(stats: rewarded, onInvite: () {}),
      ));
      expect(find.text('Invite friends, earn free Auto'), findsOneWidget);
      expect(find.textContaining('7 free Auto days'), findsOneWidget);
      expect(find.textContaining('50% commission'), findsOneWidget);
      expect(find.textContaining('50% off'), findsOneWidget);
      expect(find.text('Invite & earn'), findsOneWidget);
    });

    testWidgets('degrades to a plain invite when the programme is off',
        (tester) async {
      await tester.pumpWidget(_wrap(
        InviteBannerCard(
          stats: const ReferralStats(code: 'ABC123', referredCount: 0),
          onInvite: () {},
        ),
      ));
      expect(find.text('Invite a friend'), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);
      // Must never promise a reward the switched-off engine won't grant.
      expect(find.textContaining('commission'), findsNothing);
      expect(find.textContaining('free Auto'), findsNothing);
    });

    testWidgets('tapping the card opens the invite flow', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        InviteBannerCard(stats: rewarded, onInvite: () => tapped = true),
      ));
      await tester.tap(find.text('Invite & earn'));
      expect(tapped, isTrue);
    });
  });
}

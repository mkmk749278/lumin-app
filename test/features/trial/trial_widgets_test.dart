/// Free-trial UI — the welcome offer and the countdown (2026-07-25).
///
/// The properties worth pinning are the truthfulness ones, because the failure
/// mode here is a sheet promising something the engine will refuse:
///
/// * copy is driven by engine numbers (days / tier), never by constants;
/// * the offer tile and the countdown are mutually exclusive and each renders
///   nothing when its precondition is absent;
/// * showing the offer grants nothing — only the CTA callback fires;
/// * every engine refusal reason maps to a human sentence, never a raw enum.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/features/trial/trial_gate.dart';
import 'package:lumin/features/trial/trial_offer_tile.dart';
import 'package:lumin/features/trial/trial_welcome_sheet.dart';

// No outer scroll view: TrialWelcomeCard brings its own, and nesting two
// would hand the inner one unbounded constraints.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The welcome card is taller than the default 800×600 test surface, so its
/// buttons scroll off. Scroll to a control before tapping it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

const _offered = TrialState(offerAvailable: true, days: 7, tier: 'auto');

const _running = TrialState(
  days: 7,
  tier: 'auto',
  claimed: true,
  active: true,
  daysRemaining: 5,
  expiresAt: '2026-08-01T00:00:00Z',
);

void main() {
  group('TrialWelcomeCard', () {
    testWidgets('renders the offer using engine numbers, not constants',
        (tester) async {
      await tester.pumpWidget(_wrap(TrialWelcomeCard(
        trial: const TrialState(offerAvailable: true, days: 14, tier: 'assist'),
        onStart: () {},
        onLater: () {},
      )));

      expect(find.text('14 days of Assist, free'), findsOneWidget);
      expect(find.text('Start my 14 free days'), findsOneWidget);
    });

    testWidgets('states plainly that no card is taken', (tester) async {
      await tester.pumpWidget(_wrap(TrialWelcomeCard(
        trial: _offered,
        onStart: () {},
        onLater: () {},
      )));

      expect(find.text('No card. No auto-charge.'), findsOneWidget);
      expect(find.textContaining('nothing is billed'), findsOneWidget);
    });

    testWidgets('carries the risk disclosure — a trial is still real money',
        (tester) async {
      await tester.pumpWidget(_wrap(TrialWelcomeCard(
        trial: _offered,
        onStart: () {},
        onLater: () {},
      )));

      expect(find.textContaining('substantial risk of loss'), findsOneWidget);
      expect(find.textContaining('investment advice'), findsOneWidget);
      expect(
        find.textContaining('nothing trades until you connect'),
        findsOneWidget,
        reason: 'a trialist must not think the engine is already trading',
      );
    });

    testWidgets('CTA fires the callback and nothing else', (tester) async {
      var started = 0;
      var later = 0;
      await tester.pumpWidget(_wrap(TrialWelcomeCard(
        trial: _offered,
        onStart: () => started++,
        onLater: () => later++,
      )));

      await _tap(tester, find.text('Start my 7 free days'));
      expect(started, 1);
      expect(later, 0);

      await _tap(tester, find.text('Maybe later'));
      expect(later, 1);
      expect(started, 1);
    });

    testWidgets('busy disables both actions so a double-tap cannot double-claim',
        (tester) async {
      var started = 0;
      await tester.pumpWidget(_wrap(TrialWelcomeCard(
        trial: _offered,
        busy: true,
        onStart: () => started++,
        onLater: () {},
      )));

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await _tap(tester, find.byType(FilledButton));
      expect(started, 0);
    });

    testWidgets('surfaces a refusal message when the engine says no',
        (tester) async {
      await tester.pumpWidget(_wrap(TrialWelcomeCard(
        trial: _offered,
        error: 'You have already used your free trial.',
        onStart: () {},
        onLater: () {},
      )));

      expect(
        find.text('You have already used your free trial.'),
        findsOneWidget,
      );
    });
  });

  group('trialRefusalMessage', () {
    test('maps every engine reason to a human sentence', () {
      for (final reason in [
        'already_trialled',
        'already_subscribed',
        'account_too_old',
        'not_onboarded',
        'offer_not_available',
      ]) {
        final message = trialRefusalMessage(reason);
        expect(message, isNotEmpty);
        expect(
          message.contains('_'),
          isFalse,
          reason: 'a raw enum must never reach the user ($reason)',
        );
      }
    });

    test('an unknown reason stays vague rather than guessing', () {
      expect(
        trialRefusalMessage('some_future_reason'),
        "Couldn't start your trial. Please try again.",
      );
    });
  });

  group('trialTierLabel', () {
    test('names the known tiers and never renders an empty label', () {
      expect(trialTierLabel('auto'), 'Auto');
      expect(trialTierLabel('assist'), 'Assist');
      expect(trialTierLabel(null), 'full access');
      expect(trialTierLabel(''), 'full access');
      expect(trialTierLabel('platinum'), 'platinum');
    });
  });

  group('TrialCountdownCard', () {
    testWidgets('counts down a running trial', (tester) async {
      await tester.pumpWidget(_wrap(TrialCountdownCard(
        trial: _running,
        onSeePlans: () {},
      )));

      expect(find.textContaining('5 days left'), findsOneWidget);
      expect(find.text('See plans'), findsOneWidget);
    });

    testWidgets('singularises the last day', (tester) async {
      await tester.pumpWidget(_wrap(TrialCountdownCard(
        trial: const TrialState(
          days: 7, tier: 'auto', claimed: true, active: true, daysRemaining: 1,
        ),
        onSeePlans: () {},
      )));

      expect(find.textContaining('1 day left'), findsOneWidget);
      expect(find.textContaining('1 days left'), findsNothing);
    });

    testWidgets('turns into an upsell in the final days', (tester) async {
      await tester.pumpWidget(_wrap(TrialCountdownCard(
        trial: const TrialState(
          days: 7, tier: 'auto', claimed: true, active: true, daysRemaining: 2,
        ),
        onSeePlans: () {},
      )));

      expect(find.textContaining('ends soon'), findsOneWidget);
      expect(find.text('Keep Auto'), findsOneWidget);
    });

    testWidgets('renders nothing for a lapsed or unclaimed trial',
        (tester) async {
      await tester.pumpWidget(_wrap(TrialCountdownCard(
        trial: const TrialState(claimed: true, days: 7, tier: 'auto'),
        onSeePlans: () {},
      )));
      expect(find.byType(InkWell), findsNothing);

      await tester.pumpWidget(_wrap(TrialCountdownCard(
        trial: TrialState.empty,
        onSeePlans: () {},
      )));
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('TrialOfferTile', () {
    testWidgets('offers the trial with engine terms', (tester) async {
      await tester.pumpWidget(_wrap(TrialOfferTile(
        trial: _offered,
        onStart: () {},
      )));

      expect(find.text('Try Auto free for 7 days'), findsOneWidget);
      expect(find.text('Start free trial'), findsOneWidget);
    });

    testWidgets('renders nothing when no offer is available', (tester) async {
      await tester.pumpWidget(_wrap(TrialOfferTile(
        trial: _running,
        onStart: () {},
      )));
      expect(find.textContaining('Try Auto free'), findsNothing);

      await tester.pumpWidget(_wrap(TrialOfferTile(
        trial: TrialState.empty,
        onStart: () {},
      )));
      expect(find.textContaining('free for'), findsNothing);
    });
  });
}

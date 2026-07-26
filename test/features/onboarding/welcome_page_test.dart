/// Tests for the welcome carousel's advance behaviour.
///
/// These pin the 2026-07-26 iPhone setup-screen fix: the owner reported
/// having to press the slide CTA "a couple of times" in the web (PWA)
/// channel.  One contributing cause was `_page` only updating from
/// `PageView.onPageChanged`, which fires part-way through the 300ms scroll
/// animation — a tap inside that window read a stale index and re-targeted
/// the slide already being animated to, so it did nothing visible.  The
/// carousel now tracks the *intended* slide, so a tap is acted on the
/// moment it lands.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/onboarding/pages/welcome_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpWelcome(
    WidgetTester tester, {
    VoidCallback? onContinue,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: WelcomePage(onContinue: onContinue ?? () {})),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one tap per slide walks the carousel to the final CTA',
      (tester) async {
    var continues = 0;
    await pumpWelcome(tester, onContinue: () => continues++);

    expect(find.text('See how it works'), findsOneWidget);

    await tester.tap(find.text('See how it works'));
    await tester.pumpAndSettle();
    expect(find.text('Your funds stay safe'), findsOneWidget);

    await tester.tap(find.text('Your funds stay safe'));
    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsOneWidget);

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(continues, 1);
  });

  testWidgets('the target slide is adopted on the frame the tap lands',
      (tester) async {
    await pumpWelcome(tester);

    // Skip is rendered only while there are slides left to skip, so its
    // disappearance is a stationary read-out of the tracked slide index.
    // Pre-fix the index came from `onPageChanged`, which does not fire
    // until the 300ms animation is well under way — so one frame after the
    // tap the carousel still believed it was on slide 1 and any further
    // tap was resolved against that stale index.
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(find.text('Skip'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('double-tapping Get Started only continues once', (tester) async {
    var continues = 0;
    await pumpWelcome(tester, onContinue: () => continues++);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Started'));
    await tester.tap(find.text('Get Started'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(continues, 1);
  });

  testWidgets('finishing the carousel records the welcome-seen flag',
      (tester) async {
    await pumpWelcome(tester);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding.welcomeSeen'), isTrue);
  });
}

/// The ONE welcome screen (owner, 2026-09-25): *"just one welcome screen
/// and enter into app, no more scary warnings"*.
///
/// Pins: a single "Get Started" continues exactly once; tapping it records
/// both the welcome and the terms acceptance (the one line under the button
/// IS the acceptance, so the first-run gate must not show the old consent
/// page afterwards); the terms line is on screen; the screen fits small
/// phones with the button reachable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/consent_storage.dart';
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

  testWidgets('one tap on Get Started enters the app', (tester) async {
    var continues = 0;
    await pumpWelcome(tester, onContinue: () => continues++);

    expect(find.text('Skip'), findsNothing, reason: 'no carousel any more');
    await tester.ensureVisible(find.text('Get Started'));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(continues, 1);
  });

  testWidgets('double-tapping Get Started only continues once', (tester) async {
    var continues = 0;
    await pumpWelcome(tester, onContinue: () => continues++);

    await tester.ensureVisible(find.text('Get Started'));
    await tester.tap(find.text('Get Started'));
    await tester.tap(find.text('Get Started'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(continues, 1);
  });

  testWidgets('Get Started records the welcome AND the terms acceptance',
      (tester) async {
    await pumpWelcome(tester);
    expect(await ConsentStorage.isUpToDate(), isFalse);

    await tester.ensureVisible(find.text('Get Started'));
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(await ConsentStorage.welcomeSeen(), isTrue);
    expect(await ConsentStorage.isUpToDate(), isTrue,
        reason: 'the one line under the button is the acceptance — the '
            'gate must not show the old 3-checkbox page after this');
  });

  testWidgets('the 18+ / Terms & Risk line is on the screen', (tester) async {
    await pumpWelcome(tester);
    expect(find.textContaining('18+', findRichText: true), findsOneWidget);
    expect(find.textContaining('Terms', findRichText: true), findsOneWidget);
    expect(find.textContaining('Risk', findRichText: true), findsOneWidget);
  });

  for (final size in const [Size(360, 640), Size(320, 568)]) {
    testWidgets('fits a ${size.width.toInt()}x${size.height.toInt()} screen',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpWelcome(tester);
      expect(tester.takeException(), isNull, reason: 'welcome overflowed');
      await tester.ensureVisible(find.text('Get Started'));
      await tester.pumpAndSettle();
      expect(find.text('Get Started').hitTestable(), findsOneWidget);
    });
  }
}

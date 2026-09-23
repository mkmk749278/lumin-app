/// Upsell banner fit and dismissal (2026-09-23 audit).
///
/// Two defects, both seen on a small phone: the full card pinned above the
/// Signals list took about half the viewport at 1.3x text, and a close was
/// per tab and per session, so the same pitch came back on four tabs and on
/// every launch. These pin the compact layout's height and the shared,
/// persisted, snoozing dismissal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/widgets/upsell_banners.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(resetUpsellDismissalsForTest);

  Future<Size> sizeAt(WidgetTester tester, {required bool compact}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Scaffold(
          body: Column(children: [
            UpgradeBannerCard(
              tier: null,
              compact: compact,
              onSeePlans: () {},
              onDismiss: () {},
            ),
          ]),
        ),
      ),
    ));
    return tester.getSize(find.byType(UpgradeBannerCard));
  }

  testWidgets('the compact strip is one line and far shorter at 1.3x text',
      (tester) async {
    final full = await sizeAt(tester, compact: false);
    final compact = await sizeAt(tester, compact: true);
    expect(tester.takeException(), isNull); // no overflow
    // One line: at most ~a tenth of a 640px screen, and well under the card.
    expect(compact.height, lessThan(64));
    expect(compact.height, lessThan(full.height * 0.6));
    // The subtitle is the full card's; the strip keeps title + CTA only.
    expect(find.textContaining('own exchange keys'), findsNothing);
    expect(find.text('See plans'), findsOneWidget);
  });

  test('one dismissal hides the kind everywhere and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 9, 23, 12);
    await dismissUpsell('upgrade', now: now);
    expect(upsellDismissed.value, contains('upgrade'));
    expect(upsellDismissed.value, isNot(contains('invite')));

    // A fresh launch reads it back.
    resetUpsellDismissalsForTest();
    await hydrateUpsellDismissals(now: now.add(const Duration(days: 1)));
    expect(upsellDismissed.value, contains('upgrade'));
  });

  test('the snooze expires on its own', () async {
    SharedPreferences.setMockInitialValues({});
    final then = DateTime(2026, 9, 1);
    await dismissUpsell('invite', now: then);
    resetUpsellDismissalsForTest();
    await hydrateUpsellDismissals(now: then.add(kUpsellSnooze + const Duration(minutes: 1)));
    expect(upsellDismissed.value, isNot(contains('invite')));
  });

  testWidgets('the dismiss control in the strip fires its handler',
      (tester) async {
    var dismissed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpgradeBannerCard(
          tier: null,
          compact: true,
          onSeePlans: () {},
          onDismiss: () => dismissed = true,
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(dismissed, isTrue);
  });
}

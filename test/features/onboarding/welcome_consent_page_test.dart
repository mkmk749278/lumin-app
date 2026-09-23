import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/onboarding/pages/welcome_consent_page.dart';
import 'package:lumin/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The consent gate is the first control a new user must operate. Until
/// 2026-09-23 its checkboxes drew a 10%-alpha border on navy (close to
/// invisible on the live site) and Continue sat disabled with no reason.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, {VoidCallback? onAccepted}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLuminTheme(),
      home: WelcomeConsentPage(onAccepted: onAccepted ?? () {}),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('says how many boxes are left, and stops once none are',
      (tester) async {
    await pump(tester);
    expect(find.text('Tick all 3 boxes to continue'), findsOneWidget);

    final boxes = find.byType(Checkbox);
    await tester.tap(boxes.at(0));
    await tester.pumpAndSettle();
    expect(find.text('Tick 2 more boxes to continue'), findsOneWidget);

    await tester.tap(boxes.at(1));
    await tester.pumpAndSettle();
    expect(find.text('Tick 1 more box to continue'), findsOneWidget);

    await tester.tap(boxes.at(2));
    await tester.pumpAndSettle();
    expect(find.textContaining('to continue'), findsNothing);
  });

  testWidgets('continues only when all three are ticked', (tester) async {
    var accepted = 0;
    await pump(tester, onAccepted: () => accepted++);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(accepted, 0);

    for (final b in find.byType(Checkbox).evaluate().toList()) {
      await tester.tap(find.byWidget(b.widget));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Continue'));
    // Continue shows a spinner until the parent swaps the route, so the
    // tree never settles here; pump the storage write through instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(accepted, 1);
  });

  testWidgets('checkboxes use the theme border, not a near-invisible one',
      (tester) async {
    await pump(tester);
    for (final c in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(c.side, isNull,
          reason: 'a per-site side override is what made them invisible');
    }
  });
}

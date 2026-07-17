/// CurrentPlanCard — the persistent "you are subscribed" surface added
/// 2026-07-17 after a paying Auto subscriber's screenshots showed the
/// Subscription page pitching them the plans they already own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/settings/pages/subscription_page.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('renders plan name, renewal date and manage action',
      (tester) async {
    var managed = false;
    await tester.pumpWidget(_wrap(CurrentPlanCard(
      tier: 'auto',
      paidUntil: '2026-08-17T00:00:00Z',
      onManage: () => managed = true,
    )));

    expect(find.text('CURRENT PLAN'), findsOneWidget);
    expect(find.text('Auto plan'), findsOneWidget);
    expect(
      find.textContaining('paid until'),
      findsOneWidget,
      reason: 'renewal date must be visible when the engine provides it',
    );
    expect(find.text('Manage in Google Play'), findsOneWidget);

    await tester.tap(find.text('Manage in Google Play'));
    expect(managed, isTrue);
  });

  testWidgets('drops the renewal line when paid_until is missing',
      (tester) async {
    await tester.pumpWidget(_wrap(CurrentPlanCard(
      tier: 'assist',
      paidUntil: null,
      onManage: () {},
    )));

    expect(find.text('Assist plan'), findsOneWidget);
    expect(find.textContaining('paid until'), findsNothing);
    expect(find.textContaining('renews via Google Play'), findsOneWidget);
  });

  testWidgets('legacy paid tier renders as Auto, never raw', (tester) async {
    await tester.pumpWidget(_wrap(CurrentPlanCard(
      tier: 'paid',
      paidUntil: null,
      onManage: () {},
    )));
    expect(find.text('Auto plan'), findsOneWidget);
    expect(find.textContaining('paid plan'), findsNothing);
  });
}

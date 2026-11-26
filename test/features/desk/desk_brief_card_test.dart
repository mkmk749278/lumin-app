import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/desk_models.dart';
import 'package:lumin/features/desk/desk_brief_card.dart';

import '../../data/desk_models_test.dart' show desk;

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000900 * 1000, isUtc: true);

  Future<void> pump(WidgetTester t, Map<String, dynamic> json) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DeskBriefView(response: DeskResponse.fromJson(json), now: now),
            ),
          ),
        ),
      );

  testWidgets('a current brief shows bias, age, notes and BTC', (t) async {
    await pump(t, desk());
    expect(find.byKey(const Key('desk.brief.current')), findsOneWidget);
    expect(find.text('RISK-OFF'), findsOneWidget);
    expect(find.text('Updated 15m ago'), findsOneWidget);
    expect(find.text('BTC printed a fresh 4h low.'), findsOneWidget);
    expect(find.text('\$59,212'), findsOneWidget);
    expect(find.text('46%'), findsOneWidget);
    expect(find.textContaining('XLMUSDT short'), findsOneWidget);
  });

  testWidgets('a stale brief says it is not this hour', (t) async {
    await pump(t, desk(freshness: 'stale'));
    expect(find.byKey(const Key('desk.brief.stale')), findsOneWidget);
    expect(find.byKey(const Key('desk.brief.stale_note')), findsOneWidget);
  });

  testWidgets('a stand-aside plan is a brief, not an empty card', (t) async {
    await pump(t, desk(plan: {
      'plan_id': 'p', 'submitted_at': 1700000000.0, 'bias': 'stand_aside',
      'notes': 'Chop. Nothing clean.', 'n_setups': 0, 'n_accepted': 0, 'accepted': [],
    }));
    expect(find.textContaining('the desk stood aside'), findsOneWidget);
    expect(find.text('Chop. Nothing clean.'), findsOneWidget);
  });

  testWidgets('unreadable BTC context says so', (t) async {
    await pump(t, desk(marketReadable: false));
    expect(find.byKey(const Key('desk.brief.market_unreadable')), findsOneWidget);
  });

  testWidgets('not reported, no plan, and disabled each render their own state',
      (t) async {
    await pump(t, {'state': 'not_reported', 'desk': null});
    expect(find.byKey(const Key('desk.brief.not_reported')), findsOneWidget);

    final none = desk();
    (none['desk'] as Map)['brief'] = {'plan': null, 'freshness': {'state': 'none'}, 'market': {}};
    await pump(t, none);
    expect(find.byKey(const Key('desk.brief.none')), findsOneWidget);

    await pump(t, {'state': 'disabled', 'desk': null});
    expect(find.byKey(const Key('desk.brief.disabled')), findsOneWidget);
    expect(find.text('DESK BRIEF'), findsNothing);
  });
}

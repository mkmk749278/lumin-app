/// The masked live card (owner, 2026-09-25): symbol, analyst and age show;
/// levels and direction do not exist on it to show, and the call to action
/// matches who is looking.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/live_feed_access.dart';
import 'package:lumin/features/signals/live_signals_banner.dart';

void main() {
  const sig = LockedSignal(
    id: 's1',
    symbol: 'BTCUSDT',
    agentName: 'Trend Rider',
    qualityTier: 'A+',
    confidence: 82,
    minutesAgo: 4,
  );

  Future<void> pump(WidgetTester t, {required bool guest}) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LockedSignalCard(signal: sig, guest: guest)),
        ),
      );

  testWidgets('shows the tease, never a direction', (t) async {
    await pump(t, guest: true);
    expect(find.text('BTCUSDT'), findsOneWidget);
    expect(find.textContaining('Trend Rider'), findsOneWidget);
    expect(find.text('4 min ago'), findsOneWidget);
    expect(find.textContaining('LONG'), findsNothing);
    expect(find.textContaining('SHORT'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a guest is asked to sign up', (t) async {
    await pump(t, guest: true);
    expect(find.text('Sign up free to see signal'), findsOneWidget);
  });

  testWidgets('a signed-in user past the free days is offered the plan',
      (t) async {
    await pump(t, guest: false);
    expect(find.text('Unlock with Signals plan'), findsOneWidget);
  });
}

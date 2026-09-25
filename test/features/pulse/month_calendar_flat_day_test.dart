import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/features/pulse/month_calendar.dart';

/// UX review 2026-09-25: a day netting -0.04 rendered "-0.0" in the loss
/// colour, which read as a losing day. A day that rounds to zero is flat.
void main() {
  TrackRecord record(double net) => TrackRecord(
        enabled: true,
        unavailableReason: '',
        days: 30,
        month: '2026-09',
        earliestDate: '2026-07-01',
        amountUsdt: 100,
        feePct: 0.07,
        rangeStart: '2026-09-01',
        summary: const TrackRecordSummary(
          trades: 3, moves: 3, tradesPriced: 3, wins: 1, losses: 2,
          winRate: 0.33, grossUsd: 0, feeUsd: 0, netUsd: 0,
          avgPnlPct: 0, avgNetPct: 0, bestPnlPct: 1, worstPnlPct: -1,
        ),
        items: [
          TrackRecordDay(
            date: '2026-09-24', trades: 3, moves: 3, wins: 1, losses: 2,
            netUsd: net, netPct: net, cumNetUsd: net, partialReason: null,
          ),
        ],
      );

  Future<void> pump(WidgetTester t, double net) => t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MonthCalendar(month: '2026-09', record: record(net), loading: false),
        ),
      ));

  testWidgets('a day that nets to 0.0 reads flat, never a red "-0.0"', (t) async {
    await pump(t, -0.04);
    expect(find.text('-0.0'), findsNothing);
    expect(find.text('0.0'), findsOneWidget);
  });

  testWidgets('a real loss still carries its sign', (t) async {
    await pump(t, -1.8);
    expect(find.text('-1.8'), findsOneWidget);
  });
}

/// `TrackRecordMonthCard` — the calendar month on the main Pulse page.
///
/// Added on the owner's direction (2026-08-11: *"keep that month card in main
/// pulse page"*). It sits **beside** the rolling-window summary card, not
/// inside it, because the two describe different periods — and one control for
/// two periods is the confusion the month mode exists to remove.
///
/// What is pinned here is the seam between the two cards: that this one fetches
/// its own month, that it does not borrow the window's numbers, and that a step
/// in flight never paints one month's figures under another's heading.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/features/pulse/month_calendar.dart';
import 'package:lumin/features/pulse/track_record_month_card.dart';

TrackRecordDay _day(String date, double net, {String? partial}) =>
    TrackRecordDay(
      date: date,
      trades: 3,
      moves: 3,
      wins: net > 0 ? 2 : 1,
      losses: net > 0 ? 1 : 2,
      netUsd: net,
      netPct: net,
      cumNetUsd: net,
      partialReason: partial,
    );

TrackRecord _window({bool hasBook = true}) => TrackRecord(
      enabled: hasBook,
      unavailableReason: hasBook ? '' : 'disabled',
      days: 30,
      earliestDate: '2026-07-01',
      amountUsdt: 100.0,
      feePct: 0.07,
      rangeStart: '2026-07-12',
      summary: TrackRecordSummary(
        trades: hasBook ? 407 : 0,
        moves: 394,
        tradesPriced: hasBook ? 407 : 0,
        wins: 141,
        losses: 266,
        winRate: 0.35,
        grossUsd: 80.34,
        feeUsd: 28.49,
        netUsd: 51.85,
        avgPnlPct: 0.197,
        avgNetPct: 0.127,
        bestPnlPct: 12.71,
        worstPnlPct: -9.60,
      ),
      items: hasBook ? [_day('2026-08-10', 20.0)] : const [],
    );

/// The month payload. Values differ from the window's on purpose: if the card
/// ever rendered the window's book under a month heading, these numbers are
/// what would catch it.
TrackRecord _month(String ym, {double amount = 100.0}) => TrackRecord(
      enabled: true,
      unavailableReason: '',
      days: 31,
      month: ym,
      earliestDate: '2026-07-01',
      amountUsdt: amount,
      feePct: 0.07,
      rangeStart: '$ym-01',
      summary: const TrackRecordSummary(
        trades: 40, moves: 38, tradesPriced: 40, wins: 18, losses: 22,
        winRate: 0.45, grossUsd: 12.0, feeUsd: 2.8, netUsd: 9.2,
        avgPnlPct: 0.3, avgNetPct: 0.23, bestPnlPct: 4.0, worstPnlPct: -3.0,
      ),
      items: [
        _day('$ym-04', 8.0),
        _day('$ym-05', -5.0),
        _day('$ym-10', 20.0),
      ],
    );

class _Repo extends MockRepository {
  _Repo({this.delay = Duration.zero});
  final Duration delay;
  final months = <String>[];
  double? lastAmount;

  @override
  Future<TrackRecord> fetchTrackRecord({
    int days = 30,
    String month = '',
    double? amount,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (month.isNotEmpty) months.add(month);
    lastAmount = amount;
    return _month(month, amount: amount ?? 100.0);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  _Repo? repo,
  TrackRecord? window,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TrackRecordMonthCard(
            window: window ?? _window(),
            repo: repo ?? _Repo(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' • ')
    .toLowerCase();

void main() {
  group('when it shows', () {
    testWidgets('a record with a book renders the month grid', (t) async {
      await _pump(t);
      expect(find.byKey(const ValueKey('month-calendar')), findsOneWidget);
      expect(find.text('SIGNAL BOOK BY DAY'), findsOneWidget);
    });

    testWidgets('no record at all hides it entirely', (t) async {
      // Gated on the WINDOW's book, because a month that happens to be quiet
      // is a real answer worth showing while no record at all is not.
      await _pump(t, window: _window(hasBook: false));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('it fetches its own month', () {
    testWidgets('on first build, for the current month', (t) async {
      final repo = _Repo();
      await _pump(t, repo: repo);
      expect(repo.months, isNotEmpty);
      expect(repo.months.first, monthOf(DateTime.now().toUtc()));
    });

    testWidgets('and renders THAT payload, not the window\'s', (t) async {
      // The month summary is +$9.20; the window's is +$51.85. If the card ever
      // borrowed the window's book, this is what would catch it.
      await _pump(t);
      expect(find.text('+\$9.20'), findsOneWidget);
      expect(find.text('+\$51.85'), findsNothing);
    });

    testWidgets('stepping back refetches the previous month', (t) async {
      final repo = _Repo();
      await _pump(t, repo: repo);
      await t.tap(find.byTooltip('Previous month'));
      await t.pumpAndSettle();
      expect(repo.months.length, 2);
      expect(repo.months.last, shiftMonth(repo.months.first, -1));
    });
  });

  group('a step in flight paints no claim at all', () {
    testWidgets('cells hold neither month while the fetch is open', (t) async {
      // `MonthCalendar` keys its cells off the requested month and treats a
      // payload for any other month as stale. Painting the old month's numbers
      // under the new heading is the two-surfaces-one-name defect at the speed
      // of a tap.
      final repo = _Repo(delay: const Duration(milliseconds: 300));
      await tester_pumpWithDelay(t, repo);

      // Mid-flight: the grid is drawn, and no day carries a figure.
      expect(find.byKey(const ValueKey('month-calendar')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('month-calendar')),
          matching: find.text('+8.0'),
        ),
        findsNothing,
      );

      await t.pumpAndSettle();
      // Settled: the month's own figures appear.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('month-calendar')),
          matching: find.text('+8.0'),
        ),
        findsOneWidget,
      );
    });
  });

  group('the size is named on this card too', () {
    testWidgets('a grid of dollar figures says what size they assume',
        (t) async {
      // Every cell is a dollar figure. A grid whose size the reader cannot see
      // is an assumption wearing a measurement's clothes, thirty times over.
      await _pump(t);
      expect(_text(t), contains('100 usdt'));
      expect(_text(t), contains('utc'));
    });

    testWidgets('and it renders the size the ENGINE reported', (t) async {
      await _pump(t);
      expect(_text(t), contains('at 100 usdt'));
      expect(_text(t), isNot(contains('at 250 usdt')));
    });
  });

  group('the honesty furniture moved here with the grid', () {
    // 2026-08-12: the Pulse rolling-window card was removed and this one kept
    // (*"we don't need two track cards there, keep that signal book by day"*).
    // That card carried the RECORDED badge and the sentences that make a
    // performance figure showable at all. They are not decoration on the card
    // that left — they are conditions on reading the one that stayed, and a
    // layout change silently dropping them is the single regression this card
    // must never ship. None of these assertions passes against the pre-move
    // card, which is what makes them a guard rather than a restatement.

    testWidgets('RECORDED — these trades happened, they were not replayed',
        (t) async {
      // The word that separates this book from every back-test, what-if and
      // counterfactual surface we run internally (~0.38R optimistic). A reader
      // must be able to tell at a glance which one they are looking at.
      await _pump(t);
      expect(find.text('RECORDED'), findsOneWidget);
      expect(_text(t), contains('not a back-test'));
    });

    testWidgets('the reader is told this book is not their own', (t) async {
      // Pooled, at one fixed notional, on our delivered signals. What any
      // individual receives depends on their settings and their fills, and a
      // figure that reads as the reader's own account is the flattering
      // misreading — so the correction is on screen, not inferred.
      await _pump(t);
      expect(_text(t), contains('your own results will differ'));
      expect(_text(t), contains('your settings and your fills'));
    });

    testWidgets('past performance carries no promise about the next month',
        (t) async {
      await _pump(t);
      expect(
        _text(t),
        contains('past signal performance does not guarantee future results'),
      );
    });

    testWidgets('the fee is named, and comes from the ENGINE', (t) async {
      // A net figure with an unnamed fee is a gross figure the reader will
      // read as net. The rate is the engine's, never a constant here.
      await _pump(t);
      expect(_text(t), contains('0.07% round-trip fee charged'));
    });

    testWidgets('the tap it promises is a tap it has', (t) async {
      // The footer says "tap for every day and every signal". A promise with
      // no control behind it is how a reader learns the card does nothing —
      // this card is now the ONLY route from Pulse into the full record.
      await _pump(t);
      expect(_text(t), contains('tap for every day and every signal'));
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
    });
  });

  group('the — convention survives on the compact grid', () {
    testWidgets('a day with no close reads — and never 0.00', (t) async {
      await _pump(t);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('month-calendar')),
          matching: find.text('—'),
        ),
        findsWidgets,
      );
      expect(find.text('0.0'), findsNothing);
      expect(find.text('+0.0'), findsNothing);
      expect(_text(t), contains('nothing closed that day'));
    });
  });
}

/// Pump without settling, so the in-flight state can be observed.
Future<void> tester_pumpWithDelay(WidgetTester t, _Repo repo) async {
  await t.binding.setSurfaceSize(const Size(430, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TrackRecordMonthCard(window: _window(), repo: repo),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

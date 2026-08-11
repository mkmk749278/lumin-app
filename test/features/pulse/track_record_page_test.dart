/// `TrackRecordPage` — the drill-down behind the Pulse card.
///
/// Modelled on Binance's Futures PNL Analysis. What is pinned here is the three
/// mechanics that were worth taking from it, and the three places we
/// deliberately diverge — because a divergence nobody asserted is
/// indistinguishable from an omission six months later.
///
/// Taken: a bars⇄calendar toggle on one section of data; tap a day and the
/// header reads it back; the daily bars and the running total as **separate**
/// charts, each with its own axis.
///
/// Changed: no invented account fields; a day on which nothing closed reads
/// `—` and never `0.00`; and the calendar is a week grid over the fetched
/// window rather than a month with a stepper into months we never loaded.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/features/pulse/track_record_page.dart';

TrackRecordDay _day(String date, double? net,
        {double cum = 0.0, String? partial, int trades = 3}) =>
    TrackRecordDay(
      date: date,
      trades: trades,
      moves: trades,
      wins: (net ?? 0) > 0 ? 2 : 1,
      losses: (net ?? 0) > 0 ? 1 : 2,
      netUsd: net,
      netPct: net,
      cumNetUsd: cum,
      partialReason: partial,
    );

/// 2026-08-04 … 2026-08-11, with **2026-08-06 and 2026-08-07 absent** — days
/// on which nothing closed. The engine omits them; the calendar must still
/// draw a cell for each, and it must read `—`.
TrackRecord _record({double amount = 100.0}) => TrackRecord(
      enabled: true,
      unavailableReason: '',
      days: 30,
      amountUsdt: amount,
      feePct: 0.07,
      rangeStart: '2026-08-04',
      summary: const TrackRecordSummary(
        trades: 12, moves: 11, tradesPriced: 12, wins: 5, losses: 7,
        winRate: 0.4167, grossUsd: 30.0, feeUsd: 0.84, netUsd: 29.16,
        avgPnlPct: 2.5, avgNetPct: 2.43, bestPnlPct: 9.4, worstPnlPct: -6.1,
      ),
      items: [
        _day('2026-08-04', 8.0, cum: 8.0),
        _day('2026-08-05', -5.0, cum: 3.0),
        _day('2026-08-08', 12.0, cum: 15.0),
        _day('2026-08-09', -2.0, cum: 13.0),
        _day('2026-08-10', 20.0, cum: 33.0),
        _day('2026-08-11', -3.84, cum: 29.16, partial: 'in_progress'),
      ],
    );

/// Repository that answers the page's two fetches from fixed data.
class _Repo extends MockRepository {
  _Repo({this.signals});
  final TrackRecordSignals? signals;
  int signalCalls = 0;
  String lastDate = 'never-called';

  @override
  Future<TrackRecord> fetchTrackRecord({int days = 30}) async => _record();

  @override
  Future<TrackRecordSignals> fetchTrackRecordSignals({
    int days = 30,
    String date = '',
    int limit = 200,
  }) async {
    signalCalls++;
    lastDate = date;
    return signals ??
        TrackRecordSignals(
          enabled: true,
          date: date,
          matched: 2,
          truncated: false,
          items: [
            TrackRecordSignal(
              signalId: 'A', symbol: 'BTCUSDT', direction: 'LONG',
              setup: 'MOVER_TREND_PULLBACK', regime: 'TRENDING_UP',
              outcome: 'TP1_HIT', entry: 30000, closedAt: '2026-08-10T04:00:00Z',
              pnlPct: 2.0, netPct: 1.93, netUsd: 1.93,
            ),
            const TrackRecordSignal(
              signalId: 'B', symbol: 'SOLUSDT', direction: 'SHORT',
              setup: 'MOVER_AVWAP_SCALP', regime: 'RANGING',
              outcome: '', entry: 100, closedAt: '2026-08-10T02:00:00Z',
              pnlPct: null, netPct: null, netUsd: null,
            ),
          ],
        );
  }
}

/// A phone-width but very tall surface, so the whole page is BUILT.
///
/// The page is a `ListView`; off-screen children are not built, so on the
/// default 800px test surface `find.text` cannot see the running-total section
/// or the signals list at all. Scrolling in each test would work and would
/// also mean every assertion silently depends on a scroll offset. A tall
/// surface keeps the assertions about the page rather than about the viewport.
Future<void> _pump(WidgetTester tester, {_Repo? repo}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: TrackRecordPage(initial: _record(), repo: repo ?? _Repo()),
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
  group('the three sections Binance separates, separated here too', () {
    testWidgets('daily and running total are distinct sections', (t) async {
      await _pump(t);
      expect(find.text('DAILY RESULT'), findsOneWidget);
      expect(find.text('RUNNING TOTAL'), findsOneWidget);
      // Overlaying them costs both marks their axis, and a number you cannot
      // read off a chart is decoration.
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('the signals list is on the page, not behind a tab', (t) async {
      await _pump(t);
      expect(find.textContaining('SIGNALS IN THIS WINDOW'), findsOneWidget);
      expect(find.text('BTCUSDT'), findsOneWidget);
    });
  });

  group('the day readout — what turns a picture into a record', () {
    testWidgets('nothing is selected until the reader picks a day', (t) async {
      await _pump(t);
      expect(_text(t), contains('tap a day to see what closed on it'));
    });

    testWidgets('picking a day in the calendar reads it back', (t) async {
      final repo = _Repo();
      await _pump(t, repo: repo);
      await t.tap(find.byTooltip('Calendar'));
      await t.pumpAndSettle();
      // 2026-08-10 rendered +20.0 in the grid.
      await t.tap(find.text('+20.0'));
      await t.pumpAndSettle();
      final text = _text(t);
      expect(text, contains('10 aug utc'));
      expect(text, contains('+\$20.00'));
      expect(repo.lastDate, '2026-08-10');
    });

    testWidgets('...and it scopes the signals list to that day', (t) async {
      await _pump(t);
      await t.tap(find.byTooltip('Calendar'));
      await t.pumpAndSettle();
      await t.tap(find.text('+20.0'));
      await t.pumpAndSettle();
      expect(find.textContaining('SIGNALS ON 10 AUG'), findsOneWidget);
      // ...and offers the way back out.
      expect(find.text('Show all'), findsOneWidget);
    });

    testWidgets('the selection is one question, not three', (t) async {
      // The readout, the chart highlight and the list all follow `_selected`.
      // Letting them drift is how a page starts describing two different days
      // at once.
      final repo = _Repo();
      await _pump(t, repo: repo);
      await t.tap(find.byTooltip('Calendar'));
      await t.pumpAndSettle();
      await t.tap(find.text('-5.0'));
      await t.pumpAndSettle();
      expect(_text(t), contains('5 aug utc'));
      expect(repo.lastDate, '2026-08-05');
      expect(find.textContaining('SIGNALS ON 5 AUG'), findsOneWidget);
    });

    testWidgets('today is labelled still running, not shown as finished',
        (t) async {
      await _pump(t);
      await t.tap(find.byTooltip('Calendar'));
      await t.pumpAndSettle();
      await t.tap(find.text('-3.8'));
      await t.pumpAndSettle();
      expect(_text(t), contains('still running'));
    });
  });

  group('the calendar, and the reason it exists', () {
    testWidgets('a day on which nothing closed reads — and never 0.00',
        (t) async {
      // For an exchange a zero day is true: you traded nothing, so you made
      // nothing. Here 0.00 would assert that signals closed and netted flat.
      // The bar chart omits such a day entirely and cannot draw the difference
      // between a quiet day and a missing one — which is most of why this view
      // exists at all.
      await _pump(t);
      await t.tap(find.byTooltip('Calendar'));
      await t.pumpAndSettle();
      // 2026-08-06 and 2026-08-07 are absent from the series. Scoped to the
      // calendar: the signals list below also renders — for a trade whose
      // outcome could not be read, and counting both together would pass for
      // the wrong reason.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('track-record-calendar')),
          matching: find.text('—'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('0.0'), findsNothing);
      expect(find.text('+0.0'), findsNothing);
      expect(_text(t), contains('nothing closed that day'));
    });

    testWidgets('every day in the window gets a cell', (t) async {
      await _pump(t);
      await t.tap(find.byTooltip('Calendar'));
      await t.pumpAndSettle();
      // 4th through 11th inclusive.
      for (final d in ['4', '5', '6', '7', '8', '9', '10', '11']) {
        expect(find.text(d), findsWidgets, reason: 'day $d');
      }
    });

    testWidgets('a day with nothing to open is not tappable', (t) async {
      final repo = _Repo();
      await _pump(t, repo: repo);
      await t.tap(find.byTooltip('Calendar'));
      await t.pumpAndSettle();
      final before = repo.signalCalls;
      await t.tap(find.text('—').first);
      await t.pumpAndSettle();
      expect(repo.signalCalls, before);
    });

    testWidgets('the toggle switches back to bars', (t) async {
      await _pump(t);
      await t.tap(find.byTooltip('Calendar'));
      await t.pumpAndSettle();
      expect(find.text('+20.0'), findsOneWidget);
      await t.tap(find.byTooltip('Bars'));
      await t.pumpAndSettle();
      // The calendar's cell labels are gone; the bar chart is drawn instead.
      expect(find.text('+20.0'), findsNothing);
    });
  });

  group('the signal rows', () {
    testWidgets('a row names the trade a reader would recognise', (t) async {
      await _pump(t);
      expect(find.text('BTCUSDT'), findsOneWidget);
      expect(find.text('LONG'), findsOneWidget);
      final text = _text(t);
      expect(text, contains('tp1_hit'));
      // The setup class is an engine identifier; a subscriber should not have
      // to read SCREAMING_SNAKE.
      expect(text, contains('mover trend pullback'));
      expect(text, isNot(contains('mover_trend_pullback')));
    });

    testWidgets('a signal whose outcome could not be read is LISTED', (t) async {
      // It is part of what closed that day. Dropping it would make the list
      // disagree with the count above it.
      await _pump(t);
      expect(find.text('SOLUSDT'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('a truncated list says so, and against what', (t) async {
      final repo = _Repo(
        signals: TrackRecordSignals(
          enabled: true, date: '', matched: 640, truncated: true,
          items: [
            const TrackRecordSignal(
              signalId: 'A', symbol: 'BTCUSDT', direction: 'LONG',
              setup: 'X', regime: '', outcome: 'TP1_HIT', entry: 1,
              closedAt: '', pnlPct: 1.0, netPct: 0.93, netUsd: 0.93,
            ),
          ],
        ),
      );
      await _pump(t, repo: repo);
      expect(_text(t), contains('showing the newest 1 of 640'));
    });
  });

  group('the honesty furniture survives the bigger surface', () {
    testWidgets('RECORDED is on the page, not only on the card', (t) async {
      await _pump(t);
      expect(find.text('RECORDED'), findsOneWidget);
    });

    testWidgets('the size, the fee and the — convention are all stated',
        (t) async {
      await _pump(t);
      final text = _text(t);
      expect(text, contains('100 usdt'));
      expect(text, contains('0.07% round-trip'));
      expect(text, contains('not a back-test'));
      expect(text, contains('a day showing — is a day on which nothing closed'));
      expect(text, contains('all dates are utc'));
      expect(text,
          contains('past signal performance does not guarantee future results'));
    });

    testWidgets('gross and fees render beside net, never instead of it',
        (t) async {
      // The cost of trading on this book runs several times the edge, so a
      // gross-only figure answers a question nobody asked.
      await _pump(t);
      expect(find.text('GROSS'), findsOneWidget);
      expect(find.text('FEES'), findsOneWidget);
      expect(find.text('NET'), findsOneWidget);
      expect(find.text('-\$0.84'), findsOneWidget);
    });
  });
}

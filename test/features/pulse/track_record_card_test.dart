/// `TrackRecordCard` — what the Pulse tab actually says about our record.
///
/// The engine owns the arithmetic and the model test owns the wire contract.
/// What is pinned here is the thing neither of those can see: **the sentences
/// on screen**, which on a performance surface are part of the measurement.
/// A wrong caption over correct figures is still a wrong card, and this repo's
/// companions have paid for that three times — a benign caption over a broken
/// ledger, an alarming one over a healthy subsystem, an alert page describing a
/// delivery path it did not have.
///
/// Four things must hold however the numbers move:
///
///  * the card **hides** rather than showing a claim we could not verify;
///  * it never presents itself as the reader's own account;
///  * it names the position size beside every dollar figure, and the fee;
///  * it repeats the past-performance disclaimer the user agreed to at
///    consent, rather than assuming they remember it a month later.
///
/// The card reaches `AppConfigScope` only inside the window-chip tap handler
/// (a network refetch), so rendering is exercised without an app scope.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/features/pulse/track_record_card.dart';
import 'package:lumin/features/pulse/track_record_page.dart';

TrackRecordDay _day(
  String date,
  double net, {
  double cum = 0.0,
  String? partial,
}) =>
    TrackRecordDay(
      date: date,
      trades: 3,
      moves: 3,
      wins: net > 0 ? 2 : 1,
      losses: net > 0 ? 1 : 2,
      netUsd: net,
      netPct: net,
      cumNetUsd: cum,
      partialReason: partial,
    );

TrackRecord _record({
  bool enabled = true,
  String reason = '',
  int trades = 407,
  int moves = 394,
  int? tradesPriced,
  double? netUsd = 51.85,
  double amount = 100.0,
  double fee = 0.07,
  List<TrackRecordDay>? items,
}) =>
    TrackRecord(
      enabled: enabled,
      unavailableReason: reason,
      days: 30,
      amountUsdt: amount,
      feePct: fee,
      rangeStart: '2026-07-12',
      summary: TrackRecordSummary(
        trades: trades,
        moves: moves,
        tradesPriced: tradesPriced ?? trades,
        wins: 141,
        losses: 266,
        winRate: 0.3464,
        grossUsd: 80.34,
        feeUsd: 28.49,
        netUsd: netUsd,
        avgPnlPct: 0.197,
        avgNetPct: 0.127,
        bestPnlPct: 12.71,
        worstPnlPct: -9.60,
      ),
      items: items ??
          [
            _day('2026-08-09', 14.59, cum: 42.55),
            _day('2026-08-10', 12.51, cum: 55.06),
            _day('2026-08-11', -3.21, cum: 51.85, partial: 'in_progress'),
          ],
    );

Widget _wrap(TrackRecord r) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: TrackRecordCard(initial: r)),
      ),
    );

/// Every rendered string on the card, lowercased, joined.
String _text(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .join(' • ')
    .toLowerCase();

void main() {
  group('when the card renders at all', () {
    testWidgets('a book with priced trades shows', (tester) async {
      await tester.pumpWidget(_wrap(_record()));
      expect(find.textContaining('SIGNAL TRACK RECORD'), findsOneWidget);
    });

    testWidgets('the owner switching the record off hides it entirely',
        (tester) async {
      await tester.pumpWidget(
        _wrap(_record(enabled: false, reason: 'disabled', items: [])),
      );
      // Not an explanation, not an empty state — nothing. A subscriber does
      // not need our plumbing explained, and an empty performance card reads
      // as "the signals made nothing".
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('a failed fetch hides it rather than showing an empty book',
        (tester) async {
      // `assemblePulseBundle` falls back to TrackRecord.empty on any error.
      await tester.pumpWidget(_wrap(TrackRecord.empty));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('trades that could not be priced hide it', (tester) async {
      await tester.pumpWidget(
        _wrap(_record(trades: 12, tradesPriced: 0, netUsd: null, items: [])),
      );
      expect(find.byType(Text), findsNothing);
    });
  });

  group('the sentences that make it honest', () {
    testWidgets('it says RECORDED — not a back-test', (tester) async {
      await tester.pumpWidget(_wrap(_record()));
      final text = _text(tester);
      expect(text, contains('recorded'));
      expect(text, contains('not a back-test'));
    });

    testWidgets('it names the position size beside the money', (tester) async {
      // A dollar figure whose size the reader cannot see is an assumption
      // wearing a measurement's clothes.
      await tester.pumpWidget(_wrap(_record(amount: 100.0)));
      expect(_text(tester), contains('100 usdt'));
    });

    testWidgets('a non-default size is rendered, never the hardcoded default',
        (tester) async {
      // The engine decides the size and sends it back; if the card ever
      // hardcoded "100 USDT" the sentence would silently stop describing the
      // numbers beside it.
      await tester.pumpWidget(_wrap(_record(amount: 250.0)));
      final text = _text(tester);
      expect(text, contains('250 usdt'));
      expect(text, isNot(contains('100 usdt')));
    });

    testWidgets('it says the fee was charged, and at what rate', (tester) async {
      await tester.pumpWidget(_wrap(_record(fee: 0.07)));
      final text = _text(tester);
      expect(text, contains('fees paid'));
      expect(text, contains('0.07% round-trip'));
    });

    testWidgets('it disclaims past performance', (tester) async {
      // The same sentence the user ticked at consent. A month later they are
      // reading a green number, not their consent screen.
      await tester.pumpWidget(_wrap(_record()));
      expect(
        _text(tester),
        contains('past signal performance does not guarantee future results'),
      );
    });

    testWidgets('it says the reader\'s own results will differ', (tester) async {
      // Per-user dispatch caps mean two users on identical settings do not
      // receive identical books, so this is a fact and not a hedge.
      await tester.pumpWidget(_wrap(_record()));
      expect(_text(tester), contains('your own results will differ'));
    });

    testWidgets('it never claims to be the reader\'s own account',
        (tester) async {
      // "YOUR PAPER P&L" is a different card reading a different book. If this
      // one ever grows a possessive, the two become one book in the reader's
      // head and a disagreement between them reads as a bug.
      await tester.pumpWidget(_wrap(_record()));
      final text = _text(tester);
      for (final banned in ['your p&l', 'your profit', 'you made', 'your book']) {
        expect(text, isNot(contains(banned)), reason: banned);
      }
    });

    testWidgets('it marks the clock as UTC', (tester) async {
      // A UTC day ends at 05:30 IST, so a date with no zone is the same class
      // of omission as a percentage with no denominator.
      await tester.pumpWidget(_wrap(_record()));
      expect(_text(tester), contains('utc'));
    });
  });

  group('what the headline is, and is not', () {
    testWidgets('it leads with money at a stated size', (tester) async {
      await tester.pumpWidget(_wrap(_record(netUsd: 51.85)));
      expect(find.text('+\$51.85'), findsOneWidget);
    });

    testWidgets('it does NOT lead with a summed percentage', (tester) async {
      // Summing per-trade percentages at a fixed notional is arithmetically
      // fine and reads as something it is not: "+51.85%" over a month looks
      // like an account return, while the same book needed ~400 USDT to hold
      // its peak concurrent positions. A reader cannot be expected to make
      // that correction, and the figure flatters us when they fail to.
      await tester.pumpWidget(_wrap(_record()));
      expect(find.text('+51.85%'), findsNothing);
      expect(find.text('+80.34%'), findsNothing);
    });

    testWidgets('a losing window renders its sign', (tester) async {
      await tester.pumpWidget(_wrap(_record(netUsd: -12.40)));
      expect(find.text('-\$12.40'), findsOneWidget);
    });
  });

  group('the disclosures beside the counts', () {
    testWidgets('distinct moves are shown when they differ from trades',
        (tester) async {
      // Overlapping entries into one move exit at the same price and are not
      // independent evidence. Disclosed, never de-duplicated.
      await tester.pumpWidget(_wrap(_record(trades: 407, moves: 394)));
      expect(_text(tester), contains('394 distinct moves'));
    });

    testWidgets('...and suppressed when every trade is its own move',
        (tester) async {
      await tester.pumpWidget(_wrap(_record(trades: 12, moves: 12)));
      expect(_text(tester), isNot(contains('distinct moves')));
    });

    testWidgets('an unpriced shortfall is stated, not silently dropped',
        (tester) async {
      await tester.pumpWidget(
        _wrap(_record(trades: 100, tradesPriced: 91, moves: 100)),
      );
      expect(_text(tester), contains('9 of 100 could not be priced'));
    });

    testWidgets('...and nothing is said when every trade priced',
        (tester) async {
      await tester.pumpWidget(_wrap(_record(trades: 100, tradesPriced: 100)));
      expect(_text(tester), isNot(contains('could not be priced')));
    });
  });

  group('TrackRecordChartScale — a loss must not be drawn smaller than it is',
      () {
    // The defect this guards was found by looking at the rendered chart, not
    // by a test: on the owner's real 30-day book a -$22.85 day drew about a
    // third as tall as a +$26.18 day, because the zero line was placed by the
    // running total's range and each side then filled whatever room was left.
    // Every number behind it was correct and the chart said the losses were
    // small — the one direction a performance surface must never be wrong in,
    // and invisible without measuring pixels. So the property is asserted here
    // rather than left to a glance.
    const h = 96.0;

    double distance(TrackRecordChartScale s, double v, List<double> series) =>
        (s.y(v, series) - s.zeroY).abs();

    test('equal magnitudes either side of zero are equal distances', () {
      final bars = [26.18, -22.85, 14.59, -3.21];
      final s = TrackRecordChartScale.of(h, [bars]);
      expect(distance(s, 20.0, bars), closeTo(distance(s, -20.0, bars), 1e-9));
      expect(distance(s, 5.0, bars), closeTo(distance(s, -5.0, bars), 1e-9));
    });

    test('...and it still holds with a second, far larger series present', () {
      // This is the real configuration: daily bars against a running total an
      // order of magnitude bigger. The asymmetry entered exactly here.
      final bars = [26.18, -22.85, 14.59, -3.21];
      final cums = [6.04, -29.08, 42.55, 55.06, 51.85];
      final s = TrackRecordChartScale.of(h, [bars, cums]);
      expect(distance(s, 26.18, bars), closeTo(distance(s, -26.18, bars), 1e-9));
      expect(distance(s, 55.06, cums), closeTo(distance(s, -55.06, cums), 1e-9));
    });

    test('the pre-fix placement would have failed this', () {
      // Sanity on the vector itself: with zero placed by the running total's
      // range alone, the two sides genuinely differ — so the assertions above
      // are testing something, not restating an identity.
      final cums = [6.04, -29.08, 42.55, 55.06, 51.85];
      final hi = cums.reduce((a, b) => a > b ? a : b);
      final lo = cums.reduce((a, b) => a < b ? a : b);
      final zeroFrac = hi / (hi - lo);
      expect(zeroFrac * h, greaterThan((1 - zeroFrac) * h * 1.5));
    });

    test('each series keeps its own full scale', () {
      // A day's result and a month's running total differ by an order of
      // magnitude; one shared magnitude scale would flatten the bars into the
      // axis. Their peaks should reach comparable extents.
      final bars = [26.18, -22.85];
      final cums = [55.06, -29.08];
      final s = TrackRecordChartScale.of(h, [bars, cums]);
      expect(distance(s, 26.18, bars), closeTo(distance(s, 55.06, cums), 1e-9));
    });

    test('an all-positive book does not waste half the chart below zero', () {
      final bars = [1.0, 2.0, 3.0];
      final s = TrackRecordChartScale.of(h, [bars]);
      // Zero sits at the bottom, so the whole height carries the book.
      expect(s.zeroY, greaterThan(h * 0.9));
      expect(s.y(3.0, bars), lessThan(h * 0.1));
    });

    test('an all-negative book mirrors it', () {
      final bars = [-1.0, -2.0, -3.0];
      final s = TrackRecordChartScale.of(h, [bars]);
      expect(s.zeroY, lessThan(h * 0.1));
      expect(s.y(-3.0, bars), greaterThan(h * 0.9));
    });

    test('a flat book does not divide by zero', () {
      final s = TrackRecordChartScale.of(h, [
        [0.0, 0.0]
      ]);
      expect(s.y(0.0, [0.0, 0.0]), s.zeroY);
      expect(s.zeroY.isFinite, isTrue);
    });

    test('an empty series does not divide by zero', () {
      final s = TrackRecordChartScale.of(h, [<double>[]]);
      expect(s.zeroY.isFinite, isTrue);
      expect(s.y(1.0, <double>[]), s.zeroY);
    });

    test('nothing is drawn outside the canvas', () {
      final bars = [26.18, -22.85];
      final cums = [55.06, -29.08];
      final s = TrackRecordChartScale.of(h, [bars, cums]);
      for (final v in bars) {
        expect(s.y(v, bars), inInclusiveRange(0, h));
      }
      for (final v in cums) {
        expect(s.y(v, cums), inInclusiveRange(0, h));
      }
    });
  });

  group('window chips', () {
    testWidgets('three windows render and the initial one is selected',
        (tester) async {
      await tester.pumpWidget(_wrap(_record()));
      for (final w in ['7D', '30D', '90D']) {
        expect(find.text(w), findsOneWidget);
      }
    });
  });

  group('the card opens the full record', () {
    // Paid for during this change. An edit script aborted after rewriting the
    // footer and before adding the tap handler, so the card shipped saying
    // "Tap for every day and every signal behind these numbers" over a card
    // that did nothing when tapped. Twenty-nine passing tests saw none of it:
    // every one asserted a string or a figure, and the promise and the control
    // are two halves that only meet on screen. A control that does nothing is
    // indistinguishable from a broken page.

    testWidgets('tapping it pushes the track record page', (tester) async {
      await tester.pumpWidget(_wrap(_record()));
      await tester.tap(find.text('SIGNAL TRACK RECORD'));
      await tester.pumpAndSettle();
      expect(find.byType(TrackRecordPage), findsOneWidget);
    });

    testWidgets('the page opens on the window the card was showing',
        (tester) async {
      // Opening the page must continue the reader's context, not reset it.
      await tester.pumpWidget(_wrap(_record()));
      await tester.tap(find.text('SIGNAL TRACK RECORD'));
      await tester.pumpAndSettle();
      final page = tester.widget<TrackRecordPage>(find.byType(TrackRecordPage));
      expect(page.initial.days, 30);
    });

    testWidgets('and it shows an affordance rather than only promising one',
        (tester) async {
      await tester.pumpWidget(_wrap(_record()));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(_text(tester), contains('tap for every day'));
    });
  });
}

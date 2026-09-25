/// Lumin read (Charts redesign part 3): engine payload → model → chart
/// overlay and sheet. The payload is the engine's /api/pairs/{symbol}/context
/// shape (360-v2 #1068).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/pair_context.dart';
import 'package:lumin/features/charts/models/context_overlay.dart';
import 'package:lumin/features/charts/pair_read_sheet.dart';

Map<String, dynamic> _payload({bool locked = false}) => {
      'symbol': 'SOLUSDT',
      'state': 'covered',
      'generated_at': 1790000000.0,
      'context': {
        'price': 100.0,
        'read_at': 1790000000.0,
        'supports': [
          {'price': 99.2, 'dist_pct': -0.8, 'touches': 4, 'timeframes': ['4h'], 'round_number': false},
        ],
        'resistances': [
          {'price': 104.0, 'dist_pct': 4.0, 'touches': 3, 'timeframes': ['1d'], 'round_number': false},
        ],
        'volume_profile': {'poc': 98.0, 'vah': 99.0, 'val': 96.0, 'position': 'above_value'},
        'structure_4h': {'state': 'BULL_LEG', 'confidence': 0.8, 'last_hh': 101.0},
      },
      'checklist': locked
          ? null
          : {
              'long': ['4h structure is making higher highs and higher lows'],
              'short': [],
              'neutral': ['Something neutral'],
            },
      'checklist_locked': locked,
      'past_signals': [
        {'direction': 'LONG', 'entry': 99, 'outcome': 'TP1_HIT', 'pnl_pct': 1.2,
         'opened_at_ts': 1789999000.0, 'closed_at_ts': 1789999900.0},
        {'direction': 'SHORT', 'entry': 101, 'outcome': 'SL_HIT', 'pnl_pct': -0.9,
         'opened_at_ts': 1789990000.0, 'closed_at_ts': 1789995000.0},
        {'direction': 'LONG', 'entry': 90, 'outcome': 'TP1_HIT', 'pnl_pct': 2.0,
         'opened_at_ts': 1000.0, 'closed_at_ts': 2000.0},
      ],
    };

void main() {
  group('model', () {
    test('parses the engine payload', () {
      final c = PairContext.fromJson(_payload());
      expect(c.state, PairContextState.covered);
      expect(c.supports.single.price, 99.2);
      expect(c.resistances.single.distPct, 4.0);
      expect(c.valueArea!.position, 'above_value');
      expect(c.structure4h!.words, 'Higher highs and higher lows');
      expect(c.checklist!.long, hasLength(1));
      expect(c.pastSignals, hasLength(3));
      expect(c.pastSignals[1].won, isFalse);
    });

    test('three states; an older engine or junk never reads as covered', () {
      expect(PairContext.fromJson({'state': 'not_tracked'}).state, PairContextState.notTracked);
      expect(PairContext.fromJson({'state': 'weird'}).state, PairContextState.notReported);
      expect(PairContext.fromJson({'state': 'covered', 'context': null}).state, PairContextState.notReported);
      final c = PairContext.fromJson({'state': 'covered', 'context': {'price': 'x', 'supports': [{'price': -1}]}});
      expect(c.price, isNull);
      expect(c.supports, isEmpty);
    });
  });

  group('overlay', () {
    test('bands for every level, POC line, a marker per past signal on its bar', () {
      final c = PairContext.fromJson(_payload());
      final o = ContextChartOverlay.from(c, tfSeconds: 900, oldestBar: 1789000000, newestBar: 1790000000);
      expect(o.zones, hasLength(2));
      expect(o.zones.first['low'], lessThan(99.2));
      expect(o.zones.first['high'], greaterThan(99.2));
      expect(o.lines.single['title'], 'POC');
      // The third signal opened before the loaded candles: dropped, not drawn at the edge.
      expect(o.markers, hasLength(2));
      expect(o.markers.first['time'] % 900, 0);
    });

    test('losses are drawn as well as wins, in their own colour', () {
      final o = ContextChartOverlay.from(PairContext.fromJson(_payload()), tfSeconds: 900);
      final colors = o.markers.map((m) => m['color']).toSet();
      expect(colors, containsAll(['#22e39b', '#ff4d6d']));
      expect(o.markers.map((m) => m['text']), containsAll(['+1.2%', '-0.9%']));
    });
  });

  group('sheet', () {
    Future<void> pump(WidgetTester t, PairContext? c) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: PairReadView(symbol: 'SOLUSDT', read: c))));
    }

    testWidgets('covered: structure, levels, both sides, and every past signal', (t) async {
      await pump(t, PairContext.fromJson(_payload()));
      expect(find.text('Higher highs and higher lows'), findsOneWidget);
      expect(find.text('WHAT SITS WITH A LONG'), findsOneWidget);
      expect(find.text('WHAT SITS WITH A SHORT'), findsOneWidget);
      expect(find.text('Nothing measured on this side right now.'), findsOneWidget);
      await t.scrollUntilVisible(find.textContaining('every one shown'), 200);
      expect(find.textContaining('3 closed · 2 won · 1 lost'), findsOneWidget);
    });

    testWidgets('locked: no checklist text, an unlock card instead', (t) async {
      await pump(t, PairContext.fromJson(_payload(locked: true)));
      expect(find.text('WHAT SITS WITH A LONG'), findsNothing);
      expect(find.textContaining('Part of the Signals plan'), findsOneWidget);
      // Levels stay free.
      expect(find.text('NEAREST LEVELS'), findsOneWidget);
    });

    testWidgets('not tracked says so and still shows the record', (t) async {
      await pump(t, PairContext.fromJson({'symbol': 'PEPEUSDT', 'state': 'not_tracked', 'past_signals': []}));
      expect(find.textContaining("Lumin doesn't scan this pair"), findsOneWidget);
      expect(find.textContaining('No closed Lumin signals'), findsOneWidget);
    });

    testWidgets('never words a verdict', (t) async {
      await pump(t, PairContext.fromJson(_payload()));
      for (final w in ['Buy', 'Sell', 'Bullish', 'Bearish', 'score']) {
        expect(find.textContaining(w), findsNothing, reason: w);
      }
    });
  });
}

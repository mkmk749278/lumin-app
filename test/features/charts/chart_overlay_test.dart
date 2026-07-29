/// ChartOverlay derivation from a Lumin signal — the entry/SL/TP/BE payload
/// the chart bridge draws. Asserts the BE-armed inference (stop snaps to entry
/// once MFE ≥ +1%), the null-TP handling, and — since 2026-07-29 — that
/// lifecycle markers are anchored on the engine's stamps rather than computed.
///
/// The marker tests exist because a computed anchor shipped and was wrong for
/// months: the entry was reconstructed as `now - minutesAgo`, and `minutes_ago`
/// measures from the *terminal* event on a closed signal, so the arrow
/// captioned ENTRY was drawn at the exit. `_cotiAsOwnerSawIt` reproduces the
/// case the owner caught from the ops CSV.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/mock_data.dart';
import 'package:lumin/features/charts/models/chart_overlay.dart';

MockSignal _sig({
  String status = 'ACTIVE',
  double mfe = 0.0,
  double sl = 0.09,
  double tp1 = 0.11,
  double tp2 = 0.12,
  double tp3 = 0.13,
  int minutesAgo = 30,
  String direction = 'LONG',
  DateTime? openedAt,
  DateTime? closedAt,
  bool? isOpen,
}) {
  return MockSignal(
    id: 'MVRTP-1',
    symbol: 'GUAUSDT',
    direction: direction,
    setupName: 'Mover trend pullback',
    agentName: 'Mover',
    entry: 0.10,
    sl: sl,
    tp1: tp1,
    tp2: tp2,
    tp3: tp3,
    confidence: 80,
    tier: 'B',
    status: status,
    pnlPct: 0.0,
    minutesAgo: minutesAgo,
    openedAt: openedAt,
    closedAt: closedAt,
    isOpen: isOpen,
    maxFavorableExcursionPct: mfe,
  );
}

/// COTIUSDT SHORT, 2026-07-29, from the owner's export: created 03:00:33 UTC,
/// SL hit ~65 minutes later. The app rendered its ENTRY arrow at 04:05 —
/// on the SL line — because it derived the time from `minutes_ago`, which for
/// a closed signal counts from the exit.
MockSignal _cotiAsOwnerSawIt() => _sig(
      direction: 'SHORT',
      status: 'SL_HIT',
      isOpen: false,
      openedAt: DateTime.utc(2026, 7, 29, 3, 0, 33),
      closedAt: DateTime.utc(2026, 7, 29, 4, 5, 0),
      // What the engine sends alongside: recency of the *terminal* event.
      minutesAgo: 3,
    );

void main() {
  test('below +1% MFE: stop stays at original SL, not armed', () {
    final o = ChartOverlay.fromSignal(_sig(mfe: 0.4));
    expect(o.beArmed, isFalse);
    expect(o.stop, 0.09);
    expect(o.side, 'LONG');
    expect(o.tp1, 0.11);
  });

  test('at/above +1% MFE on an ACTIVE signal: stop snaps to entry (BE armed)', () {
    final o = ChartOverlay.fromSignal(_sig(mfe: 1.5));
    expect(o.beArmed, isTrue);
    expect(o.stop, 0.10); // entry
  });

  test('closed signal never arms BE regardless of MFE', () {
    final o = ChartOverlay.fromSignal(_sig(status: 'SL_HIT', mfe: 3.0));
    expect(o.beArmed, isFalse);
    expect(o.stop, 0.09);
  });

  test('zero TP levels serialise as null (no phantom line)', () {
    final o = ChartOverlay.fromSignal(_sig(tp2: 0.0, tp3: 0.0));
    final j = o.toJson();
    expect(j['tp1'], 0.11);
    expect(j['tp2'], isNull);
    expect(j['tp3'], isNull);
  });

  group('lifecycle markers are anchored, not computed', () {
    test('the entry marker sits on the creation stamp, not now - minutesAgo', () {
      final o = ChartOverlay.fromSignal(_cotiAsOwnerSawIt());
      final j = o.toJson();
      expect(
        j['opened_at_ms'],
        DateTime.utc(2026, 7, 29, 3, 0, 33).millisecondsSinceEpoch,
        reason: 'the entry is where the engine stamped it',
      );

      final entry = (j['markers'] as List)
          .firstWhere((m) => (m as Map)['kind'] == 'entry') as Map;
      expect(
        entry['time'],
        DateTime.utc(2026, 7, 29, 3, 0, 33).millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('the entry marker is not at the exit', () {
      // The regression itself. Against the old `now - minutesAgo` code the
      // entry marker landed within a minute or two of the exit; it must now be
      // 65 minutes clear of it.
      final o = ChartOverlay.fromSignal(_cotiAsOwnerSawIt());
      final gap = o.closedAtSec! - o.openedAtSec!;
      expect(gap, greaterThan(60 * 60));
    });

    test('a closed signal gets an exit marker at its terminal stamp', () {
      final j = ChartOverlay.fromSignal(_cotiAsOwnerSawIt()).toJson();
      final markers = j['markers'] as List;
      expect(markers.length, 2);
      final exit = markers.firstWhere((m) => (m as Map)['kind'] == 'sl') as Map;
      expect(
        exit['time'],
        DateTime.utc(2026, 7, 29, 4, 5, 0).millisecondsSinceEpoch ~/ 1000,
      );
      expect(exit['text'], 'EXIT');
    });

    test('entry and exit arrows point opposite ways', () {
      // A marker inheriting the signal's side draws both ends identically.
      final markers =
          ChartOverlay.fromSignal(_cotiAsOwnerSawIt()).toJson()['markers']
              as List;
      final entry = markers.firstWhere((m) => (m as Map)['kind'] == 'entry') as Map;
      final exit = markers.firstWhere((m) => (m as Map)['kind'] == 'sl') as Map;
      expect(entry['shape'], 'arrowDown'); // SHORT entry
      expect(exit['shape'], 'arrowUp');
      expect(entry['position'], 'aboveBar');
      expect(exit['position'], 'belowBar');
    });

    test('a profitable exit is tagged tp, not sl', () {
      final o = ChartOverlay.fromSignal(_sig(
        status: 'PROFIT_LOCKED',
        isOpen: false,
        openedAt: DateTime.utc(2026, 7, 28, 22, 24),
        closedAt: DateTime.utc(2026, 7, 28, 23, 10),
      ));
      final exit = (o.toJson()['markers'] as List)
          .firstWhere((m) => (m as Map)['kind'] != 'entry') as Map;
      expect(exit['kind'], 'tp');
    });

    test('an open signal gets no exit marker', () {
      final o = ChartOverlay.fromSignal(_sig(
        status: 'ACTIVE',
        isOpen: true,
        openedAt: DateTime.utc(2026, 7, 29, 6, 20, 21),
      ));
      expect(o.closedAtSec, isNull);
      expect(o.toJson()['closed_at_ms'], isNull);
      expect((o.toJson()['markers'] as List).length, 1);
    });

    test('a terminal status with no stamp still gets no exit marker', () {
      // Older record from before the engine published the instant. "We don't
      // know when" must not become "it closed just now".
      final o = ChartOverlay.fromSignal(_sig(
        status: 'SL_HIT',
        isOpen: false,
        openedAt: DateTime.utc(2026, 7, 29, 3, 0, 33),
        closedAt: null,
      ));
      expect(o.closedAtSec, isNull);
      expect((o.toJson()['markers'] as List).length, 1);
    });

    test('an unstamped signal draws no marker at all rather than one at zero',
        () {
      // Epoch 0 is a real x-coordinate: a 0 here plants the overlay in 1970.
      final o = ChartOverlay.fromSignal(_sig(openedAt: null, closedAt: null));
      expect(o.openedAtSec, isNull);
      expect(o.toJson()['opened_at_ms'], isNull);
      expect((o.toJson()['markers'] as List), isEmpty);
    });

    test('marker placement ignores the passed-in now entirely', () {
      // `now` used to move the marker; nothing about the anchor may depend on
      // when the chart happened to be opened.
      final sig = _cotiAsOwnerSawIt();
      final early = ChartOverlay.fromSignal(sig, now: DateTime.utc(2026, 7, 29, 5));
      final late = ChartOverlay.fromSignal(sig, now: DateTime.utc(2026, 7, 30, 18));
      expect(early.openedAtSec, late.openedAtSec);
      expect(early.closedAtSec, late.closedAtSec);
    });
  });
}

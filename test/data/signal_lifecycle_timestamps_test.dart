/// Lifecycle instants on a signal (2026-07-29).
///
/// What we pin:
///
/// * `parseUtcTimestamp` reads a zone-less engine stamp as **UTC**, not
///   device-local. Getting this wrong is a silent 5h30m error on an IST phone
///   on the field a chart marker's x-coordinate is decided from.
/// * `MockSignal.openedAt` / `closedAt` round-trip through the SWR cache, so a
///   restored snapshot still knows when its signals opened and closed.
/// * The engine's `timestamp` / `terminal_outcome_timestamp` are the field
///   names this app depends on — a cross-repo contract, pinned on both sides
///   (engine `TestLifecycleInstantsArePublished`).
///
/// The chart drew its ENTRY arrow at the exit of every closed signal because
/// none of this existed: with no instant to read, it reconstructed one from
/// `minutes_ago`, which measures from the terminal event.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/mock_data.dart';
import 'package:lumin/data/timestamps.dart';

void main() {
  group('parseUtcTimestamp', () {
    test('reads an explicit-Z stamp as UTC', () {
      final t = parseUtcTimestamp('2026-07-29T03:00:33.820031Z');
      expect(t, isNotNull);
      expect(t!.isUtc, isTrue);
      expect(t.hour, 3);
      expect(t.minute, 0);
      expect(t.second, 33);
    });

    test('reads a zone-less stamp as UTC, not device-local', () {
      // The trap. DateTime.parse binds a zone-less string to the device zone,
      // so on an IST phone this would land 5h30m away — on the exact field a
      // chart marker is drawn from.
      final t = parseUtcTimestamp('2026-07-29T03:00:33');
      expect(t, isNotNull);
      expect(t!.isUtc, isTrue);
      expect(t, DateTime.utc(2026, 7, 29, 3, 0, 33));
    });

    test('applies a non-UTC offset rather than dropping it', () {
      expect(parseUtcTimestamp('2026-07-29T08:30:33+05:30'),
          DateTime.utc(2026, 7, 29, 3, 0, 33));
    });

    test('refuses rather than guessing', () {
      // Null, never a fallback: the caller omits its marker instead of
      // drawing one at a fabricated time.
      expect(parseUtcTimestamp(null), isNull);
      expect(parseUtcTimestamp(''), isNull);
      expect(parseUtcTimestamp('   '), isNull);
      expect(parseUtcTimestamp('not-a-date'), isNull);
      expect(parseUtcTimestamp(12345), isNull);
    });

    test('passes a DateTime through as UTC', () {
      final t = parseUtcTimestamp(DateTime.utc(2026, 7, 29, 4, 5));
      expect(t, DateTime.utc(2026, 7, 29, 4, 5));
    });
  });

  group('MockSignal lifecycle stamps', () {
    MockSignal sig({DateTime? openedAt, DateTime? closedAt}) => MockSignal(
          id: 'MVRTP-015FA037',
          symbol: 'COTIUSDT',
          direction: 'SHORT',
          setupName: 'MOVER TREND PULLBACK',
          agentName: 'The Momentum Rider',
          entry: 0.0105112,
          sl: 0.01083078,
          tp1: 0.01003183,
          tp2: 0.0,
          tp3: 0.0,
          confidence: 74,
          tier: 'B',
          status: 'SL_HIT',
          pnlPct: -3.04,
          minutesAgo: 3,
          isOpen: false,
          openedAt: openedAt,
          closedAt: closedAt,
        );

    test('round-trip through the SWR cache keeps both instants', () {
      final s = sig(
        openedAt: DateTime.utc(2026, 7, 29, 3, 0, 33),
        closedAt: DateTime.utc(2026, 7, 29, 4, 5),
      );
      final back = MockSignal.fromMap(s.toMap());
      expect(back.openedAt, DateTime.utc(2026, 7, 29, 3, 0, 33));
      expect(back.closedAt, DateTime.utc(2026, 7, 29, 4, 5));
    });

    test('absent instants round-trip as absent, not as epoch', () {
      final back = MockSignal.fromMap(sig().toMap());
      expect(back.openedAt, isNull);
      expect(back.closedAt, isNull);
    });

    test('minutesAgo is not the age of a closed signal', () {
      // Stated once, here, because every downstream bug came from assuming it
      // was: this record opened at 03:00:33 and its caption says "3m ago".
      final s = sig(
        openedAt: DateTime.utc(2026, 7, 29, 3, 0, 33),
        closedAt: DateTime.utc(2026, 7, 29, 4, 5),
      );
      final ageAtCapture =
          DateTime.utc(2026, 7, 29, 4, 8).difference(s.openedAt!).inMinutes;
      expect(s.minutesAgo, 3);
      expect(ageAtCapture, 67);
    });
  });
}

/// Open/closed truth on signals (2026-07-10).
///
/// What we pin:
///
/// * ``effectiveIsOpen`` prefers the engine's ``is_open`` field — a runner
///   mover at status TP1_HIT with ``is_open: true`` renders OPEN, while a
///   BE-then-TP1 close (same status, ``is_open: false``) renders closed.
///   This is the owner-reported EIGENUSDT ("closed but shows open 8h") /
///   MVLLUSDT ("open runner reads closed at TP1") fix.
/// * Payloads that predate the field (isOpen == null) fall back to the
///   legacy terminal-status heuristic, so cached data keeps rendering.
/// * toMap/fromMap round-trips the field (SWR cache persistence).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/mock_data.dart';

MockSignal _sig({required String status, bool? isOpen}) => MockSignal(
      id: 'SIG-1',
      symbol: 'MVLLUSDT',
      direction: 'LONG',
      setupName: 'MOVER TREND PULLBACK',
      agentName: 'The Momentum Rider',
      entry: 36.49,
      sl: 38.0697,
      tp1: 37.5138,
      tp2: 38.3013,
      tp3: 39.09,
      confidence: 70.5,
      tier: 'B',
      status: status,
      pnlPct: 4.63,
      minutesAgo: 60,
      isOpen: isOpen,
    );

void main() {
  group('MockSignal.effectiveIsOpen', () {
    test('engine is_open=true wins over a TP1_HIT status (open runner)', () {
      expect(_sig(status: 'TP1_HIT', isOpen: true).effectiveIsOpen, isTrue);
    });

    test('engine is_open=false wins over an ACTIVE-looking status', () {
      expect(_sig(status: 'TP1_HIT', isOpen: false).effectiveIsOpen, isFalse);
    });

    test('null falls back to terminal-status heuristic', () {
      expect(_sig(status: 'TP1_HIT', isOpen: null).effectiveIsOpen, isFalse);
      expect(_sig(status: 'SL_HIT', isOpen: null).effectiveIsOpen, isFalse);
      expect(_sig(status: 'ACTIVE', isOpen: null).effectiveIsOpen, isTrue);
    });

    test('toMap/fromMap round-trips isOpen', () {
      for (final v in [true, false, null]) {
        final round = MockSignal.fromMap(_sig(status: 'TP1_HIT', isOpen: v).toMap());
        expect(round.isOpen, v);
      }
    });
  });
}

/// ChartOverlay derivation from a Lumin signal — the entry/SL/TP/BE payload
/// the chart bridge draws. Asserts the BE-armed inference (stop snaps to entry
/// once MFE ≥ +1%) and the null-TP handling.
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
}) {
  return MockSignal(
    id: 'MVRTP-1',
    symbol: 'GUAUSDT',
    direction: 'LONG',
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
    maxFavorableExcursionPct: mfe,
  );
}

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

  test('opened time precedes now and a marker is emitted', () {
    final now = DateTime.utc(2026, 6, 29, 12, 0, 0);
    final o = ChartOverlay.fromSignal(_sig(minutesAgo: 30), now: now);
    final j = o.toJson();
    expect(j['opened_at_ms'], DateTime.utc(2026, 6, 29, 11, 30, 0).millisecondsSinceEpoch);
    expect((j['markers'] as List).first['kind'], 'entry');
  });
}

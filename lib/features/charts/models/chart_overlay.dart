/// Lumin signal overlay for the chart — the entry / SL / TP / BE levels and
/// lifecycle markers drawn on top of the candles when a chart is opened from a
/// signal. Built entirely from the [MockSignal] the app already holds; no new
/// engine call. Serialises to the shape the WebView bridge's `setOverlay`
/// expects (see docs/market_charts_tab.md §8–§9).
library;

import '../../../data/mock_data.dart';

/// MFE (%) at which the engine's break-even shift arms — mirrors
/// `BE_SHIFT_TRIGGER_PCT` / `BE_THEN_TP1_DEFAULT_ENABLED` on the engine. Once a
/// live signal has run this far in profit, its effective stop is at entry.
const double kBeArmPct = 1.0;

class ChartOverlay {
  const ChartOverlay({
    required this.signalId,
    required this.side,
    required this.entry,
    required this.stop,
    required this.beArmed,
    required this.openedAtSec,
    required this.status,
    this.tp1,
    this.tp2,
    this.tp3,
  });

  final String signalId;
  final String side; // LONG / SHORT
  final double entry;

  /// Effective stop shown on the chart: entry once BE has armed, else the
  /// signal's original SL.
  final double stop;
  final bool beArmed;
  final int openedAtSec; // seconds since epoch (chart x-axis unit)
  final String status;
  final double? tp1;
  final double? tp2;
  final double? tp3;

  static const _active = 'ACTIVE';

  factory ChartOverlay.fromSignal(MockSignal s, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final openedSec =
        n.subtract(Duration(minutes: s.minutesAgo)).millisecondsSinceEpoch ~/ 1000;
    final beArmed = s.status == _active && s.maxFavorableExcursionPct >= kBeArmPct;
    return ChartOverlay(
      signalId: s.id,
      side: s.direction,
      entry: s.entry,
      stop: beArmed && s.entry > 0 ? s.entry : s.sl,
      beArmed: beArmed,
      openedAtSec: openedSec,
      status: s.status,
      tp1: s.tp1 > 0 ? s.tp1 : null,
      tp2: s.tp2 > 0 ? s.tp2 : null,
      tp3: s.tp3 > 0 ? s.tp3 : null,
    );
  }

  /// Lifecycle markers: an entry marker always; an exit marker tagged by the
  /// terminal status when the signal has closed. (Exit time is unknown to the
  /// app precisely, so terminal markers are omitted in v1 — entry only.)
  List<Map<String, dynamic>> _markers() {
    return [
      {'time': openedAtSec, 'kind': 'entry'},
    ];
  }

  Map<String, dynamic> toJson() => {
        'signal_id': signalId,
        'side': side,
        'entry': entry,
        'sl': stop,
        'be_armed': beArmed,
        'tp1': tp1,
        'tp2': tp2,
        'tp3': tp3,
        'opened_at_ms': openedAtSec * 1000,
        'status': status,
        'markers': _markers(),
      };
}

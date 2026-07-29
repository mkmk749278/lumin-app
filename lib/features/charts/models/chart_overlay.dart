/// Lumin signal overlay for the chart — the entry / SL / TP / BE levels and
/// lifecycle markers drawn on top of the candles when a chart is opened from a
/// signal. Built entirely from the [MockSignal] the app already holds; no new
/// engine call. Serialises to the shape the WebView bridge's `setOverlay`
/// expects (see docs/market_charts_tab.md §8–§9).
///
/// **Markers are anchored on the engine's own stamps, never on arithmetic**
/// (2026-07-29). This model used to reconstruct the entry as
/// `DateTime.now() - minutesAgo`. But `minutes_ago` is recency of the signal's
/// *last* event, so on every closed signal it measures from the terminal one —
/// and the arrow captioned ENTRY was drawn at the **exit**, offset by the whole
/// hold time. The owner caught it by comparing the ops CSV against the app:
/// COTIUSDT stamped 03:00:33 UTC rendered at 04:05, sitting exactly on its own
/// SL line; seven signals sampled, offsets of 2–65 minutes, all positive.
///
/// Three separate errors rode on that one expression, which is why nothing
/// about it is kept: the *wrong anchor event* for closed signals; integer
/// minutes (up to 60s of quantisation); and `now` being chart-open time while
/// `minutesAgo` was computed when the SWR-cached list was fetched, so the
/// marker drifted later by the cache age even on open signals.
///
/// [MockSignal.openedAt] / [MockSignal.closedAt] come straight from the engine
/// (`timestamp` / `terminal_outcome_timestamp`, engine #829). When a stamp is
/// absent the marker is **omitted** — a chart that cannot say when something
/// happened must not draw it somewhere plausible.
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
    this.closedAtSec,
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

  /// Entry instant, seconds since epoch (the chart x-axis unit). `null` when
  /// the engine sent no creation stamp — draw no entry marker rather than one
  /// at a computed time.
  final int? openedAtSec;

  /// Exit instant, same unit. `null` while the signal is open, and on closed
  /// records that predate the engine's terminal stamp. Both mean "no exit
  /// marker"; neither means "exit now".
  final int? closedAtSec;
  final String status;
  final double? tp1;
  final double? tp2;
  final double? tp3;

  static const _active = 'ACTIVE';

  /// [now] is retained for callers that pin time in tests; it no longer
  /// participates in marker placement, which reads the engine's stamps only.
  factory ChartOverlay.fromSignal(MockSignal s, {DateTime? now}) {
    final beArmed = s.status == _active && s.maxFavorableExcursionPct >= kBeArmPct;
    // An exit marker only for a signal the engine says has actually closed.
    // A terminal-looking status with no stamp (older record) gets no marker —
    // "we don't know when" and "it hasn't happened" both refuse here.
    final closedAt = s.effectiveIsOpen ? null : s.closedAt;
    return ChartOverlay(
      signalId: s.id,
      side: s.direction,
      entry: s.entry,
      stop: beArmed && s.entry > 0 ? s.entry : s.sl,
      beArmed: beArmed,
      openedAtSec: _epochSec(s.openedAt),
      closedAtSec: _epochSec(closedAt),
      status: s.status,
      tp1: s.tp1 > 0 ? s.tp1 : null,
      tp2: s.tp2 > 0 ? s.tp2 : null,
      tp3: s.tp3 > 0 ? s.tp3 : null,
    );
  }

  static int? _epochSec(DateTime? t) =>
      t == null ? null : t.toUtc().millisecondsSinceEpoch ~/ 1000;

  /// Terminal statuses that closed at a loss — the exit marker is coloured and
  /// captioned from the outcome, so a glance says which end of the trade it is.
  static const Set<String> _lossStatuses = {
    'SL_HIT', 'INVALIDATED', 'EXPIRED', 'CANCELLED',
  };

  /// Lifecycle markers: entry, plus an exit once the engine has stamped one.
  ///
  /// Each marker carries its own arrow direction rather than inheriting the
  /// signal's side — an exit points the opposite way to the entry, and a
  /// marker that inherits `side` would draw both ends identically.
  ///
  /// A marker with no stamp is omitted, not placed. That is the entire point
  /// of this change: an arrow on a chart is an assertion about *when*, and the
  /// app has no honest way to make one from a signal it has no time for.
  List<Map<String, dynamic>> _markers() {
    final up = side == 'LONG';
    final out = <Map<String, dynamic>>[];
    final o = openedAtSec;
    if (o != null) {
      out.add({
        'time': o,
        'kind': 'entry',
        'text': 'ENTRY',
        'position': up ? 'belowBar' : 'aboveBar',
        'shape': up ? 'arrowUp' : 'arrowDown',
      });
    }
    final c = closedAtSec;
    if (c != null) {
      final loss = _lossStatuses.contains(status);
      out.add({
        'time': c,
        // Drives the marker colour in the WebView: red for a loss exit, green
        // otherwise. The caption stays short — the status is already spelled
        // out in the sheet above the chart.
        'kind': loss ? 'sl' : 'tp',
        'text': 'EXIT',
        // Mirrored: the exit closes the position the entry opened.
        'position': up ? 'aboveBar' : 'belowBar',
        'shape': up ? 'arrowDown' : 'arrowUp',
      });
    }
    return out;
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
        // Null rather than 0 when unstamped: epoch 0 is a real x-coordinate and
        // would place the overlay in 1970 instead of reading as "unknown".
        'opened_at_ms': openedAtSec == null ? null : openedAtSec! * 1000,
        'closed_at_ms': closedAtSec == null ? null : closedAtSec! * 1000,
        'status': status,
        'markers': _markers(),
      };
}

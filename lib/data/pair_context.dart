/// The engine's read of one pair, for the chart screen (Charts redesign part 3,
/// engine `GET /api/pairs/{symbol}/context`, 360-v2 #1068).
///
/// Everything here is a DESCRIPTION of the chart the engine measured — its
/// support/resistance levels, the week's value area, the 4h structure leg —
/// and Lumin's own closed signals on the pair. There is no score and no
/// verdict in the payload, and this model invents none.
///
/// Parsing is tolerant: a field an older engine does not send is null, and
/// the screen renders "—" or leaves the section out rather than guessing.
library;

enum PairContextState {
  /// The engine holds a read for this pair.
  covered,

  /// A pair the scanner does not scan — the engine fetches nothing for it.
  notTracked,

  /// No published block (engine predating the endpoint, or the key expired).
  notReported,
}

class PairLevel {
  const PairLevel({
    required this.price,
    required this.distPct,
    required this.touches,
    required this.timeframes,
    required this.roundNumber,
  });

  final double price;

  /// Signed distance from the read price, in % (negative = below).
  final double distPct;
  final int touches;
  final List<String> timeframes;
  final bool roundNumber;

  static PairLevel? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = _num(j['price']);
    if (p == null || p <= 0) return null;
    return PairLevel(
      price: p,
      distPct: _num(j['dist_pct']) ?? 0,
      touches: (_num(j['touches']) ?? 1).round(),
      timeframes: [for (final t in (j['timeframes'] as List? ?? const [])) t.toString()],
      roundNumber: j['round_number'] == true,
    );
  }
}

class PairValueArea {
  const PairValueArea({required this.poc, required this.vah, required this.val, required this.position});
  final double poc;
  final double vah;
  final double val;

  /// `above_value` / `in_value` / `below_value`.
  final String position;

  static PairValueArea? fromJson(Object? j) {
    if (j is! Map) return null;
    final poc = _num(j['poc']), vah = _num(j['vah']), val = _num(j['val']);
    if (poc == null || vah == null || val == null) return null;
    return PairValueArea(poc: poc, vah: vah, val: val, position: (j['position'] ?? '').toString());
  }
}

class PairStructure {
  const PairStructure({required this.state, this.lastHH, this.lastHL, this.lastLH, this.lastLL});

  /// `BULL_LEG` / `BEAR_LEG` / `RANGE`.
  final String state;
  final double? lastHH, lastHL, lastLH, lastLL;

  static PairStructure? fromJson(Object? j) {
    if (j is! Map || j['state'] == null) return null;
    return PairStructure(
      state: j['state'].toString(),
      lastHH: _num(j['last_hh']),
      lastHL: _num(j['last_hl']),
      lastLH: _num(j['last_lh']),
      lastLL: _num(j['last_ll']),
    );
  }

  /// Plain words for the leg — what the pivots did, not what they will do.
  String get words => switch (state) {
        'BULL_LEG' => 'Higher highs and higher lows',
        'BEAR_LEG' => 'Lower highs and lower lows',
        'RANGE' => 'Ranging — no clear leg',
        _ => state,
      };
}

class PastSignal {
  const PastSignal({
    required this.direction,
    required this.entry,
    required this.outcome,
    required this.pnlPct,
    required this.openedAt,
    required this.closedAt,
  });

  final String direction;
  final double? entry;
  final String outcome;
  final double? pnlPct;
  final DateTime? openedAt;
  final DateTime? closedAt;

  bool get isLong => direction.toUpperCase() == 'LONG';

  /// A win is a positive closed PnL; a flat or unknown result is neither.
  bool? get won {
    final p = pnlPct;
    if (p == null) return null;
    if (p.abs() < 0.005) return null;
    return p > 0;
  }

  static PastSignal? fromJson(Object? j) {
    if (j is! Map) return null;
    DateTime? ts(Object? v) {
      final n = _num(v);
      return n == null || n <= 0 ? null : DateTime.fromMillisecondsSinceEpoch((n * 1000).round(), isUtc: true);
    }

    return PastSignal(
      direction: (j['direction'] ?? '').toString(),
      entry: _num(j['entry']),
      outcome: (j['outcome'] ?? '').toString(),
      pnlPct: _num(j['pnl_pct']),
      openedAt: ts(j['opened_at_ts']),
      closedAt: ts(j['closed_at_ts']),
    );
  }
}

class PairChecklist {
  const PairChecklist({required this.long, required this.short, required this.neutral});
  final List<String> long;
  final List<String> short;
  final List<String> neutral;

  static PairChecklist? fromJson(Object? j) {
    if (j is! Map) return null;
    List<String> l(Object? v) => [for (final x in (v as List? ?? const [])) x.toString()];
    return PairChecklist(long: l(j['long']), short: l(j['short']), neutral: l(j['neutral']));
  }
}

class PairContext {
  const PairContext({
    required this.symbol,
    required this.state,
    this.price,
    this.readAt,
    this.supports = const [],
    this.resistances = const [],
    this.valueArea,
    this.structure4h,
    this.checklist,
    this.checklistLocked = false,
    this.pastSignals = const [],
  });

  final String symbol;
  final PairContextState state;
  final double? price;
  final DateTime? readAt;
  final List<PairLevel> supports;
  final List<PairLevel> resistances;
  final PairValueArea? valueArea;
  final PairStructure? structure4h;

  /// Null when locked (no live access) or not covered.
  final PairChecklist? checklist;
  final bool checklistLocked;
  final List<PastSignal> pastSignals;

  factory PairContext.fromJson(Map<String, dynamic> j) {
    final state = switch (j['state']) {
      'covered' => PairContextState.covered,
      'not_tracked' => PairContextState.notTracked,
      _ => PairContextState.notReported,
    };
    final ctx = j['context'];
    List<PairLevel> levels(Object? v) => [
          for (final x in (v as List? ?? const []))
            if (PairLevel.fromJson(x) case final l?) l,
        ];
    final readAt = ctx is Map ? _num(ctx['read_at']) : null;
    return PairContext(
      symbol: (j['symbol'] ?? '').toString(),
      state: state == PairContextState.covered && ctx is! Map ? PairContextState.notReported : state,
      price: ctx is Map ? _num(ctx['price']) : null,
      readAt: readAt == null ? null : DateTime.fromMillisecondsSinceEpoch((readAt * 1000).round(), isUtc: true),
      supports: ctx is Map ? levels(ctx['supports']) : const [],
      resistances: ctx is Map ? levels(ctx['resistances']) : const [],
      valueArea: ctx is Map ? PairValueArea.fromJson(ctx['volume_profile']) : null,
      structure4h: ctx is Map ? PairStructure.fromJson(ctx['structure_4h']) : null,
      checklist: PairChecklist.fromJson(j['checklist']),
      checklistLocked: j['checklist_locked'] == true,
      pastSignals: [
        for (final x in (j['past_signals'] as List? ?? const []))
          if (PastSignal.fromJson(x) case final p?) p,
      ],
    );
  }
}

double? _num(Object? v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v);
  return null;
}

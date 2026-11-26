/// The Desk — what `GET /api/desk` returns (engine `src/desk.py`,
/// Lumin 2.0, 2026-11-26).
///
/// The hourly AI analyst submits a plan (bias, notes, setups); the engine
/// walks each setup forward on real prices and publishes the result. Every
/// field here is the engine's: the app derives no outcome, no freshness and
/// no label of its own.
///
/// Parsing is defensive by design — a field an older engine omits becomes
/// null or empty, never a crash, and never a value the engine did not send.
/// Unknown stays unknown: an unreadable market context is `readable: false`,
/// never zeros; a missing plan is `freshness: none`, never "stand aside".
library;

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;
String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;
Map<String, dynamic> _m(Object? v) =>
    v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<Map<String, dynamic>> _l(Object? v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : const [];
DateTime? _ts(Object? v) => v is num
    ? DateTime.fromMillisecondsSinceEpoch((v * 1000).round(), isUtc: true)
    : null;

/// `ok` / `not_reported` / `disabled`, plus `not_in_window` for one setup.
/// Anything else is kept verbatim so a new state is visible, not hidden.
class DeskResponse {
  const DeskResponse({required this.state, this.desk});

  final String state;
  final Desk? desk;

  bool get isOk => state == 'ok' && desk != null;

  factory DeskResponse.fromJson(Map<String, dynamic> j) => DeskResponse(
        state: _s(j['state']) ?? 'not_reported',
        desk: j['desk'] is Map ? Desk.fromJson(_m(j['desk'])) : null,
      );
}

class Desk {
  const Desk({
    required this.generatedAt,
    required this.ledger,
    required this.brief,
    required this.plans,
    required this.setups,
    required this.record,
    required this.labels,
  });

  final DateTime? generatedAt;

  /// `ok`, or why the analyst ledger could not be read.
  final String ledger;
  final DeskBrief brief;
  final List<DeskPlan> plans;
  final List<DeskSetup> setups;
  final DeskRecord record;
  final DeskLabels labels;

  factory Desk.fromJson(Map<String, dynamic> j) {
    final labels = DeskLabels.fromJson(_m(j['labels']));
    return Desk(
      generatedAt: _ts(j['generated_at']),
      ledger: _s(j['ledger']) ?? 'unknown',
      brief: DeskBrief.fromJson(_m(j['brief'])),
      plans: _l(j['plans']).map(DeskPlan.fromJson).toList(),
      setups: _l(j['setups']).map(DeskSetup.fromJson).toList(),
      record: DeskRecord.fromJson(_m(j['record'])),
      labels: labels,
    );
  }
}

/// `current` (≤ 2h old), `stale`, or `none` — the engine decides which.
enum BriefFreshness { current, stale, none }

class DeskBrief {
  const DeskBrief({
    required this.plan,
    required this.freshness,
    required this.ageSec,
    required this.market,
  });

  final DeskPlan? plan;
  final BriefFreshness freshness;
  final double? ageSec;
  final DeskMarket market;

  factory DeskBrief.fromJson(Map<String, dynamic> j) {
    final f = _m(j['freshness']);
    final state = switch (_s(f['state'])) {
      'current' => BriefFreshness.current,
      'stale' => BriefFreshness.stale,
      _ => BriefFreshness.none,
    };
    return DeskBrief(
      plan: j['plan'] is Map ? DeskPlan.fromJson(_m(j['plan'])) : null,
      freshness: state,
      ageSec: _d(f['age_sec']),
      market: DeskMarket.fromJson(_m(j['market'])),
    );
  }
}

class DeskPlan {
  const DeskPlan({
    required this.planId,
    required this.submittedAt,
    required this.bias,
    required this.notes,
    required this.nSetups,
    required this.nAccepted,
    required this.accepted,
  });

  final String planId;
  final DateTime? submittedAt;

  /// `risk_on` / `risk_off` / `neutral` / `stand_aside`, or null if absent.
  final String? bias;
  final String notes;
  final int nSetups;
  final int nAccepted;

  /// What this plan put on the book: symbol, side, archetype.
  final List<({String symbol, String side, String? archetype})> accepted;

  bool get stoodAside => nAccepted == 0;

  factory DeskPlan.fromJson(Map<String, dynamic> j) => DeskPlan(
        planId: _s(j['plan_id']) ?? '',
        submittedAt: _ts(j['submitted_at']),
        bias: _s(j['bias']),
        notes: (j['notes'] as String?) ?? '',
        nSetups: _i(j['n_setups']) ?? 0,
        nAccepted: _i(j['n_accepted']) ?? 0,
        accepted: _l(j['accepted'])
            .map((a) => (
                  symbol: _s(a['symbol']) ?? '?',
                  side: _s(a['side']) ?? '?',
                  archetype: _s(a['archetype']),
                ))
            .toList(),
      );
}

class DeskMarket {
  const DeskMarket({
    required this.readable,
    this.reason,
    this.btcPrice,
    this.btcState,
    this.btcChange24hPct,
    this.btcChange7dPct,
    this.breadthReadable = false,
    this.shareBeatingBtc7d,
    this.breadthN,
  });

  /// False when the engine could not read BTC context — render "unavailable",
  /// never a zero price.
  final bool readable;
  final String? reason;
  final double? btcPrice;

  /// The engine's BTC state score, −1 (down) … +1 (up).
  final double? btcState;
  final double? btcChange24hPct;
  final double? btcChange7dPct;
  final bool breadthReadable;

  /// Share of the universe whose 7d return beats BTC's, 0…1.
  final double? shareBeatingBtc7d;
  final int? breadthN;

  factory DeskMarket.fromJson(Map<String, dynamic> j) {
    final ch = _m(j['btc_change_pct']);
    final br = _m(j['breadth']);
    return DeskMarket(
      readable: j['readable'] == true,
      reason: _s(j['reason']),
      btcPrice: _d(j['btc_price']),
      btcState: _d(j['btc_state']),
      btcChange24hPct: _d(ch['24h']),
      btcChange7dPct: _d(ch['7d']),
      breadthReadable: br['readable'] == true,
      shareBeatingBtc7d: _d(br['share_beating_btc_7d']),
      breadthN: _i(br['n']),
    );
  }
}

class DeskEntry {
  const DeskEntry(this.price, this.weight);
  final double price;
  final double weight;
}

/// The analyst arm's walk of one setup (a limit at the first entry).
class DeskArm {
  const DeskArm({
    this.status,
    this.unfilled = false,
    this.entry,
    this.entryAt,
    this.exit,
    this.exitAt,
    this.exitReason,
    this.netPct,
    this.mfePct,
    this.maePct,
  });

  final String? status;

  /// True when the limit never filled: [netPct] is then the MARKET's result,
  /// never this setup's fill.
  final bool unfilled;
  final double? entry;
  final DateTime? entryAt;
  final double? exit;
  final DateTime? exitAt;
  final String? exitReason;
  final double? netPct;
  final double? mfePct;
  final double? maePct;

  static DeskArm? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, dynamic>();
    return DeskArm(
      status: _s(j['status']),
      unfilled: j['unfilled'] == true || j['unfilled'] == 1,
      entry: _d(j['entry']),
      entryAt: _ts(j['entry_at']),
      exit: _d(j['exit']),
      exitAt: _ts(j['exit_at']),
      exitReason: _s(j['exit_reason']),
      netPct: _d(j['net_pct']),
      mfePct: _d(j['mfe_pct']),
      maePct: _d(j['mae_pct']),
    );
  }
}

class DeskSetup {
  const DeskSetup({
    required this.setupId,
    required this.symbol,
    required this.side,
    required this.archetype,
    required this.state,
    required this.submittedAt,
    required this.expiresAt,
    required this.entries,
    required this.stop,
    required this.targets,
    this.rrTp1,
    this.scenario,
    this.invalidation,
    this.pTarget,
    this.priceAtSubmit,
    this.analyst,
  });

  final String setupId;
  final String symbol;
  final String side;
  final String? archetype;

  /// One of the engine's feed states (`pending`, `active`, `tp_hit`, …).
  final String state;
  final DateTime? submittedAt;
  final DateTime? expiresAt;
  final List<DeskEntry> entries;
  final double? stop;
  final List<double> targets;
  final double? rrTp1;
  final String? scenario;
  final String? invalidation;

  /// The ANALYST's own estimate of reaching the first target. Its stated
  /// probabilities are not yet calibrated; render it as its estimate.
  final double? pTarget;
  final double? priceAtSubmit;
  final DeskArm? analyst;

  bool get isLong => side == 'long';
  bool get isOpen =>
      const {'not_walked', 'waiting_data', 'pending', 'active'}.contains(state);

  factory DeskSetup.fromJson(Map<String, dynamic> j) => DeskSetup(
        setupId: _s(j['setup_id']) ?? '',
        symbol: _s(j['symbol']) ?? '?',
        side: _s(j['side']) ?? '?',
        archetype: _s(j['archetype']),
        state: _s(j['state']) ?? 'insufficient',
        submittedAt: _ts(j['submitted_at']),
        expiresAt: _ts(j['expires_at']),
        entries: _l(j['entries'])
            .where((e) => _d(e['price']) != null)
            .map((e) => DeskEntry(_d(e['price'])!, _d(e['weight']) ?? 0))
            .toList(),
        stop: _d(j['stop']),
        targets: (j['targets'] is List)
            ? (j['targets'] as List).map(_d).whereType<double>().toList()
            : const [],
        rrTp1: _d(j['rr_tp1']),
        scenario: _s(j['scenario']),
        invalidation: _s(j['invalidation']),
        pTarget: _d(j['p_target']),
        priceAtSubmit: _d(j['price_at_submit']),
        analyst: DeskArm.fromJson(j['analyst']),
      );
}

/// The analyst's forward-measured record. NOT fills: `basisNote` says so and
/// the UI must show it wherever these numbers appear.
class DeskRecord {
  const DeskRecord({
    required this.readable,
    this.basisNote,
    this.n = 0,
    this.winRate,
    this.avgNetPct,
    this.fillRate,
    this.filledByExit = const {},
    this.calibrationN = 0,
    this.statedPTarget,
    this.hitRate,
  });

  final bool readable;
  final String? basisNote;
  final int n;
  final double? winRate;
  final double? avgNetPct;
  final double? fillRate;

  /// Filled setups by how they ended: `target` / `stop` / `horizon`, each
  /// with its count and share.
  final Map<String, ({int n, double share})> filledByExit;
  final int calibrationN;

  /// Mean stated p(target) on filled setups, and how often they hit.
  final double? statedPTarget;
  final double? hitRate;

  factory DeskRecord.fromJson(Map<String, dynamic> j) {
    final a = _m(j['analyst']);
    final split = _m(j['split']);
    final cal = _m(j['calibration']);
    final byExit = <String, ({int n, double share})>{};
    _m(split['filled_by_exit']).forEach((k, v) {
      final m = _m(v);
      byExit[k] = (n: _i(m['n']) ?? 0, share: _d(m['share']) ?? 0);
    });
    return DeskRecord(
      readable: j['readable'] == true,
      basisNote: _s(j['basis_note']),
      n: _i(a['n']) ?? 0,
      winRate: _d(a['win_rate']),
      avgNetPct: _d(a['avg_net_pct']),
      fillRate: _d(split['fill_rate']),
      filledByExit: byExit,
      calibrationN: _i(cal['n']) ?? 0,
      statedPTarget: _d(cal['mean_p_target']),
      hitRate: _d(cal['hit_rate']),
    );
  }
}

/// The engine's display names. A key the engine did not label renders as
/// itself — a new archetype shows up under its own name instead of vanishing.
class DeskLabels {
  const DeskLabels({
    this.archetype = const {},
    this.bias = const {},
    this.state = const {},
  });

  final Map<String, String> archetype;
  final Map<String, String> bias;
  final Map<String, String> state;

  String archetypeOf(String? k) => k == null ? '—' : (archetype[k] ?? k);
  String biasOf(String? k) => k == null ? '—' : (bias[k] ?? k);
  String stateOf(String k) => state[k] ?? k;

  factory DeskLabels.fromJson(Map<String, dynamic> j) {
    Map<String, String> strs(Object? v) =>
        _m(v).map((k, v) => MapEntry(k, v is String ? v : '$v'));
    return DeskLabels(
      archetype: strs(j['archetype']),
      bias: strs(j['bias']),
      state: strs(j['state']),
    );
  }
}

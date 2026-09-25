/// Live-signal access, as the engine reports it on every `/api/signals`
/// read (owner, 2026-09-25 — engine `src/api/signal_access.py`).
///
/// Closed signals are free to everyone.  ACTIVE signals need an account plus
/// the Signals plan (or Assist / Auto), after 3 free days from sign-up; a
/// guest never sees them.  The engine enforces all of it — `/api/signals`
/// simply leaves the live ones out — and this model only lets the feed say
/// *why* the list has no live signals and how many it is not showing.
///
/// The engine is the source of truth: nothing here is derived locally, and
/// an engine that predates the paywall sends none of these keys, which
/// parses to null (no banner) rather than to "locked".
library;

/// A live signal the caller may not see yet, as the engine masks it: no
/// direction, no entry / stop / target ever reaches the app (engine
/// `LockedSignal`), so the blurred levels on the card are placeholders, not
/// the real numbers hidden under a filter.
class LockedSignal {
  const LockedSignal({
    required this.id,
    required this.symbol,
    required this.agentName,
    required this.qualityTier,
    required this.confidence,
    required this.minutesAgo,
  });

  final String id;
  final String symbol;
  final String agentName;
  final String qualityTier;
  final double confidence;
  final int minutesAgo;

  static LockedSignal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['signal_id'];
    final symbol = raw['symbol'];
    if (id is! String || symbol is! String) return null;
    return LockedSignal(
      id: id,
      symbol: symbol,
      agentName: (raw['agent_name'] as String?) ?? '',
      qualityTier: (raw['quality_tier'] as String?) ?? '',
      confidence: (raw['confidence'] as num?)?.toDouble() ?? 0,
      minutesAgo: (raw['minutes_ago'] as num?)?.toInt() ?? 0,
    );
  }
}

class LiveFeedAccess {
  const LiveFeedAccess({
    required this.locked,
    required this.lockedOpenCount,
    required this.reason,
    this.until,
    this.lockedItems = const [],
  });

  /// The withheld live signals, masked, newest first.
  final List<LockedSignal> lockedItems;

  /// True when the feed is closed-signals-only for this caller.
  final bool locked;

  /// Active signals the caller is not being shown right now.
  final int lockedOpenCount;

  /// Engine reason: guest · locked · free_window · plan · paywall_off ·
  /// misconfigured · owner.
  final String reason;

  /// End of the free days (`free_window`) or of the plan (`plan`).
  final DateTime? until;

  bool get isGuest => reason == 'guest';
  bool get isFreeWindow => reason == 'free_window';

  /// Whole days left in the free window, rounded up (0 when not in it).
  int daysLeft(DateTime now) {
    final u = until;
    if (!isFreeWindow || u == null) return 0;
    final hours = u.difference(now).inHours;
    if (hours <= 0) return 0;
    return (hours / 24).ceil();
  }

  /// Parse the `/api/signals` response.  Null when the engine did not
  /// report access (older engine).
  static LiveFeedAccess? fromSignalsJson(Map<String, dynamic> j) {
    final access = j['live_access'];
    if (access is! Map) return null;
    final untilRaw = access['until'];
    return LiveFeedAccess(
      locked: j['live_locked'] == true,
      lockedOpenCount: (j['locked_open_count'] as num?)?.toInt() ?? 0,
      reason: (access['reason'] as String?) ?? '',
      until: untilRaw is String ? DateTime.tryParse(untilRaw)?.toUtc() : null,
      lockedItems: [
        for (final raw in (j['locked_items'] as List? ?? const []))
          if (LockedSignal.fromJson(raw) case final s?) s,
      ],
    );
  }
}

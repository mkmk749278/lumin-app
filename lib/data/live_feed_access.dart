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

class LiveFeedAccess {
  const LiveFeedAccess({
    required this.locked,
    required this.lockedOpenCount,
    required this.reason,
    this.until,
  });

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
    );
  }
}

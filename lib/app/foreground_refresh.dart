/// Contract for tab pages that refresh their data when the app returns
/// to the foreground.
///
/// Why this exists: a trading app left in the background for minutes or
/// hours and then reopened must show *current* state, not a stale
/// snapshot from when it was last visible. The tab pages live inside an
/// [IndexedStack] (see `NavShell`), which keeps every visited tab mounted
/// — so a backgrounded-then-resumed tab never re-runs `didChangeDependencies`
/// and would otherwise display whatever it last fetched.
///
/// Why a single-tab contract (not "refresh everything on resume"): the
/// engine runs on a 1-vCPU VPS. Refreshing all five mounted tabs on every
/// foreground would fire a burst of multi-endpoint fetches (TradePage alone
/// fans out to five `/api/...` calls) — exactly the load spike the app's
/// lazy-mount + SWR design works to avoid. `NavShell` therefore calls
/// [refreshFromForeground] on **only the currently-visible tab**; hidden
/// tabs refresh when the user next navigates to them.
///
/// Implementers mirror their own pull-to-refresh path (invalidate the SWR
/// keys they consume, then resubscribe) but WITHOUT the `RefreshIndicator`
/// spinner — the refresh is silent. Because the page retains its last
/// rendered data across a resubscribe, the stale view stays on screen until
/// fresh data lands, so there is no skeleton flash on resume.
abstract class ForegroundRefreshable {
  /// Re-fetch this tab's data after an app foreground transition.
  ///
  /// Called by `NavShell` on the visible tab only. Implementations must be
  /// safe to call on a still-mounted `State` and should no-op (or guard on
  /// `mounted`) if the element has been disposed.
  void refreshFromForeground();
}

/// Throttle decision for foreground refresh: returns true when a resume
/// should trigger a refresh given when the last one ran.
///
/// Extracted as a pure function so the throttle is unit-testable without a
/// widget/`AppConfigScope` harness — lumin-app deliberately has no
/// scope-injection seam for widget tests (see `region_gate_test`), so the
/// logic worth testing lives here and `NavShell` just wires it to the
/// lifecycle callback.
bool shouldRefreshOnForeground({
  required DateTime? lastRefresh,
  required DateTime now,
  required Duration throttle,
}) {
  if (lastRefresh == null) return true;
  return now.difference(lastRefresh) >= throttle;
}

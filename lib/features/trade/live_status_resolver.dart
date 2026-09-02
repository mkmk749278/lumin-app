/// Live-tab auto-trade status resolver (2026-07-17 redesign).
///
/// Pure function: engine truth in, one coherent consumer-facing status
/// out.  Replaces three stacked surfaces (`_AutoTradeDisabledBanner` +
/// `_AutoPauseBanner` + `_AutoTradeArmedCard`) whose combined output
/// read like an ops console to subscribers (owner screenshots).
///
/// Truthfulness invariant: `active` is EXACTLY the old armed-card
/// expression (`runtime.armed && !userSettings.isAutoPaused`) — this
/// redesign changes the language, never the verdict.  The engine
/// remains the source of truth; nothing here derives state the engine
/// didn't send.
import '../../data/repository.dart' show AutoTradeSettings;
import '../../data/server_side_execution_models.dart';

/// Why auto-trade isn't running, in priority order — the card shows
/// only the highest-priority blocker so the user gets ONE next step,
/// with the full gate list behind the Details expander.
enum LiveBlockReason {
  /// Safety check switched the account off (circuit breaker / operator).
  /// Not self-recoverable — email support.
  userDisabled,

  /// Dispatcher paused this account (e.g. empty wallet) — self-
  /// recoverable via Resume.
  autoPaused,

  /// Trading is off for everyone (operator/global) — no user action.
  globalOff,

  /// We could not READ the global flags, so we do not know whether trading is
  /// off (2026-09-02).  Distinct from [globalOff] on purpose: that one is a
  /// deliberate operator pause that resumes on its own, and this one is a
  /// fault that does not.  Telling a subscriber their capital is waiting on an
  /// automatic resume that is never coming is the dangerous direction of this
  /// error, which is why it gets its own reason rather than a softer sentence
  /// under the old one.
  statusUnknown,

  /// No server-connected Binance key yet.
  keyNotConnected,

  /// We could not read whether a key is connected.  The owner's own screenshot
  /// showed "Connect your Binance account" over an account whose key was
  /// connected — an instruction to redo work that is already done, produced by
  /// a failed read wearing an answer's caption.
  keyStatusUnknown,

  /// User's own mode toggle is off.
  modeOff,

  /// Plan doesn't include hands-off auto-trade.
  tierBlocked,

  /// Path/regime filters exclude every signal.
  filtersBlockAll,
}

class LiveGate {
  const LiveGate({required this.label, required this.ok, this.hint});
  final String label;
  final bool ok;
  final String? hint;
}

class LiveStatus {
  const LiveStatus({
    required this.active,
    required this.reason,
    required this.gates,
    required this.watchedSymbols,
  });

  /// True iff live orders can dispatch right now — byte-identical to
  /// the pre-redesign armed-card expression.
  final bool active;

  /// Highest-priority blocker, null when [active].
  final LiveBlockReason? reason;

  /// Full truthful gate list for the Details expander — every failing
  /// gate is always present (never hidden by the single-reason
  /// summary).
  final List<LiveGate> gates;

  /// Count of symbols auto-trade currently covers for this user.
  final int watchedSymbols;
}

LiveStatus resolveLiveStatus({
  required AutoTradeRuntimeStatus runtime,
  AutoTradeUserStatus? userStatus,
  required AutoTradeSettings userSettings,
}) {
  // Pause state reads BOTH sources, mirroring the old armed card: the
  // settings row (#479 dispatcher pause) and the runtime truth field.
  final selfPaused = userSettings.isAutoPaused || (runtime.autoPaused ?? false);
  final userDisabled = runtime.autoTradeUserDisabled ||
      (userStatus?.autoTradeUserDisabled ?? false);
  final modeLive = runtime.userMode == 'live' || runtime.userMode == 'both';

  final active = runtime.armed && !userSettings.isAutoPaused;

  LiveBlockReason? reason;
  if (!active) {
    if (userDisabled) {
      reason = LiveBlockReason.userDisabled;
    } else if (selfPaused) {
      reason = LiveBlockReason.autoPaused;
    } else if (!runtime.autoTradeGloballyEnabled) {
      // An engine that publishes readability and says NO gets the honest
      // "we could not check" copy. `null` is an older engine and keeps the
      // original wording — never downgrade every old build to a fault.
      reason = runtime.globalFlagsReadable == false
          ? LiveBlockReason.statusUnknown
          : LiveBlockReason.globalOff;
    } else if (!runtime.binanceKeyConnected) {
      reason = runtime.binanceKeyReadable == false
          ? LiveBlockReason.keyStatusUnknown
          : LiveBlockReason.keyNotConnected;
    } else if (!modeLive) {
      reason = LiveBlockReason.modeOff;
    } else if (runtime.tierAllowsAuto == false) {
      // Tri-state: null (older engine, unknown) never blocks.
      reason = LiveBlockReason.tierBlocked;
    } else if (runtime.preferencesBlockAll) {
      reason = LiveBlockReason.filtersBlockAll;
    }
  }

  final gates = <LiveGate>[
    LiveGate(
      label: 'Lumin trading enabled',
      ok: runtime.autoTradeGloballyEnabled,
      hint: runtime.autoTradeGloballyEnabled
          ? null
          : runtime.globalFlagsReadable == false
              // Not "switched off" — we could not ask. Saying the first over
              // the second is how a page reports a decision somebody made
              // when what actually happened is that a read failed.
              ? 'We couldn\'t check this just now.'
              : 'Trading is switched off for everyone right now.',
    ),
    LiveGate(
      label: 'Your account active',
      ok: !userDisabled && !selfPaused,
      hint: userDisabled
          ? 'Paused by a safety check — email support to re-enable.'
          : selfPaused
              ? (userSettings.pausedReason == 'insufficient_margin'
                  ? 'Wallet empty — top up, then tap Resume above.'
                  : 'Paused — tap Resume above once fixed.')
              : null,
    ),
    LiveGate(
      label: 'Binance key connected',
      ok: runtime.binanceKeyConnected,
      hint: runtime.binanceKeyConnected
          ? null
          : runtime.binanceKeyReadable == false
              // Never send someone to connect a key we could not check for:
              // if it is already connected, that is an instruction to redo
              // finished work on the screen that spends their money.
              ? 'We couldn\'t check this just now — don\'t re-add your key.'
              : 'Settings → Server-side auto-trade.',
    ),
    LiveGate(
      label: 'Live mode on',
      ok: modeLive,
      hint: modeLive
          ? null
          : 'Flip the Live auto-trade toggle above.',
    ),
    if (runtime.tierAllowsAuto != null)
      LiveGate(
        label: 'Plan includes auto-trade',
        ok: runtime.tierAllowsAuto!,
        hint: runtime.tierAllowsAuto!
            ? null
            : 'Hands-off auto-trade needs the Auto plan. '
                'Menu → Subscription.',
      ),
    if (runtime.preferencesBlockAll)
      const LiveGate(
        label: 'Filters allow signals',
        ok: false,
        hint: 'Your setup/market filters exclude every signal. '
            'Settings → Auto-trade.',
      ),
  ];

  return LiveStatus(
    active: active,
    reason: reason,
    gates: gates,
    watchedSymbols: runtime.effectiveAllowedSymbols.length,
  );
}

/// Subtitle for the Live auto-trade toggle.
///
/// The toggle itself shows user INTENT — correct for a switch, since flipping
/// it is how intent is expressed. This sentence sits under it and describes
/// SYSTEM BEHAVIOUR, so it may only claim dispatch when the engine says
/// dispatch is live ([dispatching] is [LiveStatus.active], nothing derived).
///
/// Before 2026-08-05 the ON copy asserted "Lumin places real Binance Futures
/// orders on your account" from the mode preference alone. With no key
/// connected nothing dispatches, so the claim was false in exactly the state a
/// new user first meets it: a blue ON toggle sitting directly above an amber
/// "Connect your Binance account" card. That is the "card showing armed while
/// dispatch silently skips" class this repo has already paid for.
String liveToggleSubtitle({
  required bool liveActive,
  required bool dispatching,
}) {
  if (!liveActive) {
    return 'Off — enable to place real orders on the next signal.';
  }
  if (dispatching) {
    return 'Lumin places real Binance Futures orders on your account.';
  }
  return 'On — not placing orders yet. See the status below.';
}

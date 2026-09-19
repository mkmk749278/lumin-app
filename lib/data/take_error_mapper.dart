/// Take-flow error → consumer copy (2026-07-17).
///
/// Why this exists: the take sheet rendered the engine's HTTP-4xx
/// ``{"detail": "..."}`` strings verbatim — a paying subscriber saw
/// "user RYhAWEcw…svc2 is auto-disabled" and "order placement failed
/// (phase=entry): code=BINANCE_HTTP_ERROR …" on their phone (owner
/// screenshots).  Every message that can reach the take sheet now
/// routes through here.  Rejection copy delegates to
/// [DispatchEventTranslation.forReject] so the same failure never reads
/// differently between the sheet and the Trade tab's activity rows.
import 'server_side_execution_models.dart';

/// Where a failed take can be fixed from, when it can be fixed at all.
///
/// Why this is on the message rather than decided at the render site
/// (handoff §16, 2026-09-19): the copy already named the destination —
/// *"Settings → Server-side auto-trade takes two minutes"* — and then left
/// the user to find it. An explanation without the action is the half of a
/// recovery that costs nothing to write and everything to follow, and a user
/// whose key just stopped working is the last person who should be navigating
/// a menu from a sentence.
///
/// [none] is a real answer and the common one: a rejected order, a brief
/// outage or a dropped connection has nowhere to go and a button pointing
/// somewhere anyway would be worse than no button — it teaches the reader
/// that the control is decorative.
enum TakeRecovery {
  /// Nothing to open. Retrying, or waiting, is the whole remedy.
  none,

  /// Connect or re-connect the Binance key (server-side execution page).
  /// Also where an IP-whitelist mismatch is repaired, which is the failure
  /// that most looks permanent to a user and most is not.
  exchangeConnection,

  /// Position size and leverage.
  autoTradeSettings,

  /// The paywall — a plan-gated action, not a fault.
  subscription,

  /// Re-authenticate.
  signIn,
}

class TakeErrorMessage {
  const TakeErrorMessage({
    required this.headline,
    required this.action,
    this.recovery = TakeRecovery.none,
  });

  /// Short reason, e.g. "Binance Futures agreement needed".
  final String headline;

  /// One-sentence what-to-do, e.g. "Open Binance → Futures, accept the
  /// agreement, then try again."  May be empty.
  final String action;

  /// Where the user can fix this, if anywhere. See [TakeRecovery].
  final TakeRecovery recovery;

  String get combined => action.isEmpty ? headline : '$headline\n$action';
}

/// Which rejection classes the user can act on, and where.
///
/// Deliberately a short list rather than a broad rule. The copy for each of
/// these already tells the reader to open a specific page — the button just
/// takes them there, so the sentence and the control cannot disagree. Every
/// other class (a closed signal, a rate limit, the kill switch, a Binance
/// refusal) has no page that would help, and is left with no button: see
/// [TakeRecovery.none].
const Map<String, TakeRecovery> _recoveryByRejectClass = {
  // "Connect your Binance API key … on the Connect page".
  'UserNotConnectedError': TakeRecovery.exchangeConnection,
  'AutoTradeDisabledError': TakeRecovery.exchangeConnection,
  // "…re-connect your key in Settings." This is the IP-whitelist mismatch
  // case, which reads to a user like their account is broken and is usually
  // two minutes of work.
  'OrderPlacementKeyError': TakeRecovery.exchangeConnection,
  // "Go to Settings → Auto-trade and increase your position size".
  'NotionalTooSmall': TakeRecovery.autoTradeSettings,
};

/// Business rejection (HTTP 200, ``outcome: rejected``).
TakeErrorMessage translateTakeRejection(TakeSignalResult r) {
  final t = DispatchEventTranslation.forReject(
    rejectClass: r.rejectClass,
    rejectDetail: r.rejectDetail,
    binanceCode: r.rejectBinanceCode,
    binanceMsg: r.rejectBinanceMsg,
    symbol: r.symbol ?? '',
  );
  return TakeErrorMessage(
    headline: t.headline,
    action: t.action,
    recovery: _recoveryByRejectClass[r.rejectClass] ?? TakeRecovery.none,
  );
}

/// Transport / gate failure (HTTP status != 200).  The engine's
/// ``detail`` strings for these are written for its own logs — map the
/// status to consumer copy and never render the raw detail for a
/// status we recognise.
TakeErrorMessage translateTakeHttpError(int status, String rawDetail) {
  switch (status) {
    case 401:
      return const TakeErrorMessage(
        headline: 'Session expired',
        action: 'Sign in again with your phone number, then retry.',
        recovery: TakeRecovery.signIn,
      );
    case 403:
      return const TakeErrorMessage(
        headline: 'One-tap trades need the Assist plan',
        action: 'Upgrade in Menu → Subscription to take signals in a tap.',
        recovery: TakeRecovery.subscription,
      );
    case 409:
      return const TakeErrorMessage(
        headline: 'Connect your Binance key first',
        action: 'It takes about two minutes.',
        recovery: TakeRecovery.exchangeConnection,
      );
    case 503:
      return const TakeErrorMessage(
        headline: 'Trading is briefly unavailable',
        action: 'Please try again in a moment.',
      );
    case 0:
      return const TakeErrorMessage(
        headline: 'No connection',
        action: 'Check your internet connection and try again.',
      );
    default:
      final safe = DispatchEventTranslation.sanitizeEngineDetail(rawDetail);
      return TakeErrorMessage(
        headline: 'Could not take this trade',
        action: safe ?? 'Please try again in a moment.',
      );
  }
}

/// Unexpected client-side exception (timeouts, JSON shape drift…).
TakeErrorMessage translateTakeUnexpected() => const TakeErrorMessage(
      headline: 'Could not take this trade',
      action:
          'Something went wrong on our side. Check your connection and '
          'try again — if it keeps happening, email support from the '
          'About page.',
    );

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

class TakeErrorMessage {
  const TakeErrorMessage({required this.headline, required this.action});

  /// Short reason, e.g. "Binance Futures agreement needed".
  final String headline;

  /// One-sentence what-to-do, e.g. "Open Binance → Futures, accept the
  /// agreement, then try again."  May be empty.
  final String action;

  String get combined => action.isEmpty ? headline : '$headline\n$action';
}

/// Business rejection (HTTP 200, ``outcome: rejected``).
TakeErrorMessage translateTakeRejection(TakeSignalResult r) {
  final t = DispatchEventTranslation.forReject(
    rejectClass: r.rejectClass,
    rejectDetail: r.rejectDetail,
    binanceCode: r.rejectBinanceCode,
    binanceMsg: r.rejectBinanceMsg,
    symbol: r.symbol ?? '',
  );
  return TakeErrorMessage(headline: t.headline, action: t.action);
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
      );
    case 403:
      return const TakeErrorMessage(
        headline: 'One-tap trades need the Assist plan',
        action: 'Upgrade in Menu → Subscription to take signals in a tap.',
      );
    case 409:
      return const TakeErrorMessage(
        headline: 'Connect your Binance key first',
        action: 'Settings → Server-side auto-trade takes two minutes.',
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

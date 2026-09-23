/// Load-failure copy for screens that fetch something and can be retried.
///
/// Added 2026-09-23. Seven screens (pre-TP, eligibility, symbol picker,
/// auto-trade, invalidation, the take sheet, paper trades) rendered
/// `'$e'` / `e.toString()` / the engine's raw `ApiError.message` straight
/// into their error card — so a dropped connection read
/// *"ClientException: Connection closed before full header was received"*
/// and an engine refusal could carry its internal `detail` framing. The take
/// flow already had consumer copy for this (`take_error_mapper.dart`); this
/// is the same idea for everything that is not a trade.
///
/// Rules the copy follows, both from this repo's CLAUDE.md:
///
/// * **Say what we know, and never name a cause we cannot see.** A timeout
///   and a refused socket are both "we couldn't reach Lumin"; neither is
///   "Lumin is down", which the app cannot observe.
/// * **Never promise recovery the app cannot observe.** Copy says "try
///   again", never "this will resolve itself".
library;

import 'dart:async';

import '../data/api_client.dart' show ApiError;
import '../data/server_side_execution_models.dart'
    show DispatchEventTranslation;

/// Consumer copy for a failed load. [what] names the thing that failed to
/// load, lower-case, e.g. `'your settings'`.
String friendlyLoadError(Object error, {String what = 'this'}) {
  if (error is ApiError) {
    switch (error.statusCode) {
      case 0:
        return _offline;
      case 401:
        return 'Your session has expired. Sign in again, then retry.';
      case 403:
        return 'Your plan does not include this yet.';
      case 404:
        return 'This is not available right now. Update the app if an '
            'update is offered, then try again.';
      case 408:
        return _slow(what);
      case 429:
        return 'Too many requests in a short time. Wait a moment and '
            'try again.';
    }
    if (error.statusCode >= 500) {
      return "Lumin's servers could not load $what just now. Please try "
          'again in a moment.';
    }
    // A 4xx we have no copy for: keep the engine's sentence only if it
    // survives the same sanitiser the trade rows use, else say nothing
    // specific rather than something internal.
    final safe = DispatchEventTranslation.sanitizeEngineDetail(error.message);
    return safe ?? "Couldn't load $what. Please try again.";
  }
  if (error is TimeoutException) return _slow(what);

  // Transport failures differ by platform (`SocketException` is dart:io and
  // does not exist on web; `ClientException` comes from package:http), so
  // they are matched by type name rather than imported.
  final type = error.runtimeType.toString();
  if (type.contains('SocketException') ||
      type.contains('ClientException') ||
      type.contains('HandshakeException') ||
      type.contains('HttpException')) {
    return _offline;
  }
  return "Couldn't load $what. Please try again.";
}

const _offline =
    "Couldn't reach Lumin. Check your internet connection and try again.";

String _slow(String what) =>
    'Loading $what took too long. Check your connection and try again.';

/// Consumer copy for a Firebase phone-auth failure, keyed on the stable
/// error [code] rather than Firebase's English [message] — which ranges from
/// fine to *"…in a format that can be parsed into E.164 format. E.164 phone
/// numbers are written in the format [+][country code]…"*. The code is kept
/// in brackets on the fallback because it is what support needs, and is not
/// alarming to read.
String friendlyAuthError(String code, {String action = 'send the code'}) {
  switch (code) {
    case 'invalid-phone-number':
    case 'missing-phone-number':
      return "That number doesn't look right. Check the country and the "
          'number, then try again.';
    case 'too-many-requests':
      return 'Too many attempts from this device. Wait a while, then '
          'try again.';
    case 'quota-exceeded':
      return "We can't send codes right now. Please try again later.";
    case 'network-request-failed':
      return _offline;
    case 'captcha-check-failed':
    case 'web-phone-auth-failed':
      return "Couldn't verify this browser. Refresh the page and try again.";
    case 'user-disabled':
      return 'This account has been disabled. Contact support from the '
          'About page.';
    case 'invalid-app-credential':
    case 'app-not-authorized':
      return "Sign-in isn't available in this version of the app. Update "
          'it, then try again.';
  }
  return "Couldn't $action. Please try again. ($code)";
}

/// Web implementation of [pwa_environment.dart].
///
/// iOS detection is user-agent based (iPadOS ≥13 masquerades as macOS
/// Safari, so the touch-points probe catches modern iPads).  Standalone
/// detection combines the `display-mode` media query (the standard
/// signal once launched from the Home Screen) with Safari's legacy
/// `navigator.standalone`.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool get isIosBrowser {
  final ua = web.window.navigator.userAgent;
  if (RegExp(r'iPhone|iPad|iPod').hasMatch(ua)) return true;
  // iPadOS 13+ reports as "Macintosh" but is the only Mac with touch.
  return ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1;
}

/// True for a browser running on Android — the population that should be
/// sent to Google Play rather than left on the PWA.
///
/// Deliberately narrower than "not iOS": Android *TV*, Android-based
/// kiosks and Chrome OS all carry `Android` or `CrOS` variants, and the
/// phone case is the only one the Play banner is right for. Excluding
/// `Windows` guards against the Windows Subsystem for Android UA, which
/// carries both tokens.
///
/// A miss here costs one un-shown banner; a false positive shows a
/// "get it on Play" prompt to someone who cannot install it, so this
/// fails toward *not* showing.
bool get isAndroidBrowser {
  final ua = web.window.navigator.userAgent;
  if (!ua.contains('Android')) return false;
  if (ua.contains('Windows')) return false;
  // Android TV / set-top boxes cannot install a phone app usefully.
  if (RegExp(r'TV|BRAVIA|AFT[A-Z]').hasMatch(ua)) return false;
  return true;
}

bool get isStandalonePwa {
  try {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    // Safari's pre-standard signal, still set on iOS home-screen apps.
    final legacy = (web.window.navigator as JSObject)
        .getProperty('standalone'.toJS);
    return legacy.isA<JSBoolean>() && (legacy as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}

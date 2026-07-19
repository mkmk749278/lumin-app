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

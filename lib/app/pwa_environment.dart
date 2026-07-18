/// PWA install-state detection façade (web/PWA channel, 2026-07-18).
///
/// The install banner needs two facts the DOM alone can answer: "is this
/// an iOS browser?" and "is the app already running as an installed
/// (Add-to-Home-Screen / standalone) web app?".  The real implementation
/// lives in `pwa_environment_web.dart`; every other platform compiles the
/// stub, which reports "not a browser" so the banner never renders.
library;

export 'pwa_environment_stub.dart'
    if (dart.library.js_interop) 'pwa_environment_web.dart';

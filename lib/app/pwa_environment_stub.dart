/// Non-web stub for [pwa_environment.dart] — native builds are never a
/// browser, so every probe is constant false and the install banner
/// stays out of the tree.
///
/// [isAndroidBrowser] being false here is load-bearing, not incidental:
/// it is what makes it *impossible* for the "Get it on Google Play"
/// banner to render inside the Play build. The Play app compiles this
/// stub, so the banner is excluded at compile time rather than by a
/// runtime channel check that a future refactor could get wrong.
library;

bool get isIosBrowser => false;

bool get isAndroidBrowser => false;

bool get isStandalonePwa => false;

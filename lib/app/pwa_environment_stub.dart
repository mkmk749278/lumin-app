/// Non-web stub for [pwa_environment.dart] — native builds are never a
/// browser, so both probes are constant false and the install banner
/// stays out of the tree.
library;

bool get isIosBrowser => false;

bool get isStandalonePwa => false;

/// Distribution channel the binary was built for.
///
/// Lumin ships through three channels with different update rules:
///
///   * **sideload** (default) — signed APK distributed via GitHub Releases.
///     The in-app updater ([UpdateBanner]) polls Releases, downloads the new
///     APK, and hands off to the system installer. Requires the
///     ``REQUEST_INSTALL_PACKAGES`` permission.
///
///   * **play** — Google Play. Play policy **forbids** an app updating itself
///     by any mechanism other than Play. A Play build must therefore ship
///     with the self-updater inert and must NOT declare
///     ``REQUEST_INSTALL_PACKAGES``. Build with:
///
///         flutter build appbundle --dart-define=LUMIN_DISTRIBUTION=play
///
///   * **web** — the installable web app (PWA) at app.luminapp.org, the
///     iPhone channel (2026-07-18: no App Store path without an Apple
///     Organization account, so the PWA is the iOS product). Web deploys
///     **are** the update mechanism — the self-updater must be inert.
///     Mapped explicitly because the historical "unknown token → sideload"
///     fail-safe would otherwise ship the updater *enabled* on web. Build
///     with:
///
///         flutter build web --dart-define=LUMIN_DISTRIBUTION=web
///
/// The value bakes into the binary at compile time (``String.fromEnvironment``)
/// so a tampered runtime config can't flip a Play build back into a
/// self-installing one.
library;

enum AppDistribution { sideload, play, web }

const String _kRawDistribution =
    String.fromEnvironment('LUMIN_DISTRIBUTION', defaultValue: 'sideload');

/// The channel this binary was built for. The exact tokens ``play`` and
/// ``web`` map to their channels; anything else is treated as sideload
/// (fail-safe: an unknown value keeps the historical behaviour rather than
/// silently disabling updates on an APK build).
const AppDistribution kDistribution = _kRawDistribution == 'play'
    ? AppDistribution.play
    : _kRawDistribution == 'web'
        ? AppDistribution.web
        : AppDistribution.sideload;

/// Whether the in-app GitHub-Releases self-updater is permitted in this build.
/// False on Play, where Play owns updates and APK self-install is a policy
/// violation. False on web, where every page load serves the latest deploy —
/// there is nothing to self-install.
const bool kSelfUpdateEnabled = kDistribution == AppDistribution.sideload;

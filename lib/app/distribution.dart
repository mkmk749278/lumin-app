/// Distribution channel the binary was built for.
///
/// Lumin ships through two channels with different update rules:
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
/// The value bakes into the binary at compile time (``String.fromEnvironment``)
/// so a tampered runtime config can't flip a Play build back into a
/// self-installing one.
library;

enum AppDistribution { sideload, play }

const String _kRawDistribution =
    String.fromEnvironment('LUMIN_DISTRIBUTION', defaultValue: 'sideload');

/// The channel this binary was built for. Anything other than the exact
/// token ``play`` is treated as sideload (fail-safe: an unknown value keeps
/// the historical behaviour rather than silently disabling updates).
const AppDistribution kDistribution =
    _kRawDistribution == 'play' ? AppDistribution.play : AppDistribution.sideload;

/// Whether the in-app GitHub-Releases self-updater is permitted in this build.
/// False on Play, where Play owns updates and APK self-install is a policy
/// violation.
const bool kSelfUpdateEnabled = kDistribution == AppDistribution.sideload;

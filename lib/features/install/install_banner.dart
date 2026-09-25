/// PWA install / notification banner — sits above [NavShell] on the web
/// channel (2026-07-18 iPhone path).  Three jobs, one slot:
///
/// 1. **Android browser, not installed** — send them to Google Play.
///    Added 2026-09-13.  The native app is strictly better for this user
///    (push without an install step, client-side Binance keys, which the
///    web channel excludes for want of keystore-grade storage) *and* it
///    is the only install that Play can see: a PWA install contributes
///    nothing to install velocity, retention or listing conversion, which
///    are the signals that decide whether Play ever recommends us.  An
///    Android visitor left on the PWA is a user we cannot compound.
/// 2. **iOS browser, not installed** — walk the user through
///    *Share → Add to Home Screen*.  This is load-bearing, not a nicety:
///    iOS only grants web push inside an installed web app, so an iPhone
///    user who skips this step can never receive signal notifications.
///    There is no Play equivalent here and never will be — Apple
///    Guideline 3.1.5 makes an App Store listing impossible without an
///    Organization account, which is *why* the PWA is the iOS product.
/// 3. **Installed, permission not yet granted** — offer an "Enable
///    notifications" tap.  Browsers (Apple especially) require the
///    permission prompt to follow a user gesture, so this button *is*
///    the gesture ([NotificationService.enableWebPush]).
///
/// **Why the Play state is gated on [kIsWeb] and not on [kDistribution].**
/// `kIsWeb` is the strictly stronger guard: the Play and sideload builds
/// are native, so they compile `pwa_environment_stub.dart` where every
/// probe is a constant false — the banner cannot reach the tree at all,
/// by compilation rather than by a runtime check.  Gating on the channel
/// token instead would *also* hide the banner on a web bundle built
/// without `--dart-define=LUMIN_DISTRIBUTION=web`, which is a silent miss
/// on a real browser.  Prefer the guard that cannot be got wrong.
///
/// Ordering matters: the Android check runs **before** the push state,
/// because a non-iOS browser already qualified for `enablePush` and
/// would otherwise swallow every Android visitor.  Both branches are
/// worth something, but an install beats a web-push grant — it carries
/// the push permission with it.
///
/// All three states are dismissible; dismissal persists per state in
/// SharedPreferences so the banner doesn't nag, and the notification
/// settings page remains the recovery path after a dismissal.
/// Renders nothing on non-web builds (stub environment probes) and on
/// desktop browsers that aren't installed (they can receive push without
/// installing, so only the permission state shows).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pwa_environment.dart' as pwa;
import '../../data/notification_service.dart';
import '../../shared/tokens.dart';

/// Play listing for the Android build.
///
/// The id is not a free choice — CI runs
/// `flutter create --org=org.luminapp --project-name=lumin`, so the
/// applicationId it produces is `org.luminapp.lumin`. That makes this a
/// cross-repo contract with `.github/workflows/build-apk.yml`, and
/// `test/features/install/play_store_link_test.dart` pins it against the
/// workflow's own flags so a rename fails CI instead of quietly shipping
/// a banner that sends every Android visitor to a 404.
const String kPlayStoreListingUrl =
    'https://play.google.com/store/apps/details?id=org.luminapp.lumin';

enum _BannerState {
  hidden,
  playPrompt,    // Android browser tab → send to the Play listing
  installPrompt, // iOS browser tab → explain Add to Home Screen
  enablePush,    // installed (or desktop browser) → offer permission tap
}

class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  static const _dismissKeyInstall = 'pwa_banner_dismissed_install';
  static const _dismissKeyPush = 'pwa_banner_dismissed_push';
  static const _dismissKeyPlay = 'pwa_banner_dismissed_play';

  _BannerState _state = _BannerState.hidden;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    // Android browser → Play. Checked first: see the ordering note in the
    // library docstring. An Android visitor who has *already* installed
    // the PWA made a deliberate choice, so they fall through to the push
    // state rather than being nagged toward a second install.
    if (pwa.isAndroidBrowser && !pwa.isStandalonePwa) {
      if (prefs.getBool(_dismissKeyPlay) ?? false) return;
      if (!mounted) return;
      setState(() => _state = _BannerState.playPrompt);
      return;
    }
    if (pwa.isIosBrowser && !pwa.isStandalonePwa) {
      if (prefs.getBool(_dismissKeyInstall) ?? false) return;
      if (!mounted) return;
      setState(() => _state = _BannerState.installPrompt);
      return;
    }
    // Installed PWA or a desktop/Android browser: surface the enable
    // step only while permission is still ungranted and a VAPID key is
    // baked in (without one, push can't arm — don't advertise it).
    if (kFcmVapidKey.isEmpty) return;
    if (prefs.getBool(_dismissKeyPush) ?? false) return;
    final granted = await NotificationService.instance.webPushGranted();
    if (granted || !mounted) return;
    setState(() => _state = _BannerState.enablePush);
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissKeyFor(_state), true);
    if (mounted) setState(() => _state = _BannerState.hidden);
  }

  /// One key per state, so dismissing one banner never suppresses another.
  /// Written as an exhaustive switch rather than a ternary chain: adding a
  /// fourth state must fail to compile here, not silently reuse the push
  /// key and make the new banner un-dismissible.
  static String _dismissKeyFor(_BannerState state) => switch (state) {
        _BannerState.playPrompt => _dismissKeyPlay,
        _BannerState.installPrompt => _dismissKeyInstall,
        _BannerState.enablePush => _dismissKeyPush,
        _BannerState.hidden => _dismissKeyPush,
      };

  // ---- state → icon + copy --------------------------------------------
  // Exhaustive switches rather than the old boolean ternary: two states was
  // a ternary, three would be a nested one, and the state after that
  // silently renders another state's copy. Adding a state now fails to
  // compile here instead.

  IconData _icon(_BannerState s) => switch (s) {
        _BannerState.playPrompt => Icons.get_app,
        _BannerState.installPrompt => Icons.ios_share,
        _BannerState.enablePush => Icons.notifications_active_outlined,
        _BannerState.hidden => Icons.close,
      };

  String _title(_BannerState s) => switch (s) {
        _BannerState.playPrompt => 'Get the Lumin Android app',
        _BannerState.installPrompt => 'Install Lumin on your iPhone',
        _BannerState.enablePush => 'Get signal notifications',
        _BannerState.hidden => '',
      };

  String _body(_BannerState s) => switch (s) {
        // No performance claim, by design — this banner is a surface a paid
        // ad can land on, so it stays inside the same rule the ad copy does.
        _BannerState.playPrompt =>
          'Free on Google Play — signal alerts without keeping this tab '
              'open, and Binance keys stored on your device.',
        _BannerState.installPrompt =>
          'Tap Share → Add to Home Screen. Signal notifications only work '
              'from the installed app.',
        _BannerState.enablePush =>
          'Tap to allow notifications for new signals and market alerts.',
        _BannerState.hidden => '',
      };

  Future<void> _onPlayTap() async {
    // launchUrl is called first thing in the tap handler, before any await,
    // so it still carries the user-gesture context a browser requires to
    // allow the navigation. The Instagram and Facebook in-app browsers —
    // which is exactly the traffic this banner was built for — block a
    // window.open that has lost that context.
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(kPlayStoreListingUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // A blocked popup surfaces as a throw on some browsers and as a
      // false return on others. Both mean the same thing to the user, and
      // neither may take the tap handler down with it.
      launched = false;
    }
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open Google Play. Search for "Lumin: Crypto Signals" '
          'in the Play Store.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onEnableTap() async {
    final armed = await NotificationService.instance.enableWebPush();
    if (!mounted) return;
    if (armed) {
      setState(() => _state = _BannerState.hidden);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          armed
              ? 'Signal notifications enabled.'
              : 'Notifications stayed off — you can enable them anytime '
                  'from Menu → Notifications.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // The banner appears after an async prefs read and leaves on dismiss;
  // without easing, the whole page below it jumped both times (UX review
  // 2026-09-25).
  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _content(context),
      );

  Widget _content(BuildContext context) {
    if (_state == _BannerState.hidden) return const SizedBox(width: double.infinity);
    final onTap = switch (_state) {
      _BannerState.playPrompt => _onPlayTap,
      _BannerState.enablePush => _onEnableTap,
      // iOS Add-to-Home-Screen cannot be triggered programmatically —
      // the banner is instructions, so it must not look tappable.
      _BannerState.installPrompt || _BannerState.hidden => null,
    };
    return Material(
      color: LuminColors.bgElevated,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.lg,
            vertical: LuminSpacing.md,
          ),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: LuminColors.cardBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(_icon(_state), color: LuminColors.accent, size: 20),
              const SizedBox(width: LuminSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title(_state),
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _body(_state),
                      style: const TextStyle(
                        color: LuminColors.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    color: LuminColors.textMuted, size: 18),
                onPressed: _dismiss,
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

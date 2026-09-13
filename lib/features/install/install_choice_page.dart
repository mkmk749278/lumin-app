/// First-run install choice — the front door for web visitors
/// (2026-09-13).
///
/// **Why this exists, and why the banner was not enough.** `InstallBanner`
/// ships the same offer, and it mounts inside [NavShell] — which sits
/// *behind* the welcome screen, the consent gate and Firebase phone
/// sign-in. So a visitor arriving from a paid ad could never see it: they
/// land on the welcome page and would have to consent and complete an SMS
/// OTP before the app ever mentioned Google Play. The banner was wired,
/// tested and deployed, and unreachable by the exact audience it was built
/// for — a seam, in this repo's usual shape.
///
/// This page is that offer moved to the first frame, where the traffic
/// actually is:
///
/// * **Android browser** → Google Play. A PWA install contributes nothing
///   Play can see — not install velocity, not retention, not listing
///   conversion — so an Android visitor left on the web app is a user who
///   can never compound into an organic recommendation.
/// * **iOS browser** → Add to Home Screen. There is no Play equivalent and
///   never will be: Apple Guideline 3.1.5 makes an App Store listing
///   impossible without an Organization account, which is *why* the PWA is
///   the iOS product. It is also load-bearing rather than cosmetic — iOS
///   only grants web push inside an installed web app.
/// * **Anything else** (desktop browser, already-installed PWA, every
///   native build) → this page never renders at all. [resolveOffer] is the
///   single predicate, and it fails toward *not* interrupting.
///
/// **Both choices are skippable, by design.** The owner's requirement is
/// that a user can decline and keep using the web app; nothing here gates
/// the product. Skipping records its own flag and deliberately does **not**
/// touch the in-shell banner's dismissal keys, so the suggestion still
/// appears later while the app is in use — one decline at the door is not a
/// decline forever, and they are separate decisions.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pwa_environment.dart' as pwa;
import '../../shared/tokens.dart';
import 'install_banner.dart' show kPlayStoreListingUrl;

/// Which offer this visitor gets. Not a boolean: "we have nothing to offer
/// you" is a third state, and it is the one every desktop and native build
/// lands in.
enum InstallOffer { play, addToHomeScreen, none }

class InstallChoiceStorage {
  InstallChoiceStorage._();

  /// Deliberately NOT shared with `pwa_banner_dismissed_*`. Skipping the
  /// door must not silence the in-app suggestion — see the library doc.
  static const String _kSeenKey = 'install_choice.seen';

  static Future<bool> seen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSeenKey) ?? false;
  }

  static Future<void> recordSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeenKey, true);
  }
}

/// What to offer this visitor, or [InstallOffer.none].
///
/// Every non-web build compiles `pwa_environment_stub.dart`, where all
/// three probes are constant `false` — so this returns `none` on the Play
/// and sideload APKs by *compilation*, not by a runtime check a later
/// refactor could get wrong.
InstallOffer resolveOffer() {
  if (!kIsWeb) return InstallOffer.none;
  // Already installed: they have done the thing this page asks for.
  if (pwa.isStandalonePwa) return InstallOffer.none;
  if (pwa.isAndroidBrowser) return InstallOffer.play;
  if (pwa.isIosBrowser) return InstallOffer.addToHomeScreen;
  // Desktop is neither. Interrupting a desktop visitor with an install
  // prompt they cannot act on is worse than saying nothing.
  return InstallOffer.none;
}

/// Full-screen first-run offer. Rendered only when [resolveOffer] is not
/// [InstallOffer.none] and the flag has not been recorded.
class InstallChoicePage extends StatelessWidget {
  const InstallChoicePage({
    super.key,
    required this.offer,
    required this.onContinue,
  });

  /// Resolved by the caller so the gate and the page cannot disagree about
  /// which platform this is.
  final InstallOffer offer;

  /// Called after the flag is recorded, whether the user took the offer or
  /// skipped it. Taking the offer hands off to Play or to the OS share
  /// sheet, both of which leave the page — so the web app continues
  /// underneath either way rather than stranding them on a dead screen.
  final VoidCallback onContinue;

  bool get _isPlay => offer == InstallOffer.play;

  Future<void> _skip() async {
    await InstallChoiceStorage.recordSeen();
    onContinue();
  }

  Future<void> _openPlay(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // launchUrl first, before any await, so it still carries the
    // user-gesture context a browser requires. The Instagram and Facebook
    // in-app browsers — which is exactly this traffic — block a
    // window.open that has lost it.
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(kPlayStoreListingUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // A blocked popup throws on some browsers and returns false on
      // others. Both mean the same thing to the user.
      launched = false;
    }
    await InstallChoiceStorage.recordSeen();
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open Google Play. Search for "Lumin: Crypto Signals" '
            'in the Play Store.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: LuminSpacing.xl,
              vertical: LuminSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LUMIN',
                    style: TextStyle(
                      color: LuminColors.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: LuminSpacing.xxl),
                  Text(
                    _isPlay
                        ? 'Get the Lumin app'
                        : 'Add Lumin to your Home Screen',
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: LuminSpacing.md),
                  Text(
                    _isPlay
                        ? 'Free on Google Play. Signal alerts without keeping '
                            'this tab open, and Binance keys stored on your '
                            'device.'
                        : 'Tap Share, then Add to Home Screen. Signal '
                            'notifications only work from the installed app '
                            'on iPhone.',
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: LuminSpacing.xl),
                  if (_isPlay)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _openPlay(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: LuminColors.accent,
                          foregroundColor: LuminColors.bgDeep,
                          padding: const EdgeInsets.symmetric(
                            vertical: LuminSpacing.lg,
                          ),
                        ),
                        child: const Text(
                          'Get it on Google Play',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  else
                    // iOS gives no programmatic hook for Add to Home Screen,
                    // so this is instructions rather than a button — it must
                    // not look tappable and then do nothing.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(LuminSpacing.lg),
                      decoration: BoxDecoration(
                        color: LuminColors.bgElevated,
                        borderRadius:
                            BorderRadius.circular(LuminRadii.md),
                        border: Border.all(color: LuminColors.cardBorder),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.ios_share,
                              color: LuminColors.accent, size: 22),
                          SizedBox(width: LuminSpacing.md),
                          Expanded(
                            child: Text(
                              'Share  →  Add to Home Screen',
                              style: TextStyle(
                                color: LuminColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: LuminSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _skip,
                      style: TextButton.styleFrom(
                        foregroundColor: LuminColors.textSecondary,
                        padding: const EdgeInsets.symmetric(
                          vertical: LuminSpacing.lg,
                        ),
                      ),
                      child: Text(
                        _isPlay
                            ? 'Continue in browser'
                            : 'Continue without installing',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: LuminSpacing.sm),
                  const Text(
                    'You can do this any time — the app works either way.',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// PWA install / notification banner — sits above [NavShell] on the web
/// channel (2026-07-18 iPhone path).  Two jobs, one slot:
///
/// 1. **iOS browser, not installed** — walk the user through
///    *Share → Add to Home Screen*.  This is load-bearing, not a nicety:
///    iOS only grants web push inside an installed web app, so an iPhone
///    user who skips this step can never receive signal notifications.
/// 2. **Installed, permission not yet granted** — offer an "Enable
///    notifications" tap.  Browsers (Apple especially) require the
///    permission prompt to follow a user gesture, so this button *is*
///    the gesture ([NotificationService.enableWebPush]).
///
/// Both states are dismissible; dismissal persists per state in
/// SharedPreferences so the banner doesn't nag, and the notification
/// settings page remains the recovery path after a dismissal.
/// Renders nothing on non-web builds (stub environment probes) and on
/// non-iOS browsers that aren't installed (desktop/Android browsers can
/// receive push without installing, so only the permission state shows).
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/pwa_environment.dart' as pwa;
import '../../data/notification_service.dart';
import '../../shared/tokens.dart';

enum _BannerState {
  hidden,
  installPrompt, // iOS browser tab → explain Add to Home Screen
  enablePush,    // installed (or non-iOS browser) → offer permission tap
}

class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  static const _dismissKeyInstall = 'pwa_banner_dismissed_install';
  static const _dismissKeyPush = 'pwa_banner_dismissed_push';

  _BannerState _state = _BannerState.hidden;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
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
    await prefs.setBool(
      _state == _BannerState.installPrompt
          ? _dismissKeyInstall
          : _dismissKeyPush,
      true,
    );
    if (mounted) setState(() => _state = _BannerState.hidden);
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

  @override
  Widget build(BuildContext context) {
    if (_state == _BannerState.hidden) return const SizedBox.shrink();
    final install = _state == _BannerState.installPrompt;
    return Material(
      color: LuminColors.bgElevated,
      child: InkWell(
        onTap: install ? null : _onEnableTap,
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
              Icon(
                install
                    ? Icons.ios_share
                    : Icons.notifications_active_outlined,
                color: LuminColors.accent,
                size: 20,
              ),
              const SizedBox(width: LuminSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      install
                          ? 'Install Lumin on your iPhone'
                          : 'Get signal notifications',
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      install
                          ? 'Tap Share → Add to Home Screen. Signal '
                              'notifications only work from the installed app.'
                          : 'Tap to allow notifications for new signals '
                              'and market alerts.',
                      style: const TextStyle(
                        color: LuminColors.textSecondary,
                        fontSize: 11,
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

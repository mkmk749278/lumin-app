/// Notifications — per-class push toggles (Settings → Notifications).
///
/// Each toggle maps to an FCM topic subscription (see
/// `NotificationService`): turning a class off unsubscribes the device,
/// so delivery stops at FCM — stronger than muting an OS channel.
///
/// Web (PWA, 2026-07-18): browser push additionally needs a granted
/// notification permission, and the prompt must follow a user tap — so
/// this page grows a web-only "Enable browser notifications" card that
/// is the recovery path after the NavShell install banner is dismissed.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../data/notification_service.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool? _alertsEnabled;
  bool? _signalsEnabled;

  /// Web only: false while the browser permission is still ungranted —
  /// drives the enable card.  Always true on native builds.
  bool _webPushGranted = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = NotificationService.instance;
    final alerts = await svc.isTopicEnabled(NotificationService.topicAlerts);
    final signals = await svc.isTopicEnabled(NotificationService.topicSignals);
    final granted = kIsWeb ? await svc.webPushGranted() : true;
    if (!mounted) return;
    setState(() {
      _alertsEnabled = alerts;
      _signalsEnabled = signals;
      _webPushGranted = granted;
    });
  }

  Future<void> _enableWebPush() async {
    final armed = await NotificationService.instance.enableWebPush();
    if (!mounted) return;
    setState(() => _webPushGranted = armed);
    if (!armed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The browser blocked the permission prompt — allow '
            'notifications for Lumin in the browser/site settings.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setAlerts(bool value) async {
    setState(() => _alertsEnabled = value);
    await NotificationService.instance
        .setTopicEnabled(NotificationService.topicAlerts, value);
  }

  Future<void> _setSignals(bool value) async {
    setState(() => _signalsEnabled = value);
    await NotificationService.instance
        .setTopicEnabled(NotificationService.topicSignals, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.lg,
          vertical: LuminSpacing.md,
        ),
        children: [
          if (kIsWeb && !_webPushGranted) ...[
            LuminCard(
              child: Row(
                children: [
                  const Icon(Icons.notifications_off_outlined,
                      color: LuminColors.warn, size: 20),
                  const SizedBox(width: LuminSpacing.md),
                  const Expanded(
                    child: Text(
                      'Browser notifications are off — the toggles below '
                      'take effect once you allow them.',
                      style: TextStyle(
                        color: LuminColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: LuminSpacing.sm),
                  TextButton(
                    onPressed: _enableWebPush,
                    child: const Text('Enable'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
          ],
          LuminCard(
            child: Column(
              children: [
                _ToggleRow(
                  icon: Icons.bolt_outlined,
                  title: 'Signals',
                  subtitle:
                      'New signals going live + their final results (TP/SL).',
                  value: _signalsEnabled,
                  onChanged: _setSignals,
                ),
                const Divider(color: LuminColors.cardBorder, height: 20),
                _ToggleRow(
                  icon: Icons.notifications_active_outlined,
                  title: 'Market alerts',
                  subtitle:
                      'RSI extremes, divergences, abnormal volatility and '
                      'S/R proximity — the Pulse → Alerts feed.',
                  value: _alertsEnabled,
                  onChanged: _setAlerts,
                ),
              ],
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.xs),
            child: Text(
              kIsWeb
                  ? 'Turning a class off unsubscribes this browser — nothing '
                      'is sent, not just silenced. On iPhone, notifications '
                      'only reach the installed (Add to Home Screen) app.'
                  : 'Turning a class off unsubscribes this device — nothing '
                      'is sent, not just silenced. Also make sure Lumin '
                      'notifications are allowed in Android settings.',
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// null while the persisted preference is still loading.
  final bool? value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: LuminColors.accent, size: 20),
        const SizedBox(width: LuminSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: LuminSpacing.sm),
        value == null
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: LuminColors.accent,
                ),
              )
            : Switch(
                value: value!,
                activeColor: LuminColors.accent,
                onChanged: onChanged,
              ),
      ],
    );
  }
}

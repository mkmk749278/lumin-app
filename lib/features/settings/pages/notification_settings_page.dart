/// Notifications — per-class push toggles (Settings → Notifications).
///
/// Each toggle maps to an FCM topic subscription (see
/// `NotificationService`): turning a class off unsubscribes the device,
/// so delivery stops at FCM — stronger than muting an OS channel.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = NotificationService.instance;
    final alerts = await svc.isTopicEnabled(NotificationService.topicAlerts);
    final signals = await svc.isTopicEnabled(NotificationService.topicSignals);
    if (!mounted) return;
    setState(() {
      _alertsEnabled = alerts;
      _signalsEnabled = signals;
    });
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: LuminSpacing.xs),
            child: Text(
              'Turning a class off unsubscribes this device — nothing is '
              'sent, not just silenced. Also make sure Lumin notifications '
              'are allowed in Android settings.',
              style: TextStyle(
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

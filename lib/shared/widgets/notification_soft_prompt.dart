/// The one-time "turn on alerts" sheet, shown inside the signed-in app
/// (2026-11-26).
///
/// Android 13+ used to raise the system notification dialog on the splash,
/// before the user had seen a single signal — the moment it is most often
/// denied, and a denial is sticky. Now the signed-in shell asks once, says
/// what the alerts are, and only then hands over to the system dialog.
library;

import 'package:flutter/material.dart';

import '../../data/notification_service.dart';
import '../tokens.dart';

/// Shows the soft prompt when [NotificationService.shouldOfferAndroidPrompt]
/// says so. Safe to call on every shell mount: it is a no-op after the first
/// answer, on web, and when notifications are already allowed.
Future<void> maybeOfferNotificationPrompt(BuildContext context) async {
  final service = NotificationService.instance;
  if (!await service.shouldOfferAndroidPrompt()) return;
  if (!context.mounted) return;
  final turnOn = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: LuminColors.bgElevated,
    showDragHandle: true,
    builder: (ctx) => const NotificationSoftPromptSheet(),
  );
  if (turnOn == true) {
    await service.requestAndroidPermission();
  } else {
    // "Not now" or dismissed: do not ask again on every launch. The user
    // can still turn alerts on from Settings → Notifications.
    await service.markAndroidPromptAsked();
  }
}

class NotificationSoftPromptSheet extends StatelessWidget {
  const NotificationSoftPromptSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            LuminSpacing.xl, 0, LuminSpacing.xl, LuminSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Turn on alerts?', style: text.titleLarge),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              'Lumin notifies you when a new signal is published and when '
              'a market alert fires. You can change either one any time in '
              'Settings.',
              style: text.bodyMedium
                  ?.copyWith(color: LuminColors.textSecondary),
            ),
            const SizedBox(height: LuminSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: LuminSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Turn on'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

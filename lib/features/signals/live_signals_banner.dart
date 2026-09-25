/// The strip above the Signals feed that explains the live-signal paywall
/// (owner, 2026-09-25).
///
/// Renders only what the engine reported on the latest `/api/signals` read
/// ([LuminRepository.liveFeedAccess]); it decides nothing itself.
///   * guest        — "N live signals right now" → create a free account.
///   * locked       — free days over, no plan → see plans.
///   * free_window  — "Live signals free: N days left" → see plans.
///   * anything else (plan, paywall off, older engine) — nothing.
library;

import 'package:flutter/material.dart';

import '../../app/distribution.dart';
import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import '../auth/widgets/account_required.dart';
import '../settings/pages/subscription_page.dart';
import '../settings/pages/web_paywall_page.dart';

class LiveSignalsBanner extends StatelessWidget {
  const LiveSignalsBanner({super.key});

  void _openPlans(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => kDistribution == AppDistribution.web
            ? const WebPaywallPage()
            : const SubscriptionPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppConfigScope.of(context).repo;
    return ValueListenableBuilder<LiveFeedAccess?>(
      valueListenable: repo.liveFeedAccess,
      builder: (context, access, _) {
        if (access == null) return const SizedBox.shrink();
        final n = access.lockedOpenCount;
        final countLine = n == 1
            ? '1 live signal right now'
            : '$n live signals right now';
        if (access.isGuest) {
          return _Strip(
            icon: Icons.lock_outline,
            title: n > 0 ? countLine : 'Live signals are for members',
            body: 'You are seeing closed signals. Create a free account '
                'to see live ones — free for 3 days.',
            cta: 'Create free account',
            onTap: () => openCreateAccount(context),
          );
        }
        if (access.locked) {
          return _Strip(
            icon: Icons.lock_outline,
            title: n > 0 ? countLine : 'Live signals are locked',
            body: 'Your 3 free days are over. The Signals plan unlocks live '
                'signals; closed signals stay free.',
            cta: 'See plans',
            onTap: () => _openPlans(context),
          );
        }
        if (access.isFreeWindow) {
          final days = access.daysLeft(DateTime.now().toUtc());
          return _Strip(
            icon: Icons.timer_outlined,
            title: days <= 1
                ? 'Live signals free — last day'
                : 'Live signals free — $days days left',
            body: 'After that, the Signals plan keeps them on.',
            cta: 'See plans',
            onTap: () => _openPlans(context),
            quiet: true,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
    this.quiet = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final accent = quiet ? LuminColors.textSecondary : LuminColors.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg, LuminSpacing.sm, LuminSpacing.lg, 0,
      ),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(
            color: quiet ? LuminColors.cardBorder : LuminColors.accent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 22),
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
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: LuminSpacing.sm),
            TextButton(
              onPressed: onTap,
              child: Text(
                cta,
                style: TextStyle(color: accent, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

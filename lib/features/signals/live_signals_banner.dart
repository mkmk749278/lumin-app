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

import 'dart:ui' show ImageFilter;

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

/// A live signal shown masked to a caller without live access (owner,
/// 2026-09-25: *"show all live signals but mask them, and add click here to
/// see signal and ask user to sign up"*).
///
/// The real levels never reach the app (engine `LockedSignal`); the blurred
/// numbers here are fixed placeholders, so there is nothing to un-blur.
class LockedSignalCard extends StatelessWidget {
  const LockedSignalCard({
    super.key,
    required this.signal,
    required this.guest,
  });

  final LockedSignal signal;
  final bool guest;

  void _unlock(BuildContext context) {
    if (guest) {
      openCreateAccount(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => kDistribution == AppDistribution.web
            ? const WebPaywallPage()
            : const SubscriptionPage(),
      ),
    );
  }

  String get _age {
    final m = signal.minutesAgo;
    if (m < 1) return 'just now';
    if (m < 60) return '$m min ago';
    final h = m ~/ 60;
    return h == 1 ? '1 hr ago' : '$h hrs ago';
  }

  @override
  Widget build(BuildContext context) {
    final cta = guest ? 'Sign up free to see signal' : 'Unlock with Signals plan';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.md),
        onTap: () => _unlock(context),
        child: Container(
          padding: const EdgeInsets.all(LuminSpacing.md),
          decoration: BoxDecoration(
            color: LuminColors.bgCard,
            borderRadius: BorderRadius.circular(LuminRadii.md),
            border: Border.all(color: LuminColors.accent.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: LuminColors.accent.withValues(alpha: 0.18),
                blurRadius: 18,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _LivePill(),
                  const SizedBox(width: LuminSpacing.sm),
                  Text(
                    signal.symbol,
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: LuminSpacing.sm),
                  const _Masked(width: 52, height: 20),
                  const Spacer(),
                  Text(
                    _age,
                    style: const TextStyle(color: LuminColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
              if (signal.agentName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  signal.qualityTier.isEmpty
                      ? signal.agentName
                      : '${signal.agentName} · ${signal.qualityTier} tier',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: LuminSpacing.md),
              const Row(
                children: [
                  Expanded(child: _MaskedLevel(label: 'Entry')),
                  Expanded(child: _MaskedLevel(label: 'Stop')),
                  Expanded(child: _MaskedLevel(label: 'Target')),
                ],
              ),
              const SizedBox(height: LuminSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: LuminColors.accent,
                    foregroundColor: LuminColors.bgDeep,
                    padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
                  ),
                  onPressed: () => _unlock(context),
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: Text(
                    cta,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: LuminColors.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(LuminRadii.pill),
        border: Border.all(color: LuminColors.success.withValues(alpha: 0.6)),
      ),
      child: const Text(
        '● LIVE',
        style: TextStyle(
          color: LuminColors.success,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// A blurred placeholder block.  Placeholder only: the real value is not in
/// the app to blur.
class _Masked extends StatelessWidget {
  const _Masked({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: LuminColors.textSecondary.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _MaskedLevel extends StatelessWidget {
  const _MaskedLevel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label ',
          style: const TextStyle(color: LuminColors.textMuted, fontSize: 11),
        ),
        const Icon(Icons.lock_outline, size: 12, color: LuminColors.textMuted),
        const SizedBox(width: 4),
        const Flexible(child: _Masked(width: 44, height: 12)),
      ],
    );
  }
}

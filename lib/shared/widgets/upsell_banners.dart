/// Reusable growth banners — subscription upsell + referral invite (2026-07-21).
///
/// The B16 paywall (Assist/Auto) and the Phase-2 referral deal (engine #767:
/// 7 free Auto days + 50% commission per join, friend gets 50% off) were only
/// reachable by digging into Menu → Settings.  Nothing on the feed tabs told a
/// free user those benefits existed.  These two banners surface them where the
/// user already is — Pulse, Signals, Trade — so the value prop and the invite
/// are visible everywhere without a separate navigation step.
///
/// Design follows the repo's testable-seam convention (mirrors
/// `CurrentPlanCard`): the *pure* [UpgradeBannerCard] / [InviteBannerCard] take
/// explicit params and are widget-tested; the thin [UpgradeBanner] /
/// [InviteBanner] wrappers read [AppConfigScope] + fetch engine truth and are
/// not (lumin-app has no AppConfigScope test-injection seam — same call the
/// RegionGate widget made).
///
/// Truthfulness (repo doctrine: render engine state, never derive): the upgrade
/// banner hides itself the instant the user reaches Auto (via `tierRevision`),
/// and the invite banner only promises rewards while the engine reports
/// `rewards_enabled` — otherwise it falls back to a plain "invite a friend".
library;

import 'package:flutter/material.dart';

import '../../app/distribution.dart';
import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../features/settings/pages/referral_page.dart';
import '../../features/settings/pages/subscription_page.dart';
import '../../features/settings/pages/web_paywall_page.dart';
import '../tokens.dart';
import 'free_tier_gate.dart';

// ---------------------------------------------------------------------------
// Navigation helpers — one place for "open the right paywall for this channel"
// (Play Billing is store-bound, so the web build sells via the crypto rail).
// ---------------------------------------------------------------------------

/// Open the channel-appropriate paywall: the crypto [WebPaywallPage] on the
/// web build, the Google Play [SubscriptionPage] everywhere else.  Mirrors the
/// Settings → Subscription routing so there is a single source of that rule.
Future<void> openPaywall(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => kDistribution == AppDistribution.web
          ? const WebPaywallPage()
          : const SubscriptionPage(),
    ),
  );
}

/// Open the Invite-a-friend page (the full, engine-truth reward breakdown).
Future<void> openReferralPage(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ReferralPage()),
  );
}

// ---------------------------------------------------------------------------
// Session dismiss — a banner the user closed stays closed until next launch
// (not hostile, but re-earns the pitch on a fresh session).  Keyed per slot so
// the Pulse copy and the Signals copy dismiss independently.
// ---------------------------------------------------------------------------

final Set<String> _dismissedSlots = <String>{};

// ---------------------------------------------------------------------------
// Referral-stats cache — the invite banner needs engine truth, but it can be
// mounted on several tabs at once.  One in-flight GET is shared across them and
// re-used until the repo instance changes (mock ↔ live swap on reconfigure).
// ---------------------------------------------------------------------------

Future<ReferralStats>? _statsFuture;
LuminRepository? _statsRepo;

Future<ReferralStats> _referralStats(LuminRepository repo) {
  if (!identical(_statsRepo, repo) || _statsFuture == null) {
    _statsRepo = repo;
    _statsFuture = repo.getReferralStats();
  }
  return _statsFuture!;
}

// ---------------------------------------------------------------------------
// Shared visual scaffold
// ---------------------------------------------------------------------------

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.onTap,
    this.onDismiss,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String cta;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.lg,
        vertical: LuminSpacing.xs,
      ),
      child: Material(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LuminRadii.lg),
          child: Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LuminRadii.lg),
              border: Border.all(color: accent.withOpacity(0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(LuminSpacing.sm),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(LuminRadii.sm),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: LuminSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: LuminColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: LuminSpacing.sm),
                      Row(
                        children: [
                          Text(
                            cta,
                            style: TextStyle(
                              color: accent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_forward_rounded,
                              color: accent, size: 14),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  GestureDetector(
                    onTap: onDismiss,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: LuminSpacing.xs),
                      child: Icon(Icons.close_rounded,
                          color: LuminColors.textMuted, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Subscription upgrade banner
// ---------------------------------------------------------------------------

/// Pure upgrade card — visible to free (rank 0) and Assist (rank 1) users,
/// hidden once the user reaches Auto (rank ≥ 2) where there is nothing left to
/// sell.  Copy is tier-aware: free users hear the whole ladder, Assist users
/// are nudged the one rung to hands-off Auto.
class UpgradeBannerCard extends StatelessWidget {
  const UpgradeBannerCard({
    super.key,
    required this.tier,
    required this.onSeePlans,
    this.onDismiss,
  });

  final String? tier;
  final VoidCallback onSeePlans;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (tierRank(tier) >= 2) return const SizedBox.shrink();
    final isAssist = tierRank(tier) == 1;
    return _BannerCard(
      icon: Icons.workspace_premium_rounded,
      accent: LuminColors.accent,
      title: isAssist ? 'Go fully hands-off' : 'Automate your signals',
      subtitle: isAssist
          ? 'Upgrade to Auto — the engine trades every eligible signal for '
              'you, 24/7, on your own exchange keys.'
          : 'Every signal is free. Add one-tap trading with Assist, or '
              'hands-off Auto — all on your own exchange keys.',
      cta: isAssist ? 'Upgrade to Auto' : 'See plans',
      onTap: onSeePlans,
      onDismiss: onDismiss,
    );
  }
}

/// Scope wrapper — reads the cached tier under a [AppConfigScope.tierRevision]
/// listener so the banner vanishes the moment a purchase lands, and routes the
/// CTA to the channel-appropriate paywall.  Dismiss is per-session.
class UpgradeBanner extends StatefulWidget {
  const UpgradeBanner({super.key, this.slot = 'upgrade'});

  /// Distinguishes dismiss state between surfaces (e.g. `signals`, `trade`).
  final String slot;

  @override
  State<UpgradeBanner> createState() => _UpgradeBannerState();
}

class _UpgradeBannerState extends State<UpgradeBanner> {
  @override
  Widget build(BuildContext context) {
    if (_dismissedSlots.contains('upgrade:${widget.slot}')) {
      return const SizedBox.shrink();
    }
    final scope = AppConfigScope.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: scope.tierRevision,
      builder: (context, _, __) => UpgradeBannerCard(
        tier: scope.tier,
        onSeePlans: () => openPaywall(context),
        onDismiss: () =>
            setState(() => _dismissedSlots.add('upgrade:${widget.slot}')),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Referral invite banner
// ---------------------------------------------------------------------------

/// Pure invite card — renders the standing reward deal from engine truth.
/// Only promises rewards while `rewards_enabled`; otherwise it degrades to a
/// plain invite so a switched-off programme never over-promises.
class InviteBannerCard extends StatelessWidget {
  const InviteBannerCard({
    super.key,
    required this.stats,
    required this.onInvite,
    this.onDismiss,
  });

  final ReferralStats stats;
  final VoidCallback onInvite;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final rewards = stats.rewardsEnabled;
    final commission = '${(stats.commissionRate * 100).round()}%';
    return _BannerCard(
      icon: Icons.card_giftcard_rounded,
      accent: LuminColors.success,
      title: rewards ? 'Invite friends, earn free Auto' : 'Invite a friend',
      subtitle: rewards
          ? 'Get ${stats.rewardDaysPerInvite} free '
              '${_rewardTierLabel(stats.rewardTier)} days + $commission '
              'commission for every friend who joins. They get '
              '${stats.discountPercent}% off their first month.'
          : 'Share Lumin with friends who trade crypto — track who joins.',
      cta: rewards ? 'Invite & earn' : 'Invite',
      onTap: onInvite,
      onDismiss: onDismiss,
    );
  }
}

/// Scope wrapper — fetches (and caches) `GET /api/referral/me` and renders the
/// card only once real stats arrive; shows nothing while loading or on error so
/// the banner never flashes placeholder or misleading copy.  Dismiss is
/// per-session.
class InviteBanner extends StatefulWidget {
  const InviteBanner({super.key, this.slot = 'invite'});

  final String slot;

  @override
  State<InviteBanner> createState() => _InviteBannerState();
}

class _InviteBannerState extends State<InviteBanner> {
  Future<ReferralStats>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _referralStats(AppConfigScope.of(context).repo);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissedSlots.contains('invite:${widget.slot}')) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<ReferralStats>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            !snap.hasData ||
            snap.hasError) {
          return const SizedBox.shrink();
        }
        return InviteBannerCard(
          stats: snap.data!,
          onInvite: () => openReferralPage(context),
          onDismiss: () =>
              setState(() => _dismissedSlots.add('invite:${widget.slot}')),
        );
      },
    );
  }
}

String _rewardTierLabel(String? tier) {
  switch ((tier ?? '').toLowerCase()) {
    case 'assist':
      return 'Assist';
    case 'auto':
      return 'Auto';
    default:
      return 'Auto';
  }
}

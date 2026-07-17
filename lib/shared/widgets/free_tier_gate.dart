/// Tier gate for the B16 two-tier auto-trade paywall.
///
/// Signals + entry/SL/TP + analysis are FREE — the paywall is on trade
/// automation only.  This file exposes the tier helpers (`tierRank`,
/// `canAssist`, `canAuto`) used to gate the one-tap "take trade" (Assist)
/// and hands-off auto-execution (Auto) surfaces, plus [UpgradeSheet] — a
/// lightweight inline upsell that routes to the full SubscriptionPage so
/// the user can act immediately without navigating away.
///
/// Tier is read from [AppConfigScope], populated from the Firebase session +
/// engine profile/entitlement.  Null / unknown → free.
import 'package:flutter/material.dart';

import '../../features/settings/pages/subscription_page.dart';
import '../tokens.dart';

/// Subscription tier rank for the B16 two-tier auto-trade model.
///
/// `free(0) < assist(1) < auto(2)`; legacy `paid` maps to auto, and
/// `all-access` / `owner` sit above.  Signals + levels are FREE — the
/// paywall is on trade automation only.
///
/// Null / unknown → 0 (free).  We err **closed** on the paid actions: the
/// Assist (one-tap) path places orders **client-side**, so the app is the
/// only gate — there's no server 403 to fall back on.
int tierRank(String? tier) {
  switch ((tier ?? '').toLowerCase()) {
    case 'owner':
    case 'all-access':
      return 3;
    case 'auto':
    case 'paid': // legacy single paid tier == full automation
      return 2;
    case 'assist':
      return 1;
    default:
      return 0;
  }
}

/// May place one-tap (assisted) live trades — Assist tier or higher.
bool canAssist(String? tier) => tierRank(tier) >= 1;

/// May enable hands-off auto-execution — Auto tier (or higher).
bool canAuto(String? tier) => tierRank(tier) >= 2;

/// Any paying tier (mirrors the engine's `PlayVerifyResult.isPaid` set:
/// assist / auto / legacy paid / all-access / owner).  Drives the
/// "you're subscribed" surfaces — CurrentPlanCard, Profile subscription
/// card, Menu subtitle.
bool isPaidTier(String? tier) => tierRank(tier) >= 1;

/// Consumer-facing plan name for a tier value.  Never returns engine
/// vocabulary — unknown non-empty tiers fall back to a capitalised echo
/// so a future tier renders decently on old builds.
String tierDisplayName(String? tier) {
  switch ((tier ?? '').toLowerCase()) {
    case 'owner':
    case 'all-access':
      return 'All Access';
    case 'auto':
      return 'Auto';
    case 'paid':
      return 'Auto'; // legacy single paid tier == full automation
    case 'assist':
      return 'Assist';
    case '':
    case 'free':
      return 'Free';
    default:
      final t = tier!.toLowerCase();
      return t[0].toUpperCase() + t.substring(1);
  }
}

/// Google Play subscription-management deep link for the user's current
/// plan.  With a known Play SKU it lands directly on that subscription;
/// otherwise on the account's subscriptions list (legacy / owner tiers
/// have no Play SKU).
String playManageSubscriptionUrl(String? tier) {
  const pkg = 'org.luminapp.lumin';
  final sku = switch ((tier ?? '').toLowerCase()) {
    'assist' => kAssistMonthlyId,
    'auto' => kAutoMonthlyId,
    _ => null,
  };
  if (sku == null) {
    return 'https://play.google.com/store/account/subscriptions';
  }
  return 'https://play.google.com/store/account/subscriptions'
      '?sku=$sku&package=$pkg';
}

/// Show the upgrade bottom sheet from any context.
void showUpgradeSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: LuminColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
    ),
    builder: (_) => const UpgradeSheet(),
  );
}

/// Inline upgrade sheet — shown when a sub-tier user taps a gated action
/// (one-tap "take trade", auto-trade settings).  Lighter than navigating
/// to the full SubscriptionPage; surfaces what Assist/Auto unlock and a
/// "See plans" CTA that routes to the Google Play SubscriptionPage (B16 —
/// the Telegram-bot paywall was retired, Telegram is banned in-region).
class UpgradeSheet extends StatelessWidget {
  const UpgradeSheet({super.key});

  static const _features = [
    (Icons.bolt_rounded, 'Assist — take any signal in one tap'),
    (Icons.smart_toy_rounded, 'Auto — hands-off, every eligible signal'),
    (Icons.vpn_key_rounded, 'Runs on your own exchange keys'),
    (Icons.trending_up_rounded, 'Pre-TP lock-in & auto-breakeven'),
    (Icons.tune_rounded, 'Per-agent & risk controls (Auto)'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LuminSpacing.xl,
          LuminSpacing.lg,
          LuminSpacing.xl,
          LuminSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LuminColors.cardBorder,
                  borderRadius: BorderRadius.circular(LuminRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.xl),

            // Headline
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(LuminSpacing.sm),
                  decoration: BoxDecoration(
                    color: LuminColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(LuminRadii.sm),
                  ),
                  child: const Icon(Icons.lock_open_rounded,
                      color: LuminColors.accent, size: 22),
                ),
                const SizedBox(width: LuminSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lumin Pro',
                        style: TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Automate the trades — one-tap or hands-off',
                        style: TextStyle(
                          color: LuminColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: LuminSpacing.xl),

            // What paid unlocks
            ...List.generate(_features.length, (i) {
              final (icon, text) = _features[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: LuminSpacing.sm),
                child: Row(
                  children: [
                    Icon(icon, color: LuminColors.success, size: 16),
                    const SizedBox(width: LuminSpacing.md),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: LuminSpacing.xl),

            // Pricing hint
            Container(
              padding: const EdgeInsets.all(LuminSpacing.md),
              decoration: BoxDecoration(
                color: LuminColors.bgElevated,
                borderRadius: BorderRadius.circular(LuminRadii.md),
                border: Border.all(color: LuminColors.cardBorder),
              ),
              child: const Row(
                children: [
                  Text(
                    'Assist or Auto · monthly · cancel anytime',
                    style: TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'See plans',
                    style: TextStyle(
                      color: LuminColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: LuminSpacing.lg),

            // Play Billing CTA → full subscription page (B16)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: LuminColors.accent,
                  foregroundColor: LuminColors.bgDeep,
                  padding: const EdgeInsets.symmetric(
                    vertical: LuminSpacing.md + 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(LuminRadii.md),
                  ),
                ),
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text(
                  'See plans',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => const SubscriptionPage(),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: LuminSpacing.sm),
            const Center(
              child: Text(
                'Billed securely through Google Play',
                style: TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

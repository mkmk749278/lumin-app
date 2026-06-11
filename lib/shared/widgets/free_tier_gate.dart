/// Free-tier signal gate — locks SL/TP/entry price fields for users who
/// haven't subscribed, and surfaces an upgrade CTA when they tap.
///
/// Uses the tier claim from [AppConfigScope] which is already populated
/// everywhere via the Firebase JWT.  Free users see that a signal fired,
/// its direction, setup, confidence, and outcome — they cannot see the
/// operational levels (entry, SL, TP) that let them actually trade it.
///
/// The upgrade sheet is a lightweight inline version of the full
/// SubscriptionPage so the user can act immediately without navigating away.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_config.dart';
import '../tokens.dart';

/// Returns true when the tier claim indicates an active paid subscription.
/// [null] is treated as "not yet determined" — the engine will 403 if the
/// user genuinely isn't paid, so we don't block the UI on a missing claim.
bool isPaidTier(String? tier) {
  if (tier == null) return true; // err open — backend is the authoritative gate
  final t = tier.toLowerCase();
  return t == 'pro' || t == 'paid' || t == 'premium' || t == 'a+' ||
      t == 'b' || t == 'beta' || t == 'admin';
}

/// Reads the tier from [AppConfigScope] and calls [builder] with the result.
/// Avoids duplicating the context lookup at every call site.
class TierGate extends StatelessWidget {
  const TierGate({
    super.key,
    required this.paidBuilder,
    required this.freeBuilder,
  });

  final WidgetBuilder paidBuilder;
  final WidgetBuilder freeBuilder;

  @override
  Widget build(BuildContext context) {
    final tier = AppConfigScope.of(context).tier;
    return isPaidTier(tier) ? paidBuilder(context) : freeBuilder(context);
  }
}

/// A price column replacement for free-tier users.
///
/// Shows the column label and a locked chip. Tapping anywhere in the column
/// opens [UpgradeSheet].  Width and layout match [_PriceCol] in
/// signals_page.dart so the card row doesn't reflow.
class LockedPriceCol extends StatelessWidget {
  const LockedPriceCol({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showUpgradeSheet(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: LuminColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: LuminColors.bgElevated,
              borderRadius: BorderRadius.circular(LuminRadii.sm),
              border: Border.all(color: LuminColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.lock_outline_rounded,
                    size: 10, color: LuminColors.warn),
                SizedBox(width: 3),
                Text(
                  'PRO',
                  style: TextStyle(
                    color: LuminColors.warn,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A locked detail row used in the signal detail sheet.
/// Label shows as normal; value is replaced by a tappable lock chip.
class LockedDetailRow extends StatelessWidget {
  const LockedDetailRow({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => showUpgradeSheet(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: LuminColors.bgElevated,
                borderRadius: BorderRadius.circular(LuminRadii.sm),
                border: Border.all(color: LuminColors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.lock_outline_rounded,
                      size: 11, color: LuminColors.warn),
                  SizedBox(width: 4),
                  Text(
                    'Unlock with Pro',
                    style: TextStyle(
                      color: LuminColors.warn,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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

/// Inline upgrade sheet — shown when a free user taps a locked field.
/// Lighter than navigating to the full SubscriptionPage; surfaces the key
/// proof points and the Telegram bot CTA.
class UpgradeSheet extends StatelessWidget {
  const UpgradeSheet({super.key});

  static const _features = [
    (Icons.price_check_rounded, 'Entry, SL & TP levels on every signal'),
    (Icons.notifications_active_rounded, 'Real-time Telegram signal alerts'),
    (Icons.smart_toy_rounded, 'Full 15-evaluator AI analysis'),
    (Icons.trending_up_rounded, 'Auto-trade & pre-TP lock-in'),
    (Icons.bar_chart_rounded, 'Per-agent & per-setup performance deep-dive'),
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
                        'Unlock entry, SL & TP on every signal',
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
                    'From \$30/mo · \$300/yr · \$999 lifetime',
                    style: TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '17% off yearly',
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

            // Telegram CTA
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
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text(
                  'Upgrade via Telegram  @LuminProBot',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  final uri = Uri.parse('https://t.me/LuminProBot');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ),

            const SizedBox(height: LuminSpacing.sm),
            const Center(
              child: Text(
                'Payment & activation handled by @LuminProBot',
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

/// Subscription page — Free vs Pro tier comparison + Telegram bot deep link.
///
/// Per Play Store reader-app exception, crypto subscription must NOT use
/// Google Play Billing.  Subscriptions are managed via the @LuminProBot
/// Telegram bot — tap "Upgrade" → opens t.me/LuminProBot.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          _heroCard(),
          const SizedBox(height: LuminSpacing.md),
          _tierComparison(),
          const SizedBox(height: LuminSpacing.md),
          _pricingCards(context),
          const SizedBox(height: LuminSpacing.md),
          _telegramCta(context),
          const SizedBox(height: LuminSpacing.md),
          _disclaimer(),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              LuminColors.accent.withOpacity(0.18),
              LuminColors.accent.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(LuminRadii.lg),
          border: Border.all(color: LuminColors.accent.withOpacity(0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.workspace_premium, color: LuminColors.accent, size: 32),
            SizedBox(height: LuminSpacing.sm),
            Text(
              'Lumin Pro',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: LuminSpacing.xs),
            Text(
              'Full 15-evaluator paid signals.  Real-time Telegram dispatch.  '
              'Auto-trade unlock.',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tierComparison() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WHAT YOU GET',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            _featureRow('Watchlist signals (free channel)', true, true),
            _featureRow('Paid signals — 15 evaluators', false, true),
            _featureRow('Real-time Telegram dispatch', false, true),
            _featureRow('Pre-TP grab + auto-breakeven', false, true),
            _featureRow('In-app auto-trade (Paper)', false, true),
            _featureRow('In-app auto-trade (Live)', false, true),
            _featureRow('Per-agent toggles', false, true),
            _featureRow('Custom risk gates', false, true),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(String label, bool free, bool pro) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Icon(
                free ? Icons.check_circle : Icons.remove_circle_outline,
                color: free ? LuminColors.success : LuminColors.textMuted,
                size: 16,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Icon(
                pro ? Icons.check_circle : Icons.remove_circle_outline,
                color: pro ? LuminColors.accent : LuminColors.textMuted,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pricingCards(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Column(
        children: [
          _priceTile(
            context,
            label: 'Monthly',
            price: '\$30',
            unit: '/ month',
            note: 'Cancel anytime',
            highlight: false,
          ),
          const SizedBox(height: LuminSpacing.sm),
          _priceTile(
            context,
            label: 'Yearly',
            price: '\$300',
            unit: '/ year',
            note: 'Save \$60 — equivalent to 2 months free',
            highlight: true,
          ),
          const SizedBox(height: LuminSpacing.sm),
          _priceTile(
            context,
            label: 'Lifetime',
            price: '\$999',
            unit: 'one-time',
            note: 'Pay once, paid signals forever',
            highlight: false,
          ),
        ],
      ),
    );
  }

  Widget _priceTile(
    BuildContext context, {
    required String label,
    required String price,
    required String unit,
    required String note,
    required bool highlight,
  }) {
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: highlight
            ? LuminColors.accent.withOpacity(0.10)
            : LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        border: Border.all(
          color: highlight
              ? LuminColors.accent.withOpacity(0.50)
              : LuminColors.cardBorder,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (highlight) ...[
                      const SizedBox(width: LuminSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: LuminSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: LuminColors.accent,
                          borderRadius: BorderRadius.circular(LuminRadii.pill),
                        ),
                        child: const Text(
                          'BEST VALUE',
                          style: TextStyle(
                            color: LuminColors.bgDeep,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                unit,
                style: const TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _telegramCta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(LuminRadii.md),
          onTap: () => _showTelegramSheet(context),
          child: Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              color: LuminColors.accent,
              borderRadius: BorderRadius.circular(LuminRadii.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.send, color: LuminColors.bgDeep, size: 20),
                const SizedBox(width: LuminSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upgrade via Telegram',
                        style: TextStyle(
                          color: LuminColors.bgDeep,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '@LuminProBot — payment, activation, support',
                        style: TextStyle(
                          color: LuminColors.bgDeep,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, color: LuminColors.bgDeep, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTelegramSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: LuminColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: LuminColors.cardBorder,
                borderRadius: BorderRadius.circular(LuminRadii.pill),
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            const Text(
              'Open Telegram bot',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Text(
              'You will be redirected to @LuminProBot in Telegram.  '
              'There you can pick a plan, pay, and the bot will activate '
              'paid signals on your account.',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: LuminSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LuminColors.accent,
                  foregroundColor: LuminColors.bgDeep,
                  padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse('https://t.me/LuminProBot');
                  if (!await launchUrl(uri,
                      mode: LaunchMode.externalApplication)) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Could not open Telegram — install it first.'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
                child: const Text(
                  'Open @LuminProBot',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: LuminColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Text(
        'Crypto trading carries substantial risk of loss. Past signals do '
        'not guarantee future performance. Subscription billing is handled '
        'outside this app.',
        style: TextStyle(
          color: LuminColors.textMuted.withOpacity(0.85),
          fontSize: 10,
          height: 1.5,
        ),
      ),
    );
  }
}

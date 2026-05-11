/// About / Risk Disclosure — Play Store legal compliance.
///
/// Version, attribution, terms link, privacy link, and full risk-disclosure
/// content required for Google Play approval of a financial-services app.
import 'package:flutter/material.dart';

import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _version = '0.0.17';
  static const _build = 'live';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          _hero(),
          const SizedBox(height: LuminSpacing.md),
          _versionCard(),
          const SizedBox(height: LuminSpacing.md),
          _riskCard(),
          const SizedBox(height: LuminSpacing.md),
          _legalLinks(context),
          const SizedBox(height: LuminSpacing.md),
          _attribution(),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  Widget _hero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.lg),
          border: Border.all(color: LuminColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: LuminColors.accent, size: 28),
                SizedBox(width: LuminSpacing.sm),
                Text(
                  'Lumin',
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            SizedBox(height: LuminSpacing.sm),
            Text(
              'Crypto-scalping signal companion app for the 360 Crypto Eye '
              'engine.  Watch the engine pulse, browse signals, and manage '
              'auto-trade execution.',
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

  Widget _versionCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          children: [
            _kv('Version', _version),
            _kv('Build', _build),
            _kv('Engine', '360 Crypto Eye'),
            _kv('Channel', 'Telegram'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            v,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.loss.withOpacity(0.06),
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(color: LuminColors.loss.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: LuminColors.loss, size: 18),
                SizedBox(width: LuminSpacing.sm),
                Text(
                  'RISK DISCLOSURE',
                  style: TextStyle(
                    color: LuminColors.loss,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            SizedBox(height: LuminSpacing.md),
            Text(
              'Crypto-asset perpetual futures trading is highly speculative '
              'and carries a substantial risk of loss.  Leverage amplifies '
              'both gains and losses; you can lose more than your initial '
              'margin in seconds during volatile market conditions.\n\n'
              'Lumin and the 360 Crypto Eye engine provide algorithmic '
              'signals for informational purposes only.  Signals are not '
              'financial advice, are not personalised to your situation, '
              'and do not account for your risk tolerance, financial '
              'circumstances, or jurisdiction.\n\n'
              'Past performance — including any historical statistics shown '
              'in this app — is not indicative of future results.  Backtests '
              'and forward-tested figures may not reflect realistic execution '
              'cost (fees, slippage, funding) at retail order sizes.\n\n'
              'You are solely responsible for trades executed on your '
              'Binance account, whether placed manually or via the app\'s '
              'auto-trade module.  Verify every order before authorising '
              'live execution.  Never trade with capital you cannot afford '
              'to lose.',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legalLinks(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          children: [
            _link(context, Icons.description_outlined, 'Terms of Service'),
            const Divider(color: LuminColors.cardBorder, height: 1),
            _link(context, Icons.privacy_tip_outlined, 'Privacy Policy'),
            const Divider(color: LuminColors.cardBorder, height: 1),
            _link(context, Icons.gavel_outlined, 'Open-source licences'),
            const Divider(color: LuminColors.cardBorder, height: 1),
            _link(context, Icons.mail_outline, 'Contact support'),
          ],
        ),
      ),
    );
  }

  Widget _link(BuildContext context, IconData icon, String label) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label opens once site is live'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LuminSpacing.sm),
        child: Row(
          children: [
            Icon(icon, color: LuminColors.accent, size: 18),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: LuminColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _attribution() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Text(
        '© 2026 360 Crypto Eye.  All rights reserved.\n'
        'Made for scalpers, with the 15-evaluator engine.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: LuminColors.textMuted.withOpacity(0.75),
          fontSize: 10,
          height: 1.6,
        ),
      ),
    );
  }
}

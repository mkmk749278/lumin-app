/// Legal — privacy policy, terms, and risk disclosure.
///
/// Three rows that used to sit at the root of the Menu (handoff §28, moved
/// 2026-09-19). They are required to stay reachable and accurate — the Play
/// listing links the privacy policy and Settings → Legal is the in-app path —
/// but they are read once, if ever, and three permanent rows at the top level
/// cost more than the tap they save.
///
/// Each link opens the SYSTEM browser rather than an in-app WebView, per
/// Play's prominent-disclosure expectation that legal pages are reviewable
/// outside the app's own chrome. A launch failure surfaces a SnackBar rather
/// than silently doing nothing — a legal link that no-ops is indistinguishable
/// from a broken one.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/legal_urls.dart';
import '../../../shared/tokens.dart';
import '../settings_rows.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legal')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          SettingsSection(
            title: 'DOCUMENTS',
            rows: [
              SettingsRow(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                subtitle: 'What data we collect, why, and your rights',
                onTap: () => openLegalUrl(context, LegalUrls.privacyUrl),
              ),
              SettingsRow(
                icon: Icons.gavel_outlined,
                label: 'Terms of Service',
                subtitle: 'Eligibility, responsibilities, limitations',
                onTap: () => openLegalUrl(context, LegalUrls.termsUrl),
              ),
              SettingsRow(
                icon: Icons.report_problem_outlined,
                label: 'Risk Disclosure',
                subtitle: 'Crypto futures trading carries risk of loss',
                onTap: () => openLegalUrl(context, LegalUrls.riskUrl),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.lg),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: LuminSpacing.xl),
            child: Text(
              'These open in your browser. Lumin signals are informational '
              'only and are not personalised investment advice.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }
}

/// Open a legal document in the system browser, reporting a failure rather
/// than swallowing it. Shared with the root Menu's About row.
Future<void> openLegalUrl(BuildContext context, String url) async {
  final launched = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open $url'),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

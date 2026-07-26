/// Menu / Settings — root list of drill-down pages.
///
/// Lumin is consumer-only: this menu shows just the user's own
/// controls (auto-trade preferences, Binance, profile, subscription,
/// about, sign out).  Operator surfaces (engine defaults, agents,
/// risk gates, dev tools) live in the separate ops app — not here.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_config.dart';
import '../../data/legal_urls.dart';
import '../../data/repository.dart';
import '../agents/agents_page.dart';
import '../auth/pages/phone_signin_page.dart';
import '../../shared/platform_input.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/free_tier_gate.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/upsell_banners.dart';
import 'pages/about_page.dart';
import 'pages/notification_settings_page.dart';
import 'pages/server_side_execution_page.dart';
import 'pages/auto_trade_settings_page.dart';
import 'pages/invalidation_settings_page.dart';
import 'pages/pretp_settings_page.dart';
import 'pages/profile_settings_page.dart';
import 'pages/referral_page.dart';
import 'pages/subscription_page.dart';
import 'pages/symbol_preference_page.dart';
import 'pages/web_paywall_page.dart';
import '../../app/distribution.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          // Growth banners at the top of the menu — the upgrade pitch
          // auto-hides once the user reaches Auto; the invite banner shows
          // the standing reward deal (engine truth) to everyone.
          const UpgradeBanner(slot: 'menu'),
          const InviteBanner(slot: 'menu'),
          const SizedBox(height: LuminSpacing.md),
          _section(
            title: 'AUTO-TRADE',
            rows: [
              _Row(
                icon: Icons.auto_mode,
                label: 'Auto-trade',
                subtitle: 'Your sizing, leverage, mode',
                onTap: () => _push(context, const AutoTradeSettingsPage()),
              ),
              _Row(
                icon: Icons.shield_moon_outlined,
                label: 'Pre-TP grab',
                subtitle: 'Your thresholds + regime allowlist',
                onTap: () => _push(context, const PreTpSettingsPage()),
              ),
              _Row(
                icon: Icons.shield_outlined,
                label: 'Invalidation',
                subtitle: 'Loose / Standard / Tight — capital preservation',
                onTap: () =>
                    _push(context, const InvalidationSettingsPage()),
              ),
              _Row(
                icon: Icons.filter_list_alt,
                label: 'Symbol preference',
                subtitle: 'Which pairs auto-trade for you',
                onTap: () =>
                    _push(context, const SymbolPreferencePage()),
              ),
              // ``Binance`` (OLD client-side connect) menu entry REMOVED
              // 2026-05-19.  The OLD path stored keys locally and ran
              // ``AutoTradeWatcher`` in-app; server-side execution
              // (Settings → Server-side auto-trade) replaces it entirely.
              // The corresponding ``api_keys_settings_page.dart`` +
              // ``auto_trade_watcher.dart`` + ``auto_trade_indicator.dart``
              // files were deleted in the same PR.
              _Row(
                icon: Icons.cloud_done_outlined,
                label: 'Server-side auto-trade',
                subtitle: '24/7 execution from Lumin\'s engine (B18)',
                onTap: () =>
                    _push(context, const ServerSideExecutionPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          _section(
            title: 'INSIGHTS',
            rows: [
              _Row(
                icon: Icons.psychology_outlined,
                label: 'AI agents',
                subtitle: 'The 15 setup specialists + their live stats',
                onTap: () => _push(context, const AgentsPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          _section(
            title: 'ACCOUNT',
            rows: [
              _Row(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                subtitle: 'Push for signals + market alerts',
                onTap: () =>
                    _push(context, const NotificationSettingsPage()),
              ),
              _Row(
                icon: Icons.person_outline,
                label: 'Profile',
                subtitle: 'Name, country, display currency',
                onTap: () => _push(context, const ProfileSettingsPage()),
              ),
              // Live plan subtitle — reads the cached tier under a
              // tierRevision listener so a purchase (or the cold-start
              // hydration) updates the row without leaving the tab.
              ValueListenableBuilder<int>(
                valueListenable: AppConfigScope.of(context).tierRevision,
                builder: (context, _, __) {
                  final tier = AppConfigScope.of(context).tier;
                  final subtitle = switch (tierRank(tier)) {
                    >= 3 => 'All Access — every feature unlocked',
                    2 => 'Auto plan — hands-off auto-trading',
                    1 => 'Assist plan — one-tap trades',
                    _ => 'Free — upgrade to automate trades',
                  };
                  return _Row(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Subscription',
                    subtitle: subtitle,
                    onTap: () => _push(
                      context,
                      // Web sells the tiers via crypto/manual (Play Billing is
                      // store-bound); native builds keep Play Billing.
                      kDistribution == AppDistribution.web
                          ? const WebPaywallPage()
                          : const SubscriptionPage(),
                    ),
                  );
                },
              ),
              _Row(
                icon: Icons.person_add_alt_1_outlined,
                label: 'Invite a friend',
                subtitle: 'Earn rewards when friends join — they get a discount',
                onTap: () => _push(context, const ReferralPage()),
              ),
              _Row(
                icon: Icons.info_outline,
                label: 'About',
                subtitle: 'Version, terms, risk disclosure',
                onTap: () => _push(context, const AboutPage()),
              ),
              _Row(
                icon: Icons.logout,
                label: 'Sign out',
                subtitle: 'Wipes the cached token; phone signin again next launch',
                destructive: true,
                onTap: () => _signOut(context),
              ),
              // Delete account (Play Store launch A4-partial,
              // 2026-05-20) — required by Google's User Data policy
              // (answer/13327111).  Calls DELETE /api/account which
              // revokes the Binance key blob, deletes the SQLite
              // user row (cascades override tables), and invalidates
              // the dispatch cache.  See ``_deleteAccount`` below
              // for the confirmation + post-success flow.
              _Row(
                icon: Icons.delete_forever_outlined,
                label: 'Delete account',
                subtitle: 'Permanently remove your account + revoke API keys',
                destructive: true,
                onTap: () => _deleteAccount(context),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          // Legal section (Play Store launch A5, 2026-05-20) — three
          // direct links to the hosted lumin-legal documents.  Each
          // opens the device browser via ``url_launcher``; on launch
          // failure we surface a SnackBar rather than silently no-op'ing.
          _section(
            title: 'LEGAL',
            rows: [
              _Row(
                icon: Icons.privacy_tip_outlined,
                label: 'Privacy Policy',
                subtitle: 'What data we collect, why, your rights',
                onTap: () => _openExternalUrl(context, LegalUrls.privacyUrl),
              ),
              _Row(
                icon: Icons.gavel_outlined,
                label: 'Terms of Service',
                subtitle: 'Eligibility, responsibilities, limitations',
                onTap: () => _openExternalUrl(context, LegalUrls.termsUrl),
              ),
              _Row(
                icon: Icons.report_problem_outlined,
                label: 'Risk Disclosure',
                subtitle: 'Crypto futures trading carries risk of loss',
                onTap: () => _openExternalUrl(context, LegalUrls.riskUrl),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  Future<void> _openExternalUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    // ``mode: externalApplication`` opens the system browser instead
    // of a WebView inside the app — required for Privacy / ToS / Risk
    // links per Play Store's prominent-disclosure expectations
    // (legal pages should be reviewable outside the app's own UI
    // chrome).
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $url'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _section({required String title, required List<Widget> rows}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: LuminSpacing.sm,
              bottom: LuminSpacing.sm,
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          LuminCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (int i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1)
                    const Divider(
                      color: LuminColors.cardBorder,
                      height: 1,
                      indent: 56,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: const Text(
          'Sign out?',
          style: TextStyle(color: LuminColors.textPrimary),
        ),
        content: const Text(
          'You\'ll need to verify your phone again on next launch.  Your '
          'Binance keys stay on the device — you can pick up where you '
          'left off when you sign back in with the same phone.',
          style: TextStyle(color: LuminColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: LuminColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign out',
              style: TextStyle(
                color: LuminColors.loss,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    final scope = AppConfigScope.of(context);
    await scope.resetConnection();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneSignInPage()),
      (_) => false,
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    // Two-step confirmation: this is irreversible.  The user must
    // type "DELETE" to confirm — a more intentional gate than a
    // tap-Yes dialog.  Matches the Cornix / Bitsgap pattern.
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteAccountDialog(),
    );
    if (confirm != true) return;
    if (!context.mounted) return;

    // Show a blocking spinner while the round-trip runs.  Server
    // can take 1-3 seconds (Firestore blob delete + SQLite + cache).
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeletingSpinner(),
    );

    final scope = AppConfigScope.of(context);
    try {
      await scope.repo.deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context).pop();  // dismiss the spinner
      // Now wipe local auth state — secure-storage tokens, SharedPrefs,
      // cached user info — and route back to the welcome screen.
      // ``resetConnection`` is the same path the sign-out flow uses.
      await scope.resetConnection();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PhoneSignInPage()),
        (_) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deleted. You can sign up again any time.'),
          duration: Duration(seconds: 4),
        ),
      );
    } on DeleteAccountException catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();  // dismiss the spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();  // dismiss the spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete account: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }
}

/// Two-step confirmation dialog — user must type "DELETE" to enable
/// the Delete button.  This is a more intentional gate than the
/// usual two-button OK-Cancel because the action is irreversible
/// (revokes the Binance key + drops the SQLite row + all per-user
/// preferences cascade with it).
class _DeleteAccountDialog extends StatefulWidget {
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _canDelete = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!mounted) return;
      final ok = _controller.text.trim().toUpperCase() == 'DELETE';
      if (ok != _canDelete) setState(() => _canDelete = ok);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LuminColors.bgCard,
      title: const Text(
        'Delete account?',
        style: TextStyle(color: LuminColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This will permanently:\n'
            '\n'
            '  • Revoke your Binance API key on our server\n'
            '  • Delete your account and all per-user settings\n'
            '  • Sign you out of this device\n'
            '\n'
            'Your funds on Binance are NOT affected — only the trade-only '
            'API key authorisation we held is revoked. You can sign up '
            'again later with the same phone number.\n'
            '\n'
            'Type DELETE below to confirm.',
            style: TextStyle(color: LuminColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: LuminSpacing.md),
          TextField(
            controller: _controller,
            autofocus: kAutofocusTextFields,
            decoration: const InputDecoration(
              hintText: 'Type DELETE',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: LuminColors.textPrimary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: LuminColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed:
              _canDelete ? () => Navigator.pop(context, true) : null,
          child: Text(
            'Delete account',
            style: TextStyle(
              color: _canDelete ? LuminColors.loss : LuminColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _DeletingSpinner extends StatelessWidget {
  const _DeletingSpinner();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LuminColors.bgCard,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: LuminColors.accent,
            ),
          ),
          SizedBox(width: LuminSpacing.md),
          Text(
            'Deleting account...',
            style: TextStyle(color: LuminColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final fg = destructive ? LuminColors.loss : LuminColors.accent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.md,
          vertical: LuminSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: fg.withOpacity(0.10),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: fg, size: 18),
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: destructive
                          ? LuminColors.loss
                          : LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: LuminColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

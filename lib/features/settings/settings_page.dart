/// Menu / Settings — root list of drill-down pages.
///
/// Lumin is consumer-only: this menu shows just the user's own
/// controls (auto-trade preferences, Binance, profile, subscription,
/// about, sign out).  Operator surfaces (engine defaults, agents,
/// risk gates, dev tools) live in the separate ops app — not here.
///
/// **Restructured 2026-09-19 (handoff §27-§29).** This list had grown to
/// sixteen rows under four headings, with two promotional banners above all
/// of them — so the first screen of the Menu contained no settings at all,
/// and the first row a user reached was `Pre-TP grab`. Two changes:
///
///  * **The five auto-trade pages collapsed to one row.** They now live
///    behind `Auto-trade & execution` ([TradingSettingsPage]), and the three
///    legal links behind `Legal` ([LegalPage]). Nothing was removed and
///    nothing is more than one extra tap away; the root list went from
///    sixteen rows to ten, ordered by what a user needs on day one rather
///    than by subsystem.
///  * **The banners moved below the settings.** They still pitch, and the
///    dismissal still works — they simply no longer stand between the user
///    and the reason they opened the Menu.
import 'package:flutter/material.dart';

import '../../app/scroll_to_top.dart';
import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../agents/agents_page.dart';
import '../auth/pages/phone_signin_page.dart';
import '../../shared/platform_input.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/free_tier_gate.dart';
import '../../shared/widgets/upsell_banners.dart';
import 'pages/about_page.dart';
import 'pages/legal_page.dart';
import 'pages/notification_settings_page.dart';
import 'pages/profile_settings_page.dart';
import 'pages/referral_page.dart';
import 'pages/subscription_page.dart';
import 'pages/trading_settings_page.dart';
import 'pages/web_paywall_page.dart';
import 'settings_rows.dart';
import '../../app/distribution.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> implements ScrollToTop {
  /// Stateful only so the Menu can honour a tap on its own already-active
  /// bottom-nav icon, like the other four tabs (see `ScrollToTop`). The page
  /// itself still holds no state.
  final ScrollController _listController = ScrollController();

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  void scrollToTop() {
    if (!_listController.hasClients) return;
    _listController.animateTo(
      0,
      duration: kScrollToTopDuration,
      curve: kScrollToTopCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        controller: _listController,
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          SettingsSection(
            title: 'ACCOUNT',
            rows: [
              SettingsRow(
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
                  return SettingsRow(
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
              SettingsRow(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                subtitle: 'Push for signals and market alerts',
                onTap: () => _push(context, const NotificationSettingsPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          // One row for what used to be five. Sizing, leverage, execution
          // mode, the exchange connection and the three trading preferences
          // all live behind it — see [TradingSettingsPage] for why.
          SettingsSection(
            title: 'TRADING',
            rows: [
              SettingsRow(
                icon: Icons.auto_mode,
                label: 'Auto-trade & execution',
                subtitle: 'Sizing, leverage, exchange connection, preferences',
                onTap: () => _push(context, const TradingSettingsPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          SettingsSection(
            title: 'INTELLIGENCE',
            rows: [
              SettingsRow(
                icon: Icons.psychology_outlined,
                label: 'AI agents',
                // No count. This row cannot ask the engine how many
                // setups it runs, and the 15 it used to quote was
                // kAgents.length — the size of this build's
                // DESCRIPTION table, against 29 live setup classes
                // measured 2026-09-21. The destination page walks the
                // engine's own roster and carries the real number.
                subtitle: 'The setup specialists and their live stats',
                onTap: () => _push(context, const AgentsPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          SettingsSection(
            title: 'SUPPORT',
            rows: [
              SettingsRow(
                icon: Icons.info_outline,
                label: 'About',
                subtitle: 'App version and what Lumin does',
                onTap: () => _push(context, const AboutPage()),
              ),
              SettingsRow(
                icon: Icons.gavel_outlined,
                label: 'Legal',
                subtitle: 'Privacy, terms, and risk disclosure',
                onTap: () => _push(context, const LegalPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          SettingsSection(
            title: 'MORE',
            rows: [
              SettingsRow(
                icon: Icons.person_add_alt_1_outlined,
                label: 'Invite & earn',
                subtitle: 'Earn rewards when friends join — they get a discount',
                onTap: () => _push(context, const ReferralPage()),
              ),
              SettingsRow(
                icon: Icons.logout,
                label: 'Sign out',
                subtitle: 'You will verify your phone again next launch',
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
              SettingsRow(
                icon: Icons.delete_forever_outlined,
                label: 'Delete account',
                subtitle: 'Permanently remove your account and revoke API keys',
                destructive: true,
                onTap: () => _deleteAccount(context),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.lg),
          // Growth banners, BELOW the settings rather than above them. The
          // upgrade pitch auto-hides once the user reaches Auto; the invite
          // banner shows the standing reward deal (engine truth) to everyone.
          // They used to occupy the entire first screen of this tab, so a user
          // who opened the Menu to change a setting saw two adverts and no
          // settings (handoff §6 / §27).
          const UpgradeBanner(slot: 'menu'),
          const InviteBanner(slot: 'menu'),
          const SizedBox(height: LuminSpacing.xl),
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

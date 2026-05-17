/// Menu / Settings — root list of drill-down pages.
///
/// Lumin is consumer-only: this menu shows just the user's own
/// controls (auto-trade preferences, Binance, profile, subscription,
/// about, sign out).  Operator surfaces (engine defaults, agents,
/// risk gates, dev tools) live in the separate ops app — not here.
import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../auth/pages/phone_signin_page.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import 'pages/about_page.dart';
import 'pages/api_keys_settings_page.dart';
import 'pages/auto_trade_settings_page.dart';
import 'pages/invalidation_settings_page.dart';
import 'pages/pretp_settings_page.dart';
import 'pages/profile_settings_page.dart';
import 'pages/subscription_page.dart';

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
                icon: Icons.account_balance_outlined,
                label: 'Binance',
                subtitle: 'Connect your Futures API keys',
                onTap: () => _push(context, const ApiKeysSettingsPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          _section(
            title: 'ACCOUNT',
            rows: [
              _Row(
                icon: Icons.person_outline,
                label: 'Profile',
                subtitle: 'Name, country, display currency',
                onTap: () => _push(context, const ProfileSettingsPage()),
              ),
              _Row(
                icon: Icons.workspace_premium_outlined,
                label: 'Subscription',
                subtitle: 'Free / Pro tiers',
                onTap: () => _push(context, const SubscriptionPage()),
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
            ],
          ),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  Widget _section({required String title, required List<_Row> rows}) {
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
    // Stop the auto-trade watcher first so it doesn't tick against
    // a stale userId after the JWT is wiped.
    scope.autoTradeWatcher.stop();
    await scope.resetConnection();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneSignInPage()),
      (_) => false,
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

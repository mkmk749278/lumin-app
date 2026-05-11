/// Menu / Settings — root list of drill-down pages.
///
/// Each row pushes a self-contained settings page where the user can edit
/// the relevant subsystem.  No setting persists across sessions yet — that
/// lands when the FastAPI backend ships.
import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import 'pages/about_page.dart';
import 'pages/agents_settings_page.dart';
import 'pages/api_keys_settings_page.dart';
import 'pages/auto_trade_settings_page.dart';
import 'pages/engine_defaults_page.dart';
import 'pages/pretp_settings_page.dart';
import 'pages/risk_gates_settings_page.dart';
import 'pages/subscription_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    // Owner-only entry-points.  When ``tier`` is null (mock mode,
    // pre-Phase-2 JWT) we show the row too — the engine still gates
    // writes server-side, so a non-owner who somehow opens the page
    // can read but not edit.
    final isOwner = scope.tier == null || scope.tier == 'owner';
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          _section(
            title: 'EXECUTION',
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
                label: 'Risk gates',
                subtitle: 'Daily-loss kill, leverage, equity floor',
                onTap: () => _push(context, const RiskGatesSettingsPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          _section(
            title: 'ENGINE',
            rows: [
              if (isOwner)
                _Row(
                  icon: Icons.settings_input_component_outlined,
                  label: 'Engine defaults',
                  subtitle: 'Owner — engine-wide pre-TP + auto-mode',
                  onTap: () => _push(context, const EngineDefaultsPage()),
                ),
              _Row(
                icon: Icons.psychology_outlined,
                label: 'Agents',
                subtitle: '15 evaluators — per-agent toggles',
                onTap: () => _push(context, const AgentsSettingsPage()),
              ),
              _Row(
                icon: Icons.vpn_key_outlined,
                label: 'API keys',
                subtitle: 'Binance Futures credentials',
                onTap: () => _push(context, const ApiKeysSettingsPage()),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          _section(
            title: 'ACCOUNT',
            rows: [
              _Row(
                icon: Icons.workspace_premium_outlined,
                label: 'Subscription',
                subtitle: 'Free / Pro tiers',
                onTap: () => _push(context, const SubscriptionPage()),
              ),
              _Row(
                icon: Icons.palette_outlined,
                label: 'Appearance',
                subtitle: 'Dark mode (always on for now)',
                onTap: () => _stub(context, 'Appearance'),
              ),
              _Row(
                icon: Icons.translate_outlined,
                label: 'Language',
                subtitle: 'English',
                onTap: () => _stub(context, 'Language'),
              ),
              _Row(
                icon: Icons.info_outline,
                label: 'About',
                subtitle: 'Version, terms, risk disclosure',
                onTap: () => _push(context, const AboutPage()),
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

  void _stub(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label — not yet implemented'),
        duration: const Duration(seconds: 2),
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
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                color: LuminColors.accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: LuminColors.accent, size: 18),
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
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
            const Icon(Icons.chevron_right, color: LuminColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

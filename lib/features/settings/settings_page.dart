import 'package:flutter/material.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        physics: const BouncingScrollPhysics(),
        children: [
          LuminCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: const [
                  Icon(Icons.account_circle_outlined, color: LuminColors.accent),
                  SizedBox(width: LuminSpacing.md),
                  Text('Mulakapati Kishore Kumar', style: TextStyle(color: LuminColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
                ]),
                const SizedBox(height: LuminSpacing.sm),
                Padding(padding: const EdgeInsets.only(left: 32), child: Text('Telegram identity • Free tier', style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          ),
          const SizedBox(height: LuminSpacing.lg),
          _SectionHeader('Trading'),
          _SettingsRow(icon: Icons.swap_horiz_outlined, title: 'Auto-trade', subtitle: 'Off / Paper / Live mode'),
          _SettingsRow(icon: Icons.bolt_outlined, title: 'Pre-TP grab', subtitle: 'Threshold, ATR multiplier, fee floor'),
          _SettingsRow(icon: Icons.shield_outlined, title: 'Risk gates', subtitle: 'Daily-loss kill, leverage cap, exposure'),
          _SettingsRow(icon: Icons.code_outlined, title: 'Agents', subtitle: 'Per-path enable / custom thresholds'),
          const SizedBox(height: LuminSpacing.lg),
          _SectionHeader('Account'),
          _SettingsRow(icon: Icons.key_outlined, title: 'API keys', subtitle: 'Binance Futures (encrypted)'),
          _SettingsRow(icon: Icons.subscriptions_outlined, title: 'Subscription', subtitle: 'Free → Pro via Telegram bot'),
          const SizedBox(height: LuminSpacing.lg),
          _SectionHeader('App'),
          _SettingsRow(icon: Icons.dark_mode_outlined, title: 'Appearance', subtitle: 'Dark (default)'),
          _SettingsRow(icon: Icons.translate_outlined, title: 'Language', subtitle: 'English'),
          _SettingsRow(icon: Icons.info_outline, title: 'About', subtitle: 'Lumin v0.0.2 — Powered by 360 Crypto Eye'),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: LuminSpacing.sm, bottom: LuminSpacing.sm),
      child: Text(text.toUpperCase(), style: const TextStyle(color: LuminColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminSpacing.sm),
      child: LuminCard(
        padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg, vertical: LuminSpacing.md),
        onTap: () => _showComingSoon(context),
        child: Row(
          children: [
            Icon(icon, color: LuminColors.accent, size: 22),
            const SizedBox(width: LuminSpacing.lg),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: LuminColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            )),
            const Icon(Icons.chevron_right, color: LuminColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: LuminColors.bgElevated,
        content: Text('$title — coming with the next backend ship.', style: const TextStyle(color: LuminColors.textPrimary)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

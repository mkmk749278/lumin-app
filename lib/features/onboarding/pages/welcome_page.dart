/// Welcome page — first-launch brand intro + value-prop.
///
/// Shows ONCE per device, immediately on first app launch (before
/// the consent gate, before phone signin).  Persists via
/// ``ConsentStorage.welcomeSeen``.  Subsequent launches skip
/// straight to the consent gate (or, if already consented, the
/// auth gate).
///
/// Why a separate page from the consent gate:
///
/// * **Different jobs.**  Welcome is brand intro + value-prop —
///   make the user think "OK, this looks legit, I want to try it."
///   Consent is a legal acknowledgement — "I understand the risks."
///   Mixing them puts the risk language on a screen the user is
///   trying to be excited about; bad UX both ways.
/// * **One-shot vs. version-bumped.**  Welcome shows once and
///   never re-shows.  Consent re-shows when ``currentConsentVersion``
///   bumps (material disclosure changes) — and showing the welcome
///   page to an existing user on every consent update would feel
///   like a UX regression.
library;

import 'package:flutter/material.dart';

import '../../../data/consent_storage.dart';
import '../../../shared/tokens.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.onContinue});

  /// Called after the user taps "Get Started".  Parent typically
  /// calls ``setState`` to swap in the next route (consent gate →
  /// auth gate → nav shell).
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.lg,
            vertical: LuminSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),

              // Brand mark — same cyan accent the app icon uses.
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: LuminColors.accent,
                  borderRadius: BorderRadius.circular(LuminRadii.lg),
                ),
                child: const Center(
                  child: Text(
                    'L',
                    style: TextStyle(
                      color: LuminColors.bgDeep,
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: LuminSpacing.xl),

              // Hero title.
              const Text(
                'Welcome to Lumin',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: LuminSpacing.md),

              // Value-prop subtitle.
              const Text(
                'Crypto futures trading signals + Binance automation.',
                style: TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: LuminSpacing.xl),

              // Three-bullet feature snapshot — what the user gets.
              _featureRow(
                Icons.bolt_outlined,
                'Real-time signals',
                '24/7 scanning of 75 Binance USDT-M futures pairs',
              ),
              _featureRow(
                Icons.auto_mode_outlined,
                'Optional auto-trade',
                'Server-side execution on your Binance account',
              ),
              _featureRow(
                Icons.shield_outlined,
                'Non-custodial',
                'Trade-only key. Your funds stay on Binance.',
              ),

              const Spacer(flex: 3),

              // Primary CTA.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await ConsentStorage.recordWelcomeSeen();
                    onContinue();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LuminColors.accent,
                    foregroundColor: LuminColors.bgDeep,
                    padding: const EdgeInsets.symmetric(
                      vertical: LuminSpacing.lg,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(LuminRadii.md),
                    ),
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: LuminSpacing.md),

              // Small disclaimer below the CTA — sets honest expectation
              // before the user reaches the consent gate (which spells
              // out the risk in full).
              const Center(
                child: Text(
                  '18+ • Crypto futures trading carries risk of loss',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: LuminColors.bgCard,
              borderRadius: BorderRadius.circular(LuminRadii.sm),
              border: Border.all(color: LuminColors.cardBorder),
            ),
            child: Icon(icon, color: LuminColors.accent, size: 22),
          ),
          const SizedBox(width: LuminSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 13,
                    height: 1.3,
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

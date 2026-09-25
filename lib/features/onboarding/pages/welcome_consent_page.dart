/// Welcome + consent gate — first-run screen for fresh installs and
/// for any release that bumps ``ConsentStorage.currentConsentVersion``.
///
/// This single screen covers the two Play Store first-run requirements
/// (per the PLAYSTORE_PLAN.md execution doc):
///
/// * **Age affirmation (18+):** owner-prudent for a leveraged crypto
///   product even though IARC content rating doesn't require it.
/// * **Risk disclosure + "not financial advice":** mandated by the
///   Financial Services policy
///   (https://support.google.com/googleplay/android-developer/answer/9876821)
///   for any app surfacing financial signals.  Cornix, 3Commas, and
///   Bitsgap all run a structurally identical first-run gate.
///
/// Design choices:
///
/// * **Three checkboxes, one button.**  Continue is disabled until all
///   three are ticked.  Single-button pattern means the user can't
///   accidentally tap-through.
/// * **Vocabulary discipline.**  Per the PLAYSTORE_PLAN copy rules,
///   this screen uses "signals", "automation", "may lose funds" —
///   never "advice", "guaranteed", "returns".
/// * **No "back" / "skip".**  This is a hard gate; without consent the
///   app does not proceed.  Closing the app and reopening will re-show
///   the gate (consent only persists after the affirmative tap).
library;

import 'package:flutter/material.dart';

import '../../../data/consent_storage.dart';
import '../../../shared/tokens.dart';

class WelcomeConsentPage extends StatefulWidget {
  const WelcomeConsentPage({super.key, required this.onAccepted});

  /// Called after the user ticks all three boxes and taps Continue.
  /// The parent typically calls ``setState`` to swap in the next route
  /// (auth gate / nav shell).
  final VoidCallback onAccepted;

  @override
  State<WelcomeConsentPage> createState() => _WelcomeConsentPageState();
}

class _WelcomeConsentPageState extends State<WelcomeConsentPage> {
  bool _age = false;
  bool _risk = false;
  bool _notAdvice = false;
  bool _busy = false;

  bool get _canContinue => _age && _risk && _notAdvice && !_busy;

  int get _remaining => [_age, _risk, _notAdvice].where((v) => !v).length;

  Future<void> _continue() async {
    if (!_canContinue) return;
    setState(() => _busy = true);
    await ConsentStorage.recordAccepted();
    if (!mounted) return;
    widget.onAccepted();
  }

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
              const SizedBox(height: LuminSpacing.lg),
              const Text(
                'Welcome to Lumin',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: LuminSpacing.sm),
              const Text(
                'Crypto futures trading signals and automation.',
                style: TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: LuminSpacing.xl),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _confirmTile(
                        value: _age,
                        onChanged: (v) => setState(() => _age = v ?? false),
                        text:
                            'I am 18 years of age or older and legally permitted to trade crypto futures in my country of residence.',
                      ),
                      _confirmTile(
                        value: _risk,
                        onChanged: (v) => setState(() => _risk = v ?? false),
                        text:
                            'I understand that crypto futures trading carries substantial risk of loss. I may lose some or all of the funds I deploy. Past performance does not guarantee future results.',
                      ),
                      _confirmTile(
                        value: _notAdvice,
                        onChanged: (v) =>
                            setState(() => _notAdvice = v ?? false),
                        text:
                            'I understand that Lumin signals are informational only and are NOT personalised investment advice. I am solely responsible for my own trading decisions and any funds in my Binance account.',
                      ),
                    ],
                  ),
                ),
              ),
              // A disabled button with no reason reads as broken. Say what is
              // still needed, in the count the user can act on.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _remaining == 0
                    ? const SizedBox(height: LuminSpacing.md)
                    : Padding(
                        key: ValueKey(_remaining),
                        padding: const EdgeInsets.only(bottom: LuminSpacing.sm),
                        child: Center(
                          child: Text(
                            _remaining == 3
                                ? 'Tick all 3 boxes to continue'
                                : _remaining == 1
                                    ? 'Tick 1 more box to continue'
                                    : 'Tick $_remaining more boxes to continue',
                            style: const TextStyle(
                              color: LuminColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canContinue ? _continue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LuminColors.accent,
                    foregroundColor: LuminColors.bgDeep,
                    disabledBackgroundColor: LuminColors.bgElevated,
                    disabledForegroundColor: LuminColors.textMuted,
                    padding:
                        const EdgeInsets.symmetric(vertical: LuminSpacing.lg),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(LuminRadii.md),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LuminColors.bgDeep,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmTile({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String text,
  }) {
    // Each confirmation reads as a card that fills in when ticked. The
    // checkbox used to override the theme's border with `cardBorder` — a
    // 10%-alpha cyan on navy — so the first three controls a new user must
    // find were close to invisible (2026-09-23 audit, measured on the live
    // site). The theme's `checkboxTheme` border is what renders now.
    return Padding(
      padding: const EdgeInsets.only(bottom: LuminSpacing.md),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(LuminRadii.md),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              color: value
                  ? LuminColors.accent.withValues(alpha: 0.08)
                  : LuminColors.bgCard,
              borderRadius: BorderRadius.circular(LuminRadii.md),
              border: Border.all(
                color: value
                    ? LuminColors.accent.withValues(alpha: 0.6)
                    : LuminColors.cardBorder,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(value: value, onChanged: onChanged),
                const SizedBox(width: LuminSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: LuminSpacing.md),
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

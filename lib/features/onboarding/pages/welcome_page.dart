/// Welcome — the ONE screen before the app (owner, 2026-09-25).
///
/// *"Make everything access as guest login without asking anything from
/// user, just one welcome screen and enter into app, no more scary
/// warnings."*  So this is a single screen with one button.  "Get Started"
/// records the welcome AND the terms acceptance (the one line under the
/// button is that acceptance, in one tap), and the gate then signs the
/// visitor in as a guest — no phone number, no checkboxes.
///
/// The three-checkbox consent page and the two extra slides are gone from
/// the first run.  The risk and terms text still exist, behind the links in
/// the line under the button and in Menu → Legal; what went is the wall of
/// them in front of the product.  The owner agreed to keep the one line:
/// an 18+ / terms acknowledgement is what Play's financial-services policy
/// and the ASCI crypto guidance expect before anyone reads a signal.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/consent_storage.dart';
import '../../../data/legal_urls.dart';
import '../../../shared/tokens.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  /// True once "Get Started" has been accepted.  Guards against a second
  /// tap arriving while the flags are being written firing
  /// [WelcomePage.onContinue] twice.
  bool _finishing = false;

  Future<void> _done() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ConsentStorage.recordWelcomeSeen();
    await ConsentStorage.recordAccepted();
    if (!mounted) return;
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      body: SafeArea(child: _Slide1(onDone: _done)),
    );
  }
}

/// The shared frame every slide lays out in.
///
/// Added 2026-09-24.  Each slide is a Column spread with Spacers (and slide
/// 1's card sits in an Expanded), which fills a tall phone exactly and
/// OVERFLOWS a short one: measured 85px at 360x640 and 164px at 320x568 —
/// the bottom of the column, i.e. the CTA, under the yellow-black stripe.
/// This makes the slide scroll only when its content is taller than the
/// screen: on a phone where it fits, `minHeight` pins the column to the
/// viewport and every Spacer behaves exactly as before.
class _SlideFrame extends StatelessWidget {
  const _SlideFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                LuminSpacing.xl, LuminSpacing.xxl, LuminSpacing.xl, 80,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The screen
// ---------------------------------------------------------------------------

class _Slide1 extends StatelessWidget {
  const _Slide1({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return _SlideFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand mark
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: LuminColors.accent,
              borderRadius: BorderRadius.circular(LuminRadii.lg),
            ),
            child: const Center(
              child: Text(
                'L',
                style: TextStyle(
                  color: LuminColors.bgDeep,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),

          // The product, shown rather than described. This slide used to
          // leave ~55% of the screen empty between the brand mark and the
          // headline (measured on the live site, 2026-09-23) -- the first
          // screen ad traffic lands on. `scaleDown` lets the card shrink on
          // short phones instead of overflowing the column.
          //
          // Anchored low (UX review 2026-09-25): centred, a tall phone left two
          // equal empty bands, one of them splitting the card from the
          // headline it illustrates. The spare height now sits under the
          // brand mark and the card reads as part of the pitch.
          const Expanded(
            child: Align(
              alignment: Alignment(0, 0.7),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: ExampleSignalCard(),
              ),
            ),
          ),

          // Copy states the MECHANISM, never an outcome (2026-08-05).  The
          // previous headline — "Signals that close in profit." — asserted a
          // result the recorded book does not support, contradicted the
          // risk consent the user ticks two screens later, and is exactly
          // the guaranteed-return language Play's financial-services policy
          // treats as a listing risk.  Never restate an outcome here.
          const Text(
            'Every signal.\nEntry, stop, target.',
            style: TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          const Text(
            'AI-powered USDT futures signals with '
            'automatic execution on your Binance account.',
            style: TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const SizedBox(height: LuminSpacing.lg),

          // Proof chips
          Wrap(
            spacing: LuminSpacing.sm,
            runSpacing: LuminSpacing.sm,
            children: const [
              _StatChip(label: '75+ pairs', icon: Icons.radar_outlined),
              // No count. This screen runs BEFORE auth, so it has no
              // repository and cannot read the live roster — any number
              // here is a constant asserting a property of a moving
              // system. '15' came from kAgents.length, which is a
              // DESCRIPTION table; the engine was running 29 setup
              // classes when this was measured (2026-09-21), so the
              // first claim a prospective subscriber read understated
              // the product by half. The Agents page, which CAN ask the
              // engine, is where the real count belongs.
              _StatChip(label: 'AI analysts', icon: Icons.smart_toy_outlined),
              _StatChip(label: 'Paper mode first', icon: Icons.science_outlined),
            ],
          ),

          const SizedBox(height: LuminSpacing.xl),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LuminColors.accent,
                foregroundColor: LuminColors.bgDeep,
                padding: const EdgeInsets.symmetric(vertical: LuminSpacing.lg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LuminRadii.md),
                ),
              ),
              onPressed: onDone,
              child: const Text(
                'Get Started',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          const _TermsLine(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

/// The one line under the button: continuing is accepting.  Terms and Risk
/// open the published documents, which are the same ones Menu → Legal
/// links to.
class _TermsLine extends StatelessWidget {
  const _TermsLine();

  static void _open(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: LuminColors.textMuted, fontSize: 11, height: 1.4);
    const link = TextStyle(
      color: LuminColors.textSecondary,
      fontSize: 11,
      decoration: TextDecoration.underline,
    );
    return Center(
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'Continue karke aap confirm karte ho ki aap 18+ ho aur '),
            TextSpan(
              text: 'Terms',
              style: link,
              recognizer: TapGestureRecognizer()..onTap = () => _open(LegalUrls.termsUrl),
            ),
            const TextSpan(text: ' & '),
            TextSpan(
              text: 'Risk',
              style: link,
              recognizer: TapGestureRecognizer()..onTap = () => _open(LegalUrls.riskUrl),
            ),
            const TextSpan(text: ' padh liye hain.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.md,
        vertical: LuminSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.pill),
        border: Border.all(color: LuminColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: LuminColors.accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// What a Lumin signal looks like, drawn with the app's own tokens.
///
/// Labelled EXAMPLE and captioned as an illustration, and it carries **no
/// outcome** — no PnL, no win rate, no "hit TP". This screen runs before
/// sign-in and cannot read the engine, so any performance figure here would
/// be invented, and the headline beside it promises the mechanism (entry,
/// stop, target), not a result. The levels are round illustrative numbers.
class ExampleSignalCard extends StatefulWidget {
  const ExampleSignalCard({super.key});

  @override
  State<ExampleSignalCard> createState() => _ExampleSignalCardState();
}

class _ExampleSignalCardState extends State<ExampleSignalCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _ctl, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
            .animate(curve),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 320,
              padding: const EdgeInsets.all(LuminSpacing.lg),
              decoration: BoxDecoration(
                color: LuminColors.bgCard,
                borderRadius: BorderRadius.circular(LuminRadii.lg),
                border: Border.all(color: LuminColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: LuminColors.accent.withValues(alpha: 0.10),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'BTCUSDT',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: LuminColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: LuminSpacing.sm),
                      _pill('LONG', LuminColors.success),
                      const Spacer(),
                      const SizedBox(width: LuminSpacing.sm),
                      _pill('EXAMPLE', LuminColors.textMuted),
                    ],
                  ),
                  const SizedBox(height: LuminSpacing.md),
                  _level('Entry', '64,000.0', LuminColors.textPrimary),
                  _level('Stop', '63,200.0', LuminColors.loss),
                  _level('Target', '65,000.0', LuminColors.success),
                ],
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Text(
              'Illustration — not a live signal',
              style: TextStyle(color: LuminColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(LuminRadii.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );

  static Widget _level(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

/// Welcome intro — 3 swipeable slides shown once on first launch.
///
/// Replaces the old single-screen static page.  Goal: make the user
/// want the product before they see the consent gate or sign-in form.
///
/// Flow:
///   Slide 1 → Hook (headline + proof stats)
///   Slide 2 → How it works (3-step visual)
///   Slide 3 → Safety + "Get Started" CTA
///
/// Skip button (top-right) skips to the CTA on slide 3 from any earlier
/// slide.  Progress dots track position.  "Get Started" on slide 3
/// records welcomeSeen and calls [onContinue].
library;

import 'package:flutter/material.dart';

import '../../../data/consent_storage.dart';
import '../../../shared/tokens.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _controller = PageController();
  int _page = 0;
  static const _lastPage = 2;

  /// True once "Get Started" has been accepted.  Guards against a second
  /// tap arriving while [ConsentStorage.recordWelcomeSeen] is in flight
  /// firing [WelcomePage.onContinue] twice.
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Advances one slide, or finishes on the last one.
  ///
  /// `_page` is bumped optimistically rather than waiting for
  /// `onPageChanged` (2026-07-26 iPhone setup-screen fix).  `onPageChanged`
  /// only fires when the 300ms scroll animation crosses the halfway point,
  /// so a second CTA tap inside that window used to read a stale `_page`
  /// and re-target the slide the carousel was already animating to — the
  /// tap did nothing visible, which on iOS Safari (where the frame budget
  /// makes that window feel long) is exactly the "pressed it and nothing
  /// happened" symptom.  Tracking the intent means consecutive taps queue
  /// up one slide each.
  void _next() {
    if (_finishing) return;
    if (_page < _lastPage) {
      final target = _page + 1;
      setState(() => _page = target);
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _done();
    }
  }

  void _skipToLast() {
    if (_finishing || _page == _lastPage) return;
    setState(() => _page = _lastPage);
    _controller.animateToPage(
      _lastPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _done() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await ConsentStorage.recordWelcomeSeen();
    if (!mounted) return;
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      body: SafeArea(
        child: Stack(
          children: [
            PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _Slide1(onNext: _next),
                _Slide2(onNext: _next),
                _Slide3(onDone: _done),
              ],
            ),

            // Skip button — top right, hidden on last slide
            if (_page < _lastPage)
              Positioned(
                top: 8,
                right: 16,
                child: TextButton(
                  onPressed: _skipToLast,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

            // Progress dots — bottom centre
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _lastPage + 1,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? LuminColors.accent
                          : LuminColors.cardBorder,
                      borderRadius: BorderRadius.circular(LuminRadii.pill),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide 1 — Hook
// ---------------------------------------------------------------------------

class _Slide1 extends StatelessWidget {
  const _Slide1({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.xl, LuminSpacing.xxl, LuminSpacing.xl, 80,
      ),
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

          const Spacer(),

          const Text(
            'Signals that\nclose in profit.',
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
          const SizedBox(height: LuminSpacing.xl),

          // Proof chips
          Wrap(
            spacing: LuminSpacing.sm,
            runSpacing: LuminSpacing.sm,
            children: const [
              _StatChip(label: '75+ pairs', icon: Icons.radar_outlined),
              _StatChip(label: '15 AI analysts', icon: Icons.smart_toy_outlined),
              _StatChip(label: 'Paper mode first', icon: Icons.science_outlined),
            ],
          ),

          const Spacer(),

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
              onPressed: onNext,
              child: const Text(
                'See how it works',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide 2 — How it works
// ---------------------------------------------------------------------------

class _Slide2 extends StatelessWidget {
  const _Slide2({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.xl, LuminSpacing.xxl, LuminSpacing.xl, 80,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              color: LuminColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(LuminRadii.sm),
            ),
            child: const Icon(
              Icons.auto_mode_outlined,
              color: LuminColors.accent,
              size: 28,
            ),
          ),

          const Spacer(),

          const Text(
            'How it works',
            style: TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          const Text(
            'Three steps from scan to execution.',
            style: TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: LuminSpacing.xxl),

          _Step(
            number: '1',
            title: 'Scanner watches 75 pairs',
            body: 'Every 15 seconds, the engine scans 75 USDT futures '
                'pairs for high-probability setups.',
          ),
          const SizedBox(height: LuminSpacing.lg),
          _Step(
            number: '2',
            title: '15 AI analysts score each signal',
            body: 'Momentum, structure, volume profile, regime — '
                'every angle checked before a signal fires.',
          ),
          const SizedBox(height: LuminSpacing.lg),
          _Step(
            number: '3',
            title: 'Auto-executes on your Binance',
            body: 'SL and TP placed the moment the entry fills. '
                'Try it on paper first — zero risk.',
          ),

          const Spacer(),

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
              onPressed: onNext,
              child: const Text(
                'Your funds stay safe',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide 3 — Safety + CTA
// ---------------------------------------------------------------------------

class _Slide3 extends StatelessWidget {
  const _Slide3({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.xl, LuminSpacing.xxl, LuminSpacing.xl, 80,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              color: LuminColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(LuminRadii.sm),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: LuminColors.success,
              size: 28,
            ),
          ),

          const Spacer(),

          const Text(
            'Your funds never\nleave Binance.',
            style: TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: LuminSpacing.xl),

          _SafetyRow(
            icon: Icons.vpn_key_outlined,
            title: 'Trade-only API key',
            body: 'Read + trade permissions only. Withdraw is never requested.',
          ),
          const SizedBox(height: LuminSpacing.lg),
          _SafetyRow(
            icon: Icons.block_outlined,
            title: 'Stop-loss on every position',
            body: 'Every open trade has a hard stop. No runaway losses.',
          ),
          const SizedBox(height: LuminSpacing.lg),
          _SafetyRow(
            icon: Icons.science_outlined,
            title: 'Paper mode — prove it first',
            body: 'Run the full engine on simulated trades before going live.',
          ),

          const Spacer(),

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
          const Center(
            child: Text(
              '18+ · Crypto futures trading carries risk of loss',
              style: TextStyle(color: LuminColors.textMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

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

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body});
  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: LuminColors.accent,
            borderRadius: BorderRadius.circular(LuminRadii.sm),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: LuminColors.bgDeep,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyRow extends StatelessWidget {
  const _SafetyRow({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: LuminColors.bgCard,
            borderRadius: BorderRadius.circular(LuminRadii.sm),
            border: Border.all(color: LuminColors.cardBorder),
          ),
          child: Icon(icon, size: 18, color: LuminColors.success),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

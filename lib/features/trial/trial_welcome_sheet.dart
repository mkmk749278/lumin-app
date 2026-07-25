/// The welcome offer — 7 free days of the full product for a new customer.
///
/// Owner decision (2026-07-25): *"offer 7 days free trial for every new
/// customer so that they can understand our services"*, resolved to 7 days of
/// `auto` (hands-off server-side execution), granted with **no payment
/// method**, and **activated only by a deliberate tap** — never automatically.
/// This sheet is that tap.
///
/// Two rules govern everything in here:
///
/// * **The engine decides, the sheet renders.** This never appears unless the
///   engine reports `offer_available: true`, and every number in the copy
///   (days, tier) comes from that response rather than a constant — so the
///   moment the owner retunes the offer, the pitch retunes with it. A sheet
///   promising a trial the engine will refuse is the bug class this repo has
///   already paid for.
/// * **No overclaiming.** The copy sells what the product actually does:
///   automation of signals the user can already see for free, on their own
///   exchange keys, under their own risk. It never implies profit, and it says
///   plainly that nothing trades until the user connects a key and arms it.
///   (Play policy aside, an over-promised trial converts into a refund and a
///   one-star review.)
///
/// The pure [TrialWelcomeCard] takes explicit params and is widget-tested; the
/// [showTrialWelcomeSheet] wrapper handles presentation and the claim call.
library;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';

/// Human label for the tier a trial grants.  Falls back to the raw string so
/// an engine that starts granting a tier this build has never heard of still
/// renders something honest instead of a wrong name.
String trialTierLabel(String? tier) {
  switch ((tier ?? '').toLowerCase()) {
    case 'auto':
      return 'Auto';
    case 'assist':
      return 'Assist';
    default:
      return tier == null || tier.isEmpty ? 'full access' : tier;
  }
}

/// What the user gets, in the order that matters to someone deciding.
List<({IconData icon, String title, String body})> trialBenefits(String tier) {
  final isAuto = tier.toLowerCase() == 'auto';
  return [
    (
      icon: Icons.bolt_rounded,
      title: isAuto ? 'Hands-off trading' : 'One-tap trading',
      body: isAuto
          ? 'The engine takes every eligible signal for you — entry, stop and '
              'targets placed automatically, 24/7, while you sleep.'
          : 'Take any signal with a single tap. Entry, stop and targets are '
              'placed for you at the prices on the card.',
    ),
    (
      icon: Icons.shield_outlined,
      title: 'Every trade protected',
      body: 'A stop-loss goes on with the entry, every time. Positions are '
          'monitored continuously and closed when the setup breaks.',
    ),
    (
      icon: Icons.key_off_rounded,
      title: 'Your keys, your exchange',
      body: 'Trades run on your own Binance account. We can never withdraw — '
          'keys with withdrawal permission are rejected outright.',
    ),
  ];
}

/// Pure welcome card — the sheet's body, testable without a Navigator.
class TrialWelcomeCard extends StatelessWidget {
  const TrialWelcomeCard({
    super.key,
    required this.trial,
    required this.onStart,
    required this.onLater,
    this.busy = false,
    this.error,
  });

  /// Engine truth. [TrialState.days] and [TrialState.tier] drive the copy.
  final TrialState trial;
  final VoidCallback onStart;
  final VoidCallback onLater;
  final bool busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tier = trialTierLabel(trial.tier);
    final days = trial.days;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          LuminSpacing.lg,
          LuminSpacing.md,
          LuminSpacing.lg,
          LuminSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: LuminColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.lg),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LuminSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: LuminColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
                border: Border.all(
                  color: LuminColors.success.withOpacity(0.35),
                ),
              ),
              child: const Text(
                'WELCOME GIFT',
                style: TextStyle(
                  color: LuminColors.success,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            Text(
              '$days days of $tier, free',
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                height: 1.15,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              'You can already see every signal we produce. For the next '
              '$days days, let the engine act on them for you — so you can '
              'judge us on results, not screenshots.',
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: LuminSpacing.lg),
            for (final benefit in trialBenefits(trial.tier ?? '')) ...[
              _Benefit(
                icon: benefit.icon,
                title: benefit.title,
                body: benefit.body,
              ),
              const SizedBox(height: LuminSpacing.md),
            ],
            Container(
              padding: const EdgeInsets.all(LuminSpacing.md),
              decoration: BoxDecoration(
                color: LuminColors.bgCard,
                borderRadius: BorderRadius.circular(LuminRadii.md),
                border: Border.all(color: LuminColors.accent.withOpacity(0.25)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No card. No auto-charge.',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'We never ask for payment details to start this. When the '
                    'trial ends it simply stops — nothing is billed unless you '
                    'choose to subscribe.',
                    style: TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            const Text(
              'Trading futures carries substantial risk of loss. Nothing here '
              'is investment advice — you decide what to run and how much to '
              'risk, and nothing trades until you connect your exchange keys '
              'and switch it on.',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: LuminSpacing.md),
              Text(
                error!,
                style: const TextStyle(
                  color: LuminColors.loss,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: LuminSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: LuminColors.accent,
                  foregroundColor: const Color(0xFF06202F),
                  padding: const EdgeInsets.symmetric(
                    vertical: LuminSpacing.md,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(LuminRadii.md),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF06202F),
                        ),
                      )
                    : Text(
                        'Start my $days free days',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: LuminSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: busy ? null : onLater,
                child: const Text(
                  'Maybe later',
                  style: TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
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

class _Benefit extends StatelessWidget {
  const _Benefit({
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
          padding: const EdgeInsets.all(LuminSpacing.sm),
          decoration: BoxDecoration(
            color: LuminColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(LuminRadii.sm),
          ),
          child: Icon(icon, color: LuminColors.accent, size: 18),
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
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12.5,
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

/// Present the welcome offer and, if the user taps through, activate it.
///
/// Returns the post-claim [TrialState] when a trial was started, or `null`
/// when the user dismissed. On success the locally-cached entitlement is
/// refreshed so the free-tier gates unlock immediately — the engine has
/// already persisted the grant and remains the authority; this only saves a
/// profile round-trip.
Future<TrialState?> showTrialWelcomeSheet(
  BuildContext context,
  TrialState trial,
) async {
  final scope = AppConfigScope.of(context);
  final repo = scope.repo;
  return showModalBottomSheet<TrialState>(
    context: context,
    backgroundColor: LuminColors.bgElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
    ),
    builder: (sheetContext) {
      var busy = false;
      String? error;
      return StatefulBuilder(
        builder: (builderContext, setSheetState) => TrialWelcomeCard(
          trial: trial,
          busy: busy,
          error: error,
          onLater: () => Navigator.of(sheetContext).pop(),
          onStart: () async {
            setSheetState(() {
              busy = true;
              error = null;
            });
            TrialClaimResult result;
            try {
              result = await repo.claimTrial();
            } catch (_) {
              setSheetState(() {
                busy = false;
                error = "Couldn't start your trial just now. "
                    'Check your connection and try again.';
              });
              return;
            }
            if (!result.ok) {
              setSheetState(() {
                busy = false;
                error = trialRefusalMessage(result.reason);
              });
              return;
            }
            // The engine granted it; mirror the tier locally so gated
            // surfaces unlock without waiting for the next profile fetch.
            scope.auth?.applyEntitlement(
              tier: result.state.tier ?? 'auto',
              paidUntil: result.state.expiresAt,
            );
            if (sheetContext.mounted) {
              Navigator.of(sheetContext).pop(result.state);
            }
          },
        ),
      );
    },
  );
}

/// User-facing message for an engine refusal reason.
///
/// Deliberately exhaustive over the engine's vocabulary so a refusal never
/// surfaces as a raw enum string; the default stays vague rather than guessing
/// at a cause we don't recognise.
String trialRefusalMessage(String? reason) {
  switch (reason) {
    case 'already_trialled':
      return 'You have already used your free trial.';
    case 'already_subscribed':
      return 'Your account already has a subscription — no trial needed.';
    case 'account_too_old':
      return 'This offer is for new accounts only.';
    case 'not_onboarded':
      return 'Finish setting up your profile first, then try again.';
    case 'offer_not_available':
      return 'This offer is not available right now.';
    default:
      return "Couldn't start your trial. Please try again.";
  }
}

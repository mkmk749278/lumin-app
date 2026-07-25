/// Re-entry point for a welcome offer the user tapped past.
///
/// "Maybe later" on the welcome sheet must not be a dead end — the offer is
/// one-shot and genuinely valuable, so it stays reachable from Settings →
/// Subscription until the user takes it or the engine stops offering it.
/// Mounted above the paywall for exactly that reason: someone who opened the
/// plans page is deciding whether to pay, and the honest thing to show them
/// first is that they can have it free for a week.
///
/// Renders nothing unless the engine reports `offer_available` — same rule as
/// everywhere else, so a dark flag makes this invisible without any client
/// coordination.
library;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import 'trial_gate.dart';
import 'trial_welcome_sheet.dart';

/// Pure tile — visible only while an offer is available.
class TrialOfferTile extends StatelessWidget {
  const TrialOfferTile({
    super.key,
    required this.trial,
    required this.onStart,
  });

  final TrialState trial;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    if (!trial.offerAvailable) return const SizedBox.shrink();
    final tier = trialTierLabel(trial.tier);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Material(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.lg),
        child: InkWell(
          onTap: onStart,
          borderRadius: BorderRadius.circular(LuminRadii.lg),
          child: Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LuminRadii.lg),
              border: Border.all(
                color: LuminColors.success.withOpacity(0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(LuminSpacing.sm),
                  decoration: BoxDecoration(
                    color: LuminColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(LuminRadii.sm),
                  ),
                  child: const Icon(
                    Icons.card_giftcard_rounded,
                    color: LuminColors.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: LuminSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Try $tier free for ${trial.days} days',
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'No card, no auto-charge. Decide after you have seen '
                        'it work on your own account.',
                        style: TextStyle(
                          color: LuminColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: LuminSpacing.sm),
                      Row(
                        children: [
                          Text(
                            'Start free trial',
                            style: TextStyle(
                              color: LuminColors.success,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_forward_rounded,
                              color: LuminColors.success, size: 14),
                        ],
                      ),
                    ],
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

/// Scope wrapper — reads the shared trial state and opens the welcome sheet.
/// Shows nothing while loading or on error, so the paywall never flashes an
/// offer that turns out not to exist.
class TrialOfferBanner extends StatefulWidget {
  const TrialOfferBanner({super.key, this.onClaimed});

  /// Called after a successful claim so the host page can refresh its tier.
  final ValueChanged<TrialState>? onClaimed;

  @override
  State<TrialOfferBanner> createState() => _TrialOfferBannerState();
}

class _TrialOfferBannerState extends State<TrialOfferBanner> {
  Future<TrialState>? _future;
  TrialState? _override;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= trialState(AppConfigScope.of(context).repo);
  }

  Future<void> _start(TrialState trial) async {
    final claimed = await showTrialWelcomeSheet(context, trial);
    if (claimed == null || !mounted) return;
    invalidateTrialState();
    setState(() => _override = claimed);
    widget.onClaimed?.call(claimed);
  }

  @override
  Widget build(BuildContext context) {
    final known = _override;
    if (known != null) {
      return TrialOfferTile(trial: known, onStart: () {});
    }
    return FutureBuilder<TrialState>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            snap.hasError ||
            snap.data == null) {
          return const SizedBox.shrink();
        }
        final trial = snap.data!;
        if (!trial.offerAvailable) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: LuminSpacing.md),
          child: TrialOfferTile(
            trial: trial,
            onStart: () => _start(trial),
          ),
        );
      },
    );
  }
}

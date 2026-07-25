/// Where the free trial reaches the user: the welcome pop-up for a new
/// customer, and the countdown banner once one is running.
///
/// Mount [TrialGate] on Pulse. It does three things and nothing else:
///
/// 1. asks the engine what this user's trial situation is (one cached GET);
/// 2. if an offer is available, shows the welcome sheet **once per session**;
/// 3. if a trial is running, renders a countdown banner that turns into an
///    upsell in the last two days.
///
/// Truthfulness rules this file exists to enforce (repo doctrine: render
/// engine state, never derive it):
///
/// * The sheet appears **iff** the engine says `offer_available`. There is no
///   client-side notion of "new user" here — the engine owns eligibility, so a
///   user who already trialled, already pays, or hits a dark flag simply never
///   sees anything.
/// * Nothing is claimed without a tap. Showing the sheet grants nothing;
///   `POST /api/trial/claim` is only reached from the CTA.
/// * A dismissed offer is not a burnt one. "Maybe later" closes the sheet for
///   the session; the offer stays claimable from Settings → Subscription until
///   the user takes it or the engine stops offering it.
library;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/upsell_banners.dart';
import 'trial_welcome_sheet.dart';

// ---------------------------------------------------------------------------
// Session state + shared fetch
// ---------------------------------------------------------------------------

/// Per-session guard so the welcome sheet interrupts at most once. Deliberately
/// in-memory: a user who force-quits and comes back gets one more chance at an
/// offer that is genuinely valuable to them, and the engine's one-shot claim
/// makes re-showing harmless.
bool _welcomeShownThisSession = false;

Future<TrialState>? _trialFuture;
LuminRepository? _trialRepo;

/// One in-flight `GET /api/trial` shared across every mount point, re-used
/// until the repo instance changes (mock ↔ live swap on reconfigure).
Future<TrialState> trialState(LuminRepository repo) {
  if (!identical(_trialRepo, repo) || _trialFuture == null) {
    _trialRepo = repo;
    _trialFuture = repo.fetchTrialState();
  }
  return _trialFuture!;
}

/// Drop the cached state so the next read hits the engine — called after a
/// claim so the countdown banner replaces the offer immediately.
void invalidateTrialState() {
  _trialFuture = null;
  _trialRepo = null;
}

@visibleForTesting
void resetTrialSessionState() {
  _welcomeShownThisSession = false;
  invalidateTrialState();
}

// ---------------------------------------------------------------------------
// Countdown banner
// ---------------------------------------------------------------------------

/// Pure countdown card for a running trial. Renders nothing when no trial is
/// active — an expired or unclaimed trial has nothing to count down.
class TrialCountdownCard extends StatelessWidget {
  const TrialCountdownCard({
    super.key,
    required this.trial,
    required this.onSeePlans,
  });

  final TrialState trial;
  final VoidCallback onSeePlans;

  @override
  Widget build(BuildContext context) {
    if (!trial.active) return const SizedBox.shrink();
    final days = trial.daysRemaining ?? 0;
    final tier = trialTierLabel(trial.tier);
    final ending = trial.isEndingSoon;
    final accent = ending ? LuminColors.warn : LuminColors.success;
    final left = days == 1 ? '1 day left' : '$days days left';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.lg,
        vertical: LuminSpacing.xs,
      ),
      child: Material(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(LuminRadii.lg),
        child: InkWell(
          onTap: onSeePlans,
          borderRadius: BorderRadius.circular(LuminRadii.lg),
          child: Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LuminRadii.lg),
              border: Border.all(color: accent.withOpacity(0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(LuminSpacing.sm),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(LuminRadii.sm),
                  ),
                  child: Icon(
                    ending
                        ? Icons.hourglass_bottom_rounded
                        : Icons.auto_awesome_rounded,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: LuminSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ending
                            ? 'Your free $tier ends soon — $left'
                            : 'Free $tier trial · $left',
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ending
                            ? 'Keep it running without a gap — subscribe '
                                'before it lapses and nothing changes.'
                            : 'Full $tier access, on the house. Nothing is '
                                'billed when it ends.',
                        style: const TextStyle(
                          color: LuminColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: LuminSpacing.sm),
                      Row(
                        children: [
                          Text(
                            ending ? 'Keep $tier' : 'See plans',
                            style: TextStyle(
                              color: accent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_forward_rounded,
                              color: accent, size: 14),
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

// ---------------------------------------------------------------------------
// Gate
// ---------------------------------------------------------------------------

/// Mount point: pops the welcome offer for eligible users and renders the
/// countdown for users already on a trial. Renders nothing otherwise, which is
/// the case for everyone while the engine's offer flag is dark.
class TrialGate extends StatefulWidget {
  const TrialGate({super.key});

  @override
  State<TrialGate> createState() => _TrialGateState();
}

class _TrialGateState extends State<TrialGate> {
  Future<TrialState>? _future;
  TrialState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<TrialState> _load() async {
    final state = await trialState(AppConfigScope.of(context).repo);
    if (mounted) _maybeShowWelcome(state);
    return state;
  }

  void _maybeShowWelcome(TrialState state) {
    if (!state.offerAvailable || _welcomeShownThisSession) return;
    _welcomeShownThisSession = true;
    // Wait for the frame to settle — a modal pushed during build (or during
    // the first frame after a tab switch) fights the navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final claimed = await showTrialWelcomeSheet(context, state);
      if (claimed == null || !mounted) return;
      invalidateTrialState();
      setState(() {
        _state = claimed;
        _future = Future<TrialState>.value(claimed);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final known = _state;
    if (known != null) {
      return TrialCountdownCard(
        trial: known,
        onSeePlans: () => openPaywall(context),
      );
    }
    return FutureBuilder<TrialState>(
      future: _future,
      builder: (context, snap) {
        // Nothing while loading or on error — a trial banner that flashes
        // placeholder copy is worse than one that arrives a beat later.
        if (snap.connectionState != ConnectionState.done ||
            snap.hasError ||
            snap.data == null) {
          return const SizedBox.shrink();
        }
        return TrialCountdownCard(
          trial: snap.data!,
          onSeePlans: () => openPaywall(context),
        );
      },
    );
  }
}

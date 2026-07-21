/// Invite a friend — Phase 2 referral rewards (2026-07-21).
///
/// Phase 1 (2026-06-27) shipped the stable code + "friends joined"
/// counter with "rewards are coming soon".  Phase 2 delivers them, and
/// this page renders the deal straight from engine truth
/// (`GET /api/referral/me`):
///   * 7 days of free Auto banked per friend who joins (stacking),
///   * the friend gets 50% off their first month on either plan,
///   * 50% commission on each of the friend's first 3 paid months,
///     accrued per currency and paid out by the owner.
/// `rewards_enabled` gates every reward element so the page stays
/// truthful if the engine programme is switched off — never promise a
/// reward the engine won't grant (repo convention: render engine state).
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../shared/format.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});

  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  ReferralStats? _stats;
  String? _loadError;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stats == null && _loadError == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final stats = await AppConfigScope.of(context).repo.getReferralStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Couldn\'t load your invite code: $e';
        _loading = false;
      });
    }
  }

  void _share() {
    final stats = _stats;
    if (stats == null) return;
    final rewards = stats.rewardsEnabled;
    final discount =
        rewards && stats.discountPercent > 0 ? stats.discountPercent : null;
    SharePlus.instance.share(ShareParams(
      text: discount != null
          ? 'Join me on Lumin — AI crypto trading signals from the 360 '
              'Crypto Eye engine. Sign up with my invite code '
              '${stats.code} and get $discount% off your first month of '
              'any plan!'
          : 'Join me on Lumin — AI crypto trading signals from the 360 '
              'Crypto Eye engine. Use my invite code ${stats.code} when '
              'you sign up!',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text('Invite a friend')),
      body: RefreshIndicator(
        color: LuminColors.accent,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
            const SizedBox(height: LuminSpacing.md),
            if (_loading) ...[
              const SizedBox(height: LuminSpacing.xl),
              const Center(
                child: CircularProgressIndicator(color: LuminColors.accent),
              ),
            ] else if (_loadError != null) ...[
              _errorCard(_loadError!),
            ] else if (stats != null) ...[
              _hero(stats),
              const SizedBox(height: LuminSpacing.md),
              _codeCard(stats.code),
              const SizedBox(height: LuminSpacing.md),
              if (stats.rewardsEnabled && stats.rewardActiveUntil != null) ...[
                _activeRewardCard(stats),
                const SizedBox(height: LuminSpacing.md),
              ],
              _statsCard(stats),
              if (stats.rewardsEnabled &&
                  stats.commissionTotals.isNotEmpty) ...[
                const SizedBox(height: LuminSpacing.md),
                _commissionCard(stats),
              ],
              const SizedBox(height: LuminSpacing.lg),
              _shareButton(),
            ],
            const SizedBox(height: LuminSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _hero(ReferralStats stats) {
    final rewards = stats.rewardsEnabled;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.lg),
          border: Border.all(color: LuminColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person_add_alt_1_outlined,
                    color: LuminColors.accent, size: 28),
                SizedBox(width: LuminSpacing.sm),
                Text(
                  'Invite a friend',
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            if (!rewards)
              const Text(
                'Share your code with friends. We\'ll keep this counter '
                'updated as they join — rewards are coming soon.',
                style: TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              )
            else ...[
              _dealRow(
                Icons.card_giftcard,
                'You get ${stats.rewardDaysPerInvite} days of free '
                '${_tierLabel(stats.rewardTier)} for every friend who joins '
                'with your code — they stack.',
              ),
              _dealRow(
                Icons.percent,
                'Your friend gets ${stats.discountPercent}% off their first '
                'month on any plan.',
              ),
              _dealRow(
                Icons.payments_outlined,
                'When a friend subscribes, you earn '
                '${_pct(stats.commissionRate)} of what they pay for their '
                'first ${stats.commissionMaxPeriods} months — paid out to '
                'you directly.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dealRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: LuminSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: LuminColors.accent, size: 16),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeCard(String code) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'YOUR CODE',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: LuminSpacing.md,
                vertical: LuminSpacing.md,
              ),
              decoration: BoxDecoration(
                color: LuminColors.bgElevated,
                borderRadius: BorderRadius.circular(LuminRadii.sm),
                border: Border.all(color: LuminColors.cardBorder),
              ),
              child: Text(
                code,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: LuminColors.accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Green "reward running" banner — rendered only when the engine
  /// reports an active reward window (engine truth, never derived).
  Widget _activeRewardCard(ReferralStats stats) {
    final until = formatPaidUntil(stats.rewardActiveUntil);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.success.withOpacity(0.10),
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(color: LuminColors.success.withOpacity(0.45)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded,
                color: LuminColors.success, size: 20),
            const SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Text(
                until != null
                    ? 'Free ${_tierLabel(stats.rewardActiveTier)} active '
                        'until $until — earned from your invites.'
                    : 'Free ${_tierLabel(stats.rewardActiveTier)} active — '
                        'earned from your invites.',
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsCard(ReferralStats stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          children: [
            _statRow(
              Icons.group_outlined,
              stats.referredCount == 1
                  ? '1 friend joined'
                  : '${stats.referredCount} friends joined',
            ),
            if (stats.rewardsEnabled) ...[
              const SizedBox(height: LuminSpacing.sm),
              _statRow(
                Icons.workspace_premium_outlined,
                stats.paidReferredCount == 1
                    ? '1 friend subscribed'
                    : '${stats.paidReferredCount} friends subscribed',
              ),
              const SizedBox(height: LuminSpacing.sm),
              _statRow(
                Icons.card_giftcard,
                '${stats.rewardDaysEarned} free '
                '${_tierLabel(stats.rewardTier)} days earned',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: LuminColors.accent, size: 22),
        const SizedBox(width: LuminSpacing.md),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// Commission earnings — one row per currency (INR from Play, USD from
  /// the web channel); never summed across currencies.
  Widget _commissionCard(ReferralStats stats) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'COMMISSION EARNED',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.sm),
            for (final t in stats.commissionTotals)
              Padding(
                padding: const EdgeInsets.only(bottom: LuminSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_money(t.accrued + t.paid, t.currency)} total',
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      t.accrued > 0
                          ? '${_money(t.accrued, t.currency)} pending payout'
                          : 'all paid out',
                      style: const TextStyle(
                        color: LuminColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: LuminSpacing.xs),
            const Text(
              'Payouts are settled directly to you by the Lumin team.',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: FilledButton.icon(
        onPressed: _share,
        icon: const Icon(Icons.ios_share),
        style: FilledButton.styleFrom(
          backgroundColor: LuminColors.accent,
          foregroundColor: LuminColors.bgDeep,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LuminRadii.md),
          ),
        ),
        label: const Text(
          'Share my invite code',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(
                  color: LuminColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: LuminSpacing.md),
            TextButton(
              onPressed: _load,
              child: const Text('Retry',
                  style: TextStyle(color: LuminColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

String _tierLabel(String? tier) {
  switch ((tier ?? '').toLowerCase()) {
    case 'assist':
      return 'Assist';
    case 'auto':
      return 'Auto';
    default:
      return 'Auto';
  }
}

String _pct(double fraction) => '${(fraction * 100).round()}%';

String _money(double amount, String currency) {
  final symbol = switch (currency.toUpperCase()) {
    'INR' => '₹',
    'USD' => '\$',
    _ => '$currency ',
  };
  final text = amount == amount.roundToDouble()
      ? amount.round().toString()
      : amount.toStringAsFixed(2);
  return '$symbol$text';
}

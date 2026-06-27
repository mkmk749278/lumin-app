/// Invite a friend — Phase 1 referral tracking (2026-06-27).
///
/// Shows the user's stable referral code and how many friends have
/// joined via it, with a native share-sheet button.  Phase 1 is
/// tracking only — no monetary or tier reward yet; that ships once
/// Google Play Billing is live (each side gets one week of Auto free).
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/app_config.dart';
import '../../../data/repository.dart';
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
    final code = _stats?.code;
    if (code == null) return;
    SharePlus.instance.share(ShareParams(
      text: 'Join me on Lumin — AI crypto trading signals from the 360 '
          'Crypto Eye engine. Use my invite code $code when you sign up!',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite a friend')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          if (_loading) ...[
            const SizedBox(height: LuminSpacing.xl),
            const Center(
              child: CircularProgressIndicator(color: LuminColors.accent),
            ),
          ] else if (_loadError != null) ...[
            _errorCard(_loadError!),
          ] else ...[
            _hero(),
            const SizedBox(height: LuminSpacing.md),
            _codeCard(_stats!.code),
            const SizedBox(height: LuminSpacing.md),
            _statCard(_stats!.referredCount),
            const SizedBox(height: LuminSpacing.lg),
            _shareButton(),
          ],
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  Widget _hero() {
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
          children: const [
            Row(
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
            SizedBox(height: LuminSpacing.sm),
            Text(
              'Share your code with friends. We\'ll keep this counter '
              'updated as they join — rewards are coming soon.',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
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

  Widget _statCard(int referredCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            const Icon(Icons.group_outlined, color: LuminColors.accent, size: 22),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Text(
                referredCount == 1
                    ? '1 friend joined'
                    : '$referredCount friends joined',
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
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
              style: const TextStyle(color: LuminColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: LuminSpacing.md),
            TextButton(
              onPressed: _load,
              child: const Text('Retry', style: TextStyle(color: LuminColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

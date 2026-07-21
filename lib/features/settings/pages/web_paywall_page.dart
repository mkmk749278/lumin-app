/// Web paywall — the PWA's crypto (NOWPayments) subscription page (Phase 3).
///
/// Shown instead of the Play [SubscriptionPage] on the **web** build
/// (`kDistribution == AppDistribution.web`).  Signals + levels + analysis are
/// FREE; the paywall is on trade automation — the SAME two tiers as Play:
///   * Assist ($15/mo) — one-tap "take trade".
///   * Auto   ($25/mo) — hands-off auto-execution.
///
/// Crypto settles asynchronously on-chain, so after the user pays on the
/// hosted NOWPayments page we cannot know locally when funds land — the
/// signature-verified IPN grants the tier on the engine (the source of
/// truth), and this page polls `GET /api/profile` until the tier unlocks.
/// A "manual" note is shown when the owner offers manual activation.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/app_config.dart';
import '../../../data/repository.dart';
import '../../../data/web_billing_service.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

class WebPaywallPage extends StatefulWidget {
  const WebPaywallPage({super.key});

  @override
  State<WebPaywallPage> createState() => _WebPaywallPageState();
}

class _WebPaywallPageState extends State<WebPaywallPage> {
  bool _initialised = false;
  bool _loading = true;
  String? _error;
  WebBillingService? _svc;
  WebBillingConfig? _config;
  String? _tier;

  /// Referral Phase 2 (2026-07-21): engine-reported one-time discount
  /// state.  The engine prices the discounted invoice server-side at
  /// checkout — this only drives the "50% off will be applied" banner.
  ReferralStats? _referral;

  // Post-checkout state.
  bool _awaitingPayment = false;
  bool _checking = false;
  WebCheckout? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final scope = AppConfigScope.of(context);
    _tier = scope.tier;
    final auth = scope.auth;
    if (auth == null) {
      setState(() {
        _loading = false;
        _error = 'Billing is unavailable in preview mode.';
      });
      return;
    }
    _svc = WebBillingService(repo: scope.repo, auth: auth);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await _svc!.loadConfig();
      // Best-effort — a failed referral read never blocks the paywall.
      ReferralStats? referral;
      try {
        referral = await AppConfigScope.of(context).repo.getReferralStats();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _config = config;
        _referral = referral;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load plans. $e';
        _loading = false;
      });
    }
  }

  bool get _isPaid =>
      _tier == 'assist' || _tier == 'auto' || _tier == 'paid' || _tier == 'owner';

  Future<void> _buy(String tier) async {
    final svc = _svc;
    if (svc == null) return;
    setState(() => _awaitingPayment = true);
    try {
      final checkout = await svc.startCheckout(tier);
      if (!mounted) return;
      setState(() => _pending = checkout);
      // Poll in the background; the webhook grants the tier when funds land.
      final entitled = await svc.pollEntitlement(wantTier: tier);
      if (!mounted) return;
      if (entitled) {
        _onEntitled();
      }
      // On timeout we leave the awaiting card up with the manual check button.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _awaitingPayment = false;
        _pending = null;
      });
      _snack('Checkout failed: $e');
    }
  }

  Future<void> _checkNow(String tier) async {
    final svc = _svc;
    if (svc == null) return;
    setState(() => _checking = true);
    final entitled = await svc.checkEntitlementOnce(tier);
    if (!mounted) return;
    setState(() => _checking = false);
    if (entitled) {
      _onEntitled();
    } else {
      _snack('No confirmed payment yet — this can take a few minutes.');
    }
  }

  void _onEntitled() {
    setState(() {
      _tier = _svc?.auth.currentTier() ?? _tier;
      _awaitingPayment = false;
      _pending = null;
    });
    _snack('Subscription active — thanks!');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _errorView(_error!);
    }
    return ListView(
      padding: const EdgeInsets.all(LuminSpacing.lg),
      children: [
        if (_isPaid) _currentPlanCard(),
        if (_awaitingPayment)
          _awaitingCard()
        else ...[
          _introCard(),
          if (_discountBanner() != null) ...[
            const SizedBox(height: LuminSpacing.md),
            _discountBanner()!,
          ],
          const SizedBox(height: LuminSpacing.md),
          ..._planCards(),
        ],
        const SizedBox(height: LuminSpacing.md),
        _manualCard(),
        const SizedBox(height: LuminSpacing.lg),
        _footerNote(),
      ],
    );
  }

  /// Referral discount banner — shown only while the ENGINE reports the
  /// one-time discount as unredeemed; the engine applies the actual cut
  /// at checkout, so this never promises what the invoice won't honour.
  Widget? _discountBanner() {
    final r = _referral;
    if (_isPaid ||
        r == null ||
        !r.rewardsEnabled ||
        !r.discountEligible ||
        r.discountPercent <= 0) {
      return null;
    }
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.success.withOpacity(0.10),
        borderRadius: BorderRadius.circular(LuminRadii.md),
        border: Border.all(color: LuminColors.success.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.percent, color: LuminColors.success, size: 20),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Text(
              'Invite reward: ${r.discountPercent}% off your first payment '
              'will be applied at checkout.',
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(LuminSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LuminColors.textSecondary)),
              const SizedBox(height: LuminSpacing.md),
              if (_svc != null)
                FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _currentPlanCard() => Padding(
        padding: const EdgeInsets.only(bottom: LuminSpacing.md),
        child: LuminCard(
          child: Row(
            children: [
              const Icon(Icons.verified, color: LuminColors.success),
              const SizedBox(width: LuminSpacing.sm),
              Expanded(
                child: Text(
                  'You’re on the ${_tier!.toUpperCase()} plan.',
                  style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _introCard() => const LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signals, levels & charts are free.',
                style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: LuminSpacing.xs),
            Text('Upgrade to trade the signals — one-tap or hands-off, on '
                'your own exchange. Lumin never holds your funds.',
                style: TextStyle(color: LuminColors.textSecondary)),
          ],
        ),
      );

  List<Widget> _planCards() {
    final crypto = _config?.crypto;
    if (crypto == null || crypto.tiers.isEmpty) {
      return [
        LuminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Card & crypto checkout is not available yet.',
                  style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: LuminSpacing.xs),
              Text('You can still activate a plan manually — see below.',
                  style: TextStyle(color: LuminColors.textSecondary)),
            ],
          ),
        ),
      ];
    }
    const specs = [
      ('assist', 'Assist', 'One-tap live trades — take any signal on your own '
          'exchange.'),
      ('auto', 'Auto', 'Hands-off auto-execution — the engine trades the '
          'signals for you.'),
    ];
    return [
      for (final (tierId, label, blurb) in specs)
        if (crypto.tiers[tierId] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: LuminSpacing.md),
            child: _planCard(tierId, label, blurb, crypto.tiers[tierId]!),
          ),
    ];
  }

  Widget _planCard(
      String tierId, String label, String blurb, WebTierPrice price) {
    final owned = _tier == tierId ||
        _tier == 'owner' ||
        (tierId == 'assist' && _tier == 'auto');
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(price.display,
                  style: const TextStyle(
                      color: LuminColors.accent, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: LuminSpacing.xs),
          Text(blurb, style: const TextStyle(color: LuminColors.textSecondary)),
          const SizedBox(height: LuminSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: owned ? null : () => _buy(tierId),
              child: Text(owned ? 'Current plan' : 'Pay with crypto'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _awaitingCard() {
    final tier = _pending?.tier ?? '';
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: LuminSpacing.sm),
              Text('Waiting for payment',
                  style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: LuminSpacing.sm),
          const Text(
            'Complete the payment in the tab that opened. Your plan unlocks '
            'automatically once the payment confirms on-chain — this can take '
            'a few minutes.',
            style: TextStyle(color: LuminColors.textSecondary),
          ),
          if (_pending != null && _pending!.amountUsd > 0) ...[
            const SizedBox(height: LuminSpacing.xs),
            Text(
              _pending!.discounted
                  ? 'Invoice: \$${_pending!.amountUsd.toStringAsFixed(2)} '
                      '(${_pending!.discountPercent}% invite discount applied)'
                  : 'Invoice: \$${_pending!.amountUsd.toStringAsFixed(2)}',
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: LuminSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _checking ? null : () => _checkNow(tier),
                  child: Text(_checking ? 'Checking…' : 'I’ve paid — check now'),
                ),
              ),
              const SizedBox(width: LuminSpacing.sm),
              TextButton(
                onPressed: () => setState(() {
                  _awaitingPayment = false;
                  _pending = null;
                }),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _manualCard() {
    final manual = _config?.railById('manual');
    if (manual == null) return const SizedBox.shrink();
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Prefer to pay another way?',
              style: TextStyle(
                  color: LuminColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: LuminSpacing.xs),
          Text(
            manual.note ?? 'Contact us to activate a plan manually.',
            style: const TextStyle(color: LuminColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _footerNote() => const Text(
        'Prices are billed in crypto (USDT). Subscriptions renew monthly; '
        'crypto renewals are paid manually — we’ll remind you before expiry. '
        'The paid feature is trade-automation software that runs on your own '
        'exchange keys — not investment advice.',
        style: TextStyle(color: LuminColors.textMuted, fontSize: 12),
      );
}

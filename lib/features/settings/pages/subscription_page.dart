/// Subscription page — two-tier auto-trade plans via Google Play Billing (B16).
///
/// Signals + levels + analysis are FREE; the paywall is on trade automation:
///   * Assist (₹1000/mo) — one-tap "take trade".
///   * Auto   (₹2000/mo) — hands-off auto-execution.
/// Telegram is banned in-region, so the bot paywall reaches no one.  Each
/// purchase is verified server-side by the engine
/// (`POST /api/billing/play/verify`), the entitlement source of truth.  The
/// paid feature is automation *software functionality* run on the user's own
/// exchange keys (Lumin never custodies funds) — not investment advice.
///
/// Product IDs MUST match the Play Console products AND the engine's
/// GOOGLE_PLAY_ASSIST/AUTO_PRODUCT_IDS env.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../data/app_config.dart';
import '../../../data/play_billing_service.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/lumin_card.dart';

/// Play Console subscription product ids (B16 two-tier model).  Keep in
/// lockstep with the engine's GOOGLE_PLAY_ASSIST/AUTO_PRODUCT_IDS env.
///   * Assist (₹1000/mo) — one-tap "take trade".
///   * Auto   (₹2000/mo) — hands-off auto-execution.
const String kAssistMonthlyId = 'lumin_assist_monthly';
const String kAutoMonthlyId = 'lumin_auto_monthly';
const Set<String> kSubscriptionProductIds = {kAssistMonthlyId, kAutoMonthlyId};

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  PlayBillingService? _billing;
  StreamSubscription<PlayBillingEvent>? _eventSub;

  bool _initialised = false;
  bool _available = false;
  bool _loading = true;
  bool _purchaseInFlight = false;
  String? _loadError;
  List<ProductDetails> _products = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final scope = AppConfigScope.of(context);
    final auth = scope.auth;
    if (auth == null) {
      // Mock/preview mode (no live auth) — nothing to purchase against.
      setState(() {
        _loading = false;
        _available = false;
        _loadError = 'Billing is unavailable in preview mode.';
      });
      return;
    }
    final billing = PlayBillingService(repo: scope.repo, auth: auth);
    _billing = billing;
    _eventSub = billing.events.listen(_onBillingEvent);
    billing.start();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final billing = _billing!;
    try {
      final available = await billing.isAvailable();
      if (!available) {
        if (mounted) {
          setState(() {
            _available = false;
            _loading = false;
            _loadError = 'Google Play Billing is not available on this device.';
          });
        }
        return;
      }
      final products = await billing.loadProducts(kSubscriptionProductIds);
      // Cheapest first so Assist (₹1000) renders above Auto (₹2000).
      products.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
      if (mounted) {
        setState(() {
          _available = true;
          _products = products;
          _loading = false;
          _loadError = products.isEmpty
              ? 'No subscription plans are available right now.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load plans: $e';
        });
      }
    }
  }

  void _onBillingEvent(PlayBillingEvent event) {
    if (!mounted) return;
    switch (event.status) {
      case PlayBillingStatus.pending:
        setState(() => _purchaseInFlight = true);
        _snack('Purchase pending…');
        break;
      case PlayBillingStatus.entitled:
        setState(() => _purchaseInFlight = false);
        final t = event.result?.tier == 'auto' ? 'Auto' : 'Assist';
        _snack('$t plan active — automation unlocked.');
        Navigator.of(context).pop(true);
        break;
      case PlayBillingStatus.notEntitled:
        setState(() => _purchaseInFlight = false);
        _snack('Subscription not active (${event.message ?? 'unknown'}).');
        break;
      case PlayBillingStatus.canceled:
        setState(() => _purchaseInFlight = false);
        break;
      case PlayBillingStatus.error:
        setState(() => _purchaseInFlight = false);
        _snack(event.message ?? 'Purchase failed.');
        break;
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _buy(ProductDetails product) async {
    if (_purchaseInFlight) return;
    setState(() => _purchaseInFlight = true);
    try {
      await _billing!.buy(product);
    } catch (e) {
      if (mounted) {
        setState(() => _purchaseInFlight = false);
        _snack('Could not start purchase: $e');
      }
    }
  }

  Future<void> _restore() async {
    try {
      await _billing?.restore();
      _snack('Checking for previous purchases…');
    } catch (e) {
      _snack('Restore failed: $e');
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _billing?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: LuminSpacing.md),
          _heroCard(),
          const SizedBox(height: LuminSpacing.md),
          _tierComparison(),
          const SizedBox(height: LuminSpacing.md),
          _plans(),
          const SizedBox(height: LuminSpacing.sm),
          _restoreButton(),
          const SizedBox(height: LuminSpacing.md),
          _disclaimer(),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              LuminColors.accent.withOpacity(0.18),
              LuminColors.accent.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(LuminRadii.lg),
          border: Border.all(color: LuminColors.accent.withOpacity(0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.workspace_premium, color: LuminColors.accent, size: 32),
            SizedBox(height: LuminSpacing.sm),
            Text(
              'Lumin Pro',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: LuminSpacing.xs),
            Text(
              'All signals, levels and analysis are free. Upgrade to '
              'automate the trades — one-tap with Assist, fully hands-off '
              'with Auto. Trades run on your own exchange keys.',
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

  Widget _tierComparison() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row — Free / Assist / Auto column labels.
            Row(
              children: const [
                Expanded(flex: 5, child: SizedBox()),
                Expanded(child: Center(child: _ColHead('FREE'))),
                Expanded(child: Center(child: _ColHead('ASSIST'))),
                Expanded(child: Center(child: _ColHead('AUTO'))),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            _featureRow('Signals + entry / SL / TP', true, true, true),
            _featureRow('Full 15-evaluator analysis', true, true, true),
            _featureRow('Paper trading', true, true, true),
            _featureRow('One-tap "take trade"', false, true, true),
            _featureRow('Hands-off auto-execution', false, false, true),
            _featureRow('Per-agent & risk controls', false, false, true),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(String label, bool free, bool assist, bool auto) {
    Widget mark(bool on, Color onColor) => Center(
          child: Icon(
            on ? Icons.check_circle : Icons.remove_circle_outline,
            color: on ? onColor : LuminColors.textMuted,
            size: 15,
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(child: mark(free, LuminColors.success)),
          Expanded(child: mark(assist, LuminColors.accent)),
          Expanded(child: mark(auto, LuminColors.accent)),
        ],
      ),
    );
  }

  Widget _plans() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(LuminSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_available || _products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
        child: LuminCard(
          child: Text(
            _loadError ?? 'Subscription plans are unavailable right now.',
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Column(
        children: [
          for (final p in _products) ...[
            _planTile(p),
            const SizedBox(height: LuminSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _planTile(ProductDetails product) {
    final isAuto = product.id == kAutoMonthlyId;
    final label = isAuto ? 'Auto' : 'Assist';
    const unit = '/ month';
    final note = isAuto
        ? 'Hands-off — every eligible signal auto-executed'
        : 'One-tap — take any signal in a tap';
    return Opacity(
      opacity: _purchaseInFlight ? 0.6 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(LuminRadii.md),
          onTap: _purchaseInFlight ? null : () => _buy(product),
          child: Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              color: isAuto
                  ? LuminColors.accent.withOpacity(0.10)
                  : LuminColors.bgCard,
              borderRadius: BorderRadius.circular(LuminRadii.md),
              border: Border.all(
                color: isAuto
                    ? LuminColors.accent.withOpacity(0.50)
                    : LuminColors.cardBorder,
                width: isAuto ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: LuminColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isAuto) ...[
                            const SizedBox(width: LuminSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: LuminSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: LuminColors.accent,
                                borderRadius:
                                    BorderRadius.circular(LuminRadii.pill),
                              ),
                              child: const Text(
                                'RECOMMENDED',
                                style: TextStyle(
                                  color: LuminColors.bgDeep,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note,
                        style: const TextStyle(
                          color: LuminColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      product.price, // Play-formatted, localised currency
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      unit,
                      style: const TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _restoreButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: _available ? _restore : null,
          child: const Text(
            'Restore purchases',
            style: TextStyle(color: LuminColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _disclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Text(
        'Crypto trading carries substantial risk of loss. Assist and Auto '
        'are trade-automation tools that act on your own connected exchange '
        'account with your own keys — not financial advice, and past results '
        'do not guarantee future performance. You are responsible for your '
        'trades. Subscriptions are billed through Google Play and renew '
        'automatically until cancelled; manage or cancel anytime in Google '
        'Play › Subscriptions.',
        style: TextStyle(
          color: LuminColors.textMuted.withOpacity(0.85),
          fontSize: 10,
          height: 1.5,
        ),
      ),
    );
  }
}

/// Small column header used in the Free / Assist / Auto comparison table.
class _ColHead extends StatelessWidget {
  const _ColHead(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: LuminColors.textMuted,
        fontSize: 9,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

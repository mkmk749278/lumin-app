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
import 'package:url_launcher/url_launcher.dart';

import '../../../data/app_config.dart';
import '../../../data/auth_service.dart';
import '../../../data/play_billing_service.dart';
import '../../../data/repository.dart';
import '../../../shared/format.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/free_tier_gate.dart';
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

  /// Current plan, rendered persistently (2026-07-17 — before this the
  /// page showed the identical marketing pitch to a paying Auto
  /// subscriber; the only status signal was a purchase-time snackbar).
  /// Seeded from the cached tier for an instant first frame, then
  /// refreshed from `GET /api/profile` — the engine's truth wins.
  String? _tier;
  String? _paidUntil;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final scope = AppConfigScope.of(context);
    final auth = scope.auth;
    _tier = scope.tier;
    _paidUntil = auth?.currentPaidUntil();
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
    _refreshCurrentPlan(scope.repo, auth);
  }

  /// Engine-truth refresh of the current plan.  Also feeds the
  /// AuthService cache so the Menu subtitle / tier gates update in
  /// lockstep with what this page shows.
  Future<void> _refreshCurrentPlan(LuminRepository repo, AuthService auth) async {
    try {
      final p = await repo.fetchProfile();
      auth.cacheEngineMetadata(
        userId: p.userId,
        tier: p.tier,
        paidUntil: p.paidUntil,
        needsOnboarding: p.needsOnboarding,
        displayName: p.displayName,
      );
      if (mounted) {
        setState(() {
          _tier = p.tier;
          _paidUntil = p.paidUntil;
        });
      }
    } catch (_) {
      // Offline — keep the cached tier already seeded.
    }
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
          _loadError =
              'Could not load plans — check your connection and try again.';
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
        // Stay on the page and flip it into its subscribed state —
        // popping away used to be the only confirmation the user ever
        // saw, which is how "am I even subscribed?" support screenshots
        // happened.
        setState(() {
          _purchaseInFlight = false;
          _tier = event.result?.tier ?? _tier;
          _paidUntil = event.result?.paidUntil ?? _paidUntil;
        });
        final t = tierDisplayName(event.result?.tier);
        _snack('$t plan active — automation unlocked.');
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
    } catch (_) {
      if (mounted) {
        setState(() => _purchaseInFlight = false);
        _snack('Could not start the purchase. Please try again.');
      }
    }
  }

  Future<void> _restore() async {
    try {
      await _billing?.restore();
      _snack('Checking for previous purchases…');
    } catch (_) {
      _snack('Restore did not complete. Please try again.');
    }
  }

  Future<void> _openPlayManage() async {
    final uri = Uri.parse(playManageSubscriptionUrl(_tier));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack('Open Google Play › Subscriptions to manage your plan.');
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
          if (isPaidTier(_tier))
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
              child: CurrentPlanCard(
                tier: _tier,
                paidUntil: _paidUntil,
                onManage: _openPlayManage,
              ),
            )
          else
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
            _featureRow('Full 15-analyst breakdown', true, true, true),
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
    // Subscribed users never re-buy from this page: the owned tile is
    // labelled CURRENT PLAN, and switching plans routes through Google
    // Play's manage screen (a plain buy() would open a second parallel
    // subscription — plan changes need Play-side proration).
    final subscribed = isPaidTier(_tier);
    final ownedProductId = switch ((_tier ?? '').toLowerCase()) {
      'assist' => kAssistMonthlyId,
      'auto' || 'paid' => kAutoMonthlyId,
      _ => null,
    };
    final owned = product.id == ownedProductId;
    return Opacity(
      opacity: _purchaseInFlight ? 0.6 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(LuminRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(LuminRadii.md),
          onTap: _purchaseInFlight
              ? null
              : subscribed
                  ? _openPlayManage
                  : () => _buy(product),
          child: Container(
            padding: const EdgeInsets.all(LuminSpacing.md),
            decoration: BoxDecoration(
              color: owned
                  ? LuminColors.success.withOpacity(0.08)
                  : isAuto
                      ? LuminColors.accent.withOpacity(0.10)
                      : LuminColors.bgCard,
              borderRadius: BorderRadius.circular(LuminRadii.md),
              border: Border.all(
                color: owned
                    ? LuminColors.success.withOpacity(0.55)
                    : isAuto
                        ? LuminColors.accent.withOpacity(0.50)
                        : LuminColors.cardBorder,
                width: (owned || isAuto) ? 1.5 : 1,
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
                          if (owned) ...[
                            const SizedBox(width: LuminSpacing.sm),
                            _pill('CURRENT PLAN', LuminColors.success),
                          ] else if (isAuto && !subscribed) ...[
                            const SizedBox(width: LuminSpacing.sm),
                            _pill('RECOMMENDED', LuminColors.accent),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        owned
                            ? 'Your active plan — tap to manage in Google Play'
                            : subscribed
                                ? 'Switch plans in Google Play'
                                : note,
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

Widget _pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(LuminRadii.pill),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: LuminColors.bgDeep,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );

/// Persistent "you are subscribed" card shown at the top of the
/// Subscription page (and pumped directly in widget tests).  Public so
/// tests don't need billing / scope plumbing.
class CurrentPlanCard extends StatelessWidget {
  const CurrentPlanCard({
    super.key,
    required this.tier,
    required this.paidUntil,
    required this.onManage,
  });

  final String? tier;
  final String? paidUntil;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final renewal = formatPaidUntil(paidUntil);
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            LuminColors.success.withOpacity(0.16),
            LuminColors.success.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(LuminRadii.lg),
        border: Border.all(color: LuminColors.success.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded,
                  color: LuminColors.success, size: 22),
              const SizedBox(width: LuminSpacing.sm),
              const Text(
                'CURRENT PLAN',
                style: TextStyle(
                  color: LuminColors.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.sm),
          Text(
            '${tierDisplayName(tier)} plan',
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: LuminSpacing.xs),
          Text(
            renewal != null
                ? 'Active — renews via Google Play · paid until $renewal'
                : 'Active — renews via Google Play',
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          OutlinedButton.icon(
            onPressed: onManage,
            style: OutlinedButton.styleFrom(
              foregroundColor: LuminColors.textPrimary,
              side: BorderSide(
                color: LuminColors.success.withOpacity(0.45),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: LuminSpacing.lg,
                vertical: LuminSpacing.sm,
              ),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text(
              'Manage in Google Play',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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

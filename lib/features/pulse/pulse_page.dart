/// Pulse — engine status dashboard.
///
/// StreamBuilder against the live repo (or MockRepository when offline)
/// with SWR caching at the repo layer.  Pull-to-refresh invalidates the
/// SWR entry and holds the spinner until fresh data lands (5s timeout),
/// mirroring the Trade tab's pattern — previously the spinner released
/// instantly and users couldn't tell whether the pull triggered a
/// refresh.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/foreground_refresh.dart';
import '../../data/app_config.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import '../../shared/widgets/shimmer.dart';
import '../trade/paper_trades_page.dart';

// _PulseBundle promoted to ``PulseBundle`` in lib/data/repository.dart
// (Phase 2b perf push) so the repository can cache the assembled bundle
// as a single SwrCache entry; the page now consumes it via
// ``watchPulseBundle()`` instead of bundling four fetches itself.
class PulsePage extends StatefulWidget {
  const PulsePage({super.key});

  @override
  State<PulsePage> createState() => _PulsePageState();
}

class _PulsePageState extends State<PulsePage>
    implements ForegroundRefreshable {
  // Stream-based load (Phase 2b perf push) — yields the cached
  // PulseBundle synchronously on subscribe when HttpRepository has a
  // fresh SWR entry, then yields fresh data when the network
  // round-trip completes.  First paint on tab re-entry goes from
  // "spinner during 200-2000ms RTT" to instant.  We listen directly
  // (instead of feeding StreamBuilder) so the pull-to-refresh
  // Completer can signal off the same stream emit that drives the UI.
  StreamSubscription<PulseBundle>? _sub;
  PulseBundle? _data;
  Object? _streamError;
  LuminRepository? _lastRepo;

  /// Set by [_refresh] so it can await the next fresh emit.  Completed
  /// by the stream listener on the post-invalidate emit.  Without
  /// this, RefreshIndicator released its spinner instantly and users
  /// couldn't tell whether the pull actually triggered a refresh.
  /// Same pattern as TradePage._refreshDone.
  Completer<void>? _refreshDone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppConfigScope.of(context).repo;
    if (repo != _lastRepo) {
      _lastRepo = repo;
      _resubscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _resubscribe() {
    _sub?.cancel();
    final repo = AppConfigScope.of(context).repo;
    final stream = repo.watchPulseBundle();
    setState(() {
      _streamError = null;
    });
    _sub = stream.listen(
      (bundle) {
        if (!mounted) return;
        setState(() {
          _data = bundle;
          _streamError = null;
        });
        final done = _refreshDone;
        if (done != null && !done.isCompleted) done.complete();
      },
      onError: (Object e, StackTrace _) {
        if (!mounted) return;
        setState(() => _streamError = e);
        final done = _refreshDone;
        if (done != null && !done.isCompleted) done.complete();
      },
    );
  }

  @override
  void refreshFromForeground() {
    // App returned to foreground on the Pulse tab. Mirror the pull-to-
    // refresh data path (invalidate the bundle key, then resubscribe so the
    // stream refetches) but without the RefreshIndicator spinner — the
    // refresh is silent. `_data` is retained across `_resubscribe`, so the
    // current bundle stays on screen until fresh data lands (no skeleton).
    if (!mounted) return;
    AppConfigScope.of(context).repo.invalidatePulseBundleCache();
    _resubscribe();
  }

  Future<void> _refresh() async {
    // Pull-to-refresh: drop the SWR entry so the resubscribed stream
    // refetches, then hold the spinner until the next emit lands so
    // the gesture has visible feedback (the prior fire-and-forget
    // released the spinner instantly — users couldn't tell whether
    // the refresh actually triggered).  Timeout at 5s so a backend
    // stall doesn't strand the UI in spin-forever.
    final repo = AppConfigScope.of(context).repo;
    final completer = Completer<void>();
    _refreshDone = completer;
    repo.invalidatePulseBundleCache();
    _resubscribe();
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Stream didn't emit within 5s — release the spinner anyway;
      // the page either kept its previous data or shows the error
      // path via the StreamBuilder.
    } finally {
      if (identical(_refreshDone, completer)) _refreshDone = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLive = AppConfigScope.of(context).repo.isLive;
    return Scaffold(
      appBar: AppBar(title: const Text('Pulse')),
      body: RefreshIndicator(
        color: LuminColors.accent,
        onRefresh: _refresh,
        child: AnimatedSwitcher(
          // 200ms cross-fade between skeleton ↔ data so the layout
          // doesn't snap.  Matches the Binance / Robinhood feel where
          // skeletons gently dissolve into populated cards.
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _buildBody(isLive: isLive),
        ),
      ),
    );
  }

  Widget _buildBody({required bool isLive}) {
    final data = _data;
    if (data == null) {
      if (_streamError != null) {
        return _ErrorView(
          key: const ValueKey('pulse-error'),
          error: _streamError.toString(),
          onRetry: _refresh,
          isLive: isLive,
        );
      }
      return const _PulseSkeleton(key: ValueKey('pulse-skeleton'));
    }
    // Past this point `data` is promoted to non-null PulseBundle for
    // the remainder of the method — every child below reads through
    // a single local without inline `!` operators.
    return ListView(
      key: const ValueKey('pulse-data'),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        if (!isLive) const PreviewBadge(),
        _EngineStatusCard(engine: data.engine),
        const SizedBox(height: LuminSpacing.md),
        _RegimeBar(engine: data.engine),
        const SizedBox(height: LuminSpacing.md),
        _TodayPnlCard(userPnl: data.userPnl),
        const SizedBox(height: LuminSpacing.md),
        // 30-day chart is engine-global PnL (per OWNER_BRIEF §3.8
        // single paper book).  Only render to users who're actually
        // trading on the engine — otherwise it's misleading.  Engine-
        // health overview is the EngineStatusCard above.
        if (data.userPnl.hasAnyTrading) ...[
          _PnlChartCard(history: data.pnlHistory),
          const SizedBox(height: LuminSpacing.md),
          _DailyLossBudgetCard(engine: data.engine),
          const SizedBox(height: LuminSpacing.md),
        ],
        if (data.tickers.isNotEmpty) ...[
          _TopPairTickerStrip(tickers: data.tickers),
          const SizedBox(height: LuminSpacing.md),
        ],
        _RecentSignalsCard(recent: data.recent),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cards (data-driven via constructor)
// ---------------------------------------------------------------------------

class _EngineStatusCard extends StatelessWidget {
  const _EngineStatusCard({required this.engine});
  final MockEngineSnapshot engine;

  @override
  Widget build(BuildContext context) {
    final isHealthy = engine.status == 'Healthy';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isHealthy ? LuminColors.success : LuminColors.warn,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isHealthy ? LuminColors.success : LuminColors.warn)
                        .withOpacity(0.4),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Engine ${engine.status.toLowerCase()}',
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Up ${engine.uptime} • scanning 75 pairs',
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.flash_on, color: LuminColors.accent, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Horizontal regime bar — five segments (one per regime), the active one
/// glows in its semantic accent.  Drops the previous "X% trending" subtitle
/// (the engine still hardcodes that field to 0 in `build_pulse`) and gives
/// subscribers an at-a-glance read of the current market state.
class _RegimeBar extends StatelessWidget {
  const _RegimeBar({required this.engine});
  final MockEngineSnapshot engine;

  static const _segments = <String>[
    'TRENDING_UP',
    'RANGING',
    'QUIET',
    'VOLATILE',
    'TRENDING_DOWN',
  ];

  static Color _colorFor(String regime) {
    switch (regime) {
      case 'TRENDING_UP':
        return LuminColors.success;
      case 'TRENDING_DOWN':
        return LuminColors.loss;
      case 'RANGING':
        return LuminColors.accent;
      case 'VOLATILE':
        return LuminColors.warn;
      case 'QUIET':
      default:
        return LuminColors.textMuted;
    }
  }

  static String _labelFor(String regime) {
    switch (regime) {
      case 'TRENDING_UP':
        return 'Trend ↑';
      case 'TRENDING_DOWN':
        return 'Trend ↓';
      case 'RANGING':
        return 'Range';
      case 'VOLATILE':
        return 'Volatile';
      case 'QUIET':
      default:
        return 'Quiet';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _colorFor(engine.regime);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bar_chart_outlined, size: 16, color: activeColor),
                const SizedBox(width: 6),
                const Text(
                  'Regime',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  _labelFor(engine.regime).toUpperCase(),
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            Row(
              children: List.generate(_segments.length, (i) {
                final regime = _segments[i];
                final active = regime == engine.regime;
                final c = _colorFor(regime);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == _segments.length - 1 ? 0 : 4,
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: active ? c : c.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: active
                                ? [
                                    BoxShadow(
                                      color: c.withOpacity(0.5),
                                      blurRadius: 6,
                                      spreadRadius: 0,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _labelFor(regime),
                          style: TextStyle(
                            color: active ? c : LuminColors.textMuted,
                            fontSize: 9,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's P&L — promoted from a half-row stat to a full-width card now
/// that the regime bar takes the row above.  Reads cleaner and gives the
/// number the prominence the audit asked for.
///
/// 2026-05 — Paper visibility: a "View all trades →" footer link routes
/// to :class:`PaperTradesPage` so the daily aggregate has a one-tap
/// drill-down to the per-trade ledger.  The Today/Weekly/Monthly
/// aggregate layout above stays untouched.
/// Per-user PnL card.  Renders the user's own realised PnL from
/// server-side execution positions (B18) — not the engine-global
/// number that was leaking across all users pre-2026-05-22.
///
/// Two render modes:
///   * Active trader (``userPnl.hasAnyTrading``): show realised USD +
///     open-position count + "View all trades" deep-link.
///   * Not enabled yet: show "Trading not enabled" CTA pointing to
///     the Trade tab.  Avoids the previous bug where every signed-in
///     user — even brand-new accounts that hadn't opted in — saw the
///     engine's shared PnL as if it were theirs.
class _TodayPnlCard extends StatelessWidget {
  const _TodayPnlCard({required this.userPnl});
  final UserPnlSnapshot userPnl;

  @override
  Widget build(BuildContext context) {
    if (!userPnl.hasAnyTrading) {
      return const _NotTradingYetCard();
    }
    final positive = userPnl.realisedUsd >= 0;
    final color = positive ? LuminColors.success : LuminColors.loss;
    final openSubtitle = userPnl.openPositionCount == 1
        ? '1 open position'
        : '${userPnl.openPositionCount} open positions';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  positive ? Icons.trending_up : Icons.trending_down,
                  size: 22,
                  color: color,
                ),
                const SizedBox(width: LuminSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "YOUR REALISED P&L",
                      style: TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      openSubtitle,
                      style: const TextStyle(
                        color: LuminColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '${positive ? '+' : ''}\$${userPnl.realisedUsd.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Divider(color: LuminColors.cardBorder, height: 1),
            const SizedBox(height: 4),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(LuminRadii.sm),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PaperTradesPage(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 2,
                  ),
                  child: Row(
                    children: const [
                      Text(
                        'View all trades',
                        style: TextStyle(
                          color: LuminColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: LuminColors.accent,
                      ),
                    ],
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

/// Empty-state card for users who haven't enabled trading yet.
/// Replaces the engine-global PnL number that was previously rendered
/// to every signed-in user.
class _NotTradingYetCard extends StatelessWidget {
  const _NotTradingYetCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: LuminColors.accent.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.rocket_launch_outlined,
                color: LuminColors.accent,
                size: 22,
              ),
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "YOUR REALISED P&L",
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Trading not enabled yet',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Connect Binance on the Trade tab to start '
                    'auto-trading signals on your own account.',
                    style: TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyLossBudgetCard extends StatelessWidget {
  const _DailyLossBudgetCard({required this.engine});
  final MockEngineSnapshot engine;

  @override
  Widget build(BuildContext context) {
    final used = engine.dailyLossUsedUsd.abs();
    final budget = engine.dailyLossBudgetUsd;
    final pct = budget == 0 ? 0.0 : (used / budget).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: LuminColors.accent, size: 16),
                const SizedBox(width: LuminSpacing.xs),
                const Text(
                  'DAILY LOSS BUDGET',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '\$${used.toStringAsFixed(2)} / \$${budget.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(LuminRadii.pill),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: LuminColors.bgElevated,
                valueColor: AlwaysStoppedAnimation(
                  pct < 0.7
                      ? LuminColors.success
                      : pct < 0.95
                          ? LuminColors.warn
                          : LuminColors.loss,
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.xs),
            Text(
              pct < 0.01
                  ? 'No losses today — budget intact'
                  : '${(pct * 100).toStringAsFixed(0)}% of daily budget used',
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 30-day P&L chart + weekly/monthly summary header.
///
/// Owner audit (2026-05-08): "Daily, Weekly and monthly PnL along Daily PnL
/// Chat".  Sources from ``/api/pnl/history`` (engine PR #338); since
/// 2026-05-24 the engine filters the paper series per user by their
/// paper-subscription windows when the caller carries a user_id token,
/// so the chart shows trades that closed while THIS user had paper
/// auto-trade on — not engine-wide. Label was renamed from
/// "ENGINE — LAST 30 DAYS" to make the per-user scope explicit.
class _PnlChartCard extends StatelessWidget {
  const _PnlChartCard({required this.history});
  final PnlHistory history;

  @override
  Widget build(BuildContext context) {
    final hasData = history.items.any((p) => p.pnlUsd != 0.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.show_chart, size: 16, color: LuminColors.accent),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'YOUR PAPER P&L — LAST 30 DAYS',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Single shared paper book per OWNER_BRIEF §3.8 —
                // this chart aggregates every signal across the
                // project, not the viewing user's own trades.  Per-
                // user lifetime history ships when the engine adds
                // a per-user PnL endpoint.
                Text(
                  'shared',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 9,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PnlAggregateCell(
                    label: 'Weekly',
                    value: history.weeklyPnlUsd,
                    subtitle: 'Last 7 days',
                  ),
                ),
                Expanded(
                  child: _PnlAggregateCell(
                    label: 'Monthly',
                    value: history.monthlyPnlUsd,
                    subtitle: 'Last 30 days',
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            SizedBox(
              height: 90,
              child: hasData
                  ? CustomPaint(
                      painter: _PnlBarChartPainter(items: history.items),
                      child: const SizedBox.expand(),
                    )
                  : const _PnlChartEmptyState(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PnlAggregateCell extends StatelessWidget {
  const _PnlAggregateCell({
    required this.label,
    required this.value,
    required this.subtitle,
  });
  final String label;
  final double value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final positive = value >= 0;
    final color = positive ? LuminColors.success : LuminColors.loss;
    final formatted =
        '${positive ? '+' : ''}\$${value.toStringAsFixed(2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: LuminColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatted,
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(
            color: LuminColors.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _PnlChartEmptyState extends StatelessWidget {
  const _PnlChartEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LuminColors.bgElevated.withOpacity(0.5),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
      ),
      alignment: Alignment.center,
      child: const Text(
        'No closed trades in the last 30 days yet.',
        style: TextStyle(
          color: LuminColors.textMuted,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Custom-painted bar chart — one bar per UTC day.  Wins green, losses
/// red, zero days a thin baseline tick so subscribers can read the
/// trade cadence at a glance.
class _PnlBarChartPainter extends CustomPainter {
  _PnlBarChartPainter({required this.items});
  final List<PnlPoint> items;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;
    final maxAbs = items
        .map((p) => p.pnlUsd.abs())
        .fold<double>(0.0, (a, b) => a > b ? a : b);
    if (maxAbs == 0.0) return;

    final n = items.length;
    final spacing = 2.0;
    final usable = size.width - spacing * (n - 1);
    final barWidth = usable / n;
    final centerY = size.height / 2;
    final maxBarHeight = size.height / 2 - 4;

    final winPaint = Paint()..color = LuminColors.success;
    final lossPaint = Paint()..color = LuminColors.loss;
    final zeroPaint = Paint()
      ..color = LuminColors.textMuted.withOpacity(0.35);
    final axisPaint = Paint()
      ..color = LuminColors.cardBorder
      ..strokeWidth = 1;

    // Faint horizontal axis at zero.
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      axisPaint,
    );

    for (int i = 0; i < n; i++) {
      final p = items[i];
      final x = i * (barWidth + spacing);
      if (p.pnlUsd == 0.0) {
        // Zero-day tick — keeps the x-axis cadence readable.
        canvas.drawRect(
          Rect.fromLTWH(x, centerY - 0.5, barWidth, 1.0),
          zeroPaint,
        );
        continue;
      }
      final h = (p.pnlUsd.abs() / maxAbs) * maxBarHeight;
      final paint = p.pnlUsd > 0 ? winPaint : lossPaint;
      final y = p.pnlUsd > 0 ? centerY - h : centerY;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PnlBarChartPainter old) =>
      old.items != items;
}

class _TopPairTickerStrip extends StatelessWidget {
  const _TopPairTickerStrip({required this.tickers});
  final List<MockTicker> tickers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: LuminSpacing.sm),
              child: Text(
                'Top pairs',
                style: TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: tickers.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: LuminSpacing.md),
                itemBuilder: (_, i) => _TickerPill(ticker: tickers[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TickerPill extends StatelessWidget {
  const _TickerPill({required this.ticker});
  final MockTicker ticker;

  @override
  Widget build(BuildContext context) {
    final positive = ticker.changePct24h >= 0;
    final color = positive ? LuminColors.success : LuminColors.loss;
    // Strip the "USDT" suffix for a cleaner pill.
    final label = ticker.symbol.endsWith('USDT')
        ? ticker.symbol.substring(0, ticker.symbol.length - 4)
        : ticker.symbol;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: LuminColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                formatPrice(ticker.price),
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                formatPct(ticker.changePct24h, decimals: 2),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentSignalsCard extends StatelessWidget {
  const _RecentSignalsCard({required this.recent});
  final List<MockSignal> recent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.history, color: LuminColors.accent, size: 16),
                SizedBox(width: LuminSpacing.xs),
                Text(
                  'RECENT SIGNALS',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            if (recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: LuminSpacing.lg),
                child: Center(
                  child: Text(
                    'No signals yet',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              for (final sig in recent) _RecentSignalRow(sig: sig),
          ],
        ),
      ),
    );
  }
}

class _RecentSignalRow extends StatelessWidget {
  const _RecentSignalRow({required this.sig});
  final MockSignal sig;

  Color _statusColor() {
    switch (sig.status) {
      case 'TP1_HIT':
      case 'TP2_HIT':
      case 'TP3_HIT':
        return LuminColors.success;
      case 'SL_HIT':
        return LuminColors.loss;
      case 'INVALIDATED':
        return LuminColors.textMuted;
      default:
        return LuminColors.accent;
    }
  }

  String _agoLabel() {
    if (sig.minutesAgo < 60) return '${sig.minutesAgo}m ago';
    if (sig.minutesAgo < 1440) return '${(sig.minutesAgo / 60).round()}h ago';
    return '${(sig.minutesAgo / 1440).round()}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final pnlPositive = sig.pnlPct >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LuminSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: _statusColor(),
              borderRadius: BorderRadius.circular(LuminRadii.pill),
            ),
          ),
          const SizedBox(width: LuminSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      sig.symbol,
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: LuminSpacing.xs),
                    Text(
                      sig.direction,
                      style: TextStyle(
                        color: sig.direction == 'LONG'
                            ? LuminColors.success
                            : LuminColors.loss,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: LuminSpacing.xs),
                    Text(
                      '• ${sig.status}',
                      style: TextStyle(
                        color: _statusColor(),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${sig.agentName} • ${_agoLabel()}',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${pnlPositive ? '+' : ''}${sig.pnlPct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: pnlPositive ? LuminColors.success : LuminColors.loss,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading + error views (shared across pages)
// ---------------------------------------------------------------------------

/// Section-shaped placeholder rendered while the SWR cache has no
/// entry yet (typically cold start).  Mirrors the real Pulse page
/// layout: engine card + regime bar + PnL card + chart card + budget
/// card + ticker strip + signals card.  Static gray boxes — no
/// shimmer dep added in this phase; the layout match alone delivers
/// the perceived-speed win.
class _PulseSkeleton extends StatelessWidget {
  const _PulseSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Single Shimmer ancestor — shaders compose cheaper as one mask
    // over the whole list than per-card.  ScrollPhysics matches the
    // populated list so pull-to-refresh still works while loading.
    return Shimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.md,
          vertical: LuminSpacing.sm,
        ),
        children: const [
          _PulseSkeletonCard(height: 92), // EngineStatus
          SizedBox(height: LuminSpacing.md),
          _PulseSkeletonCard(height: 44), // RegimeBar
          SizedBox(height: LuminSpacing.md),
          _PulseSkeletonCard(height: 96), // TodayPnl
          SizedBox(height: LuminSpacing.md),
          _PulseSkeletonCard(height: 180), // PnlChart
          SizedBox(height: LuminSpacing.md),
          _PulseSkeletonCard(height: 64), // DailyLossBudget
          SizedBox(height: LuminSpacing.md),
          _PulseSkeletonCard(height: 56), // Ticker strip
          SizedBox(height: LuminSpacing.md),
          _PulseSkeletonCard(height: 156), // RecentSignals (3 rows)
          SizedBox(height: LuminSpacing.xl),
        ],
      ),
    );
  }
}

class _PulseSkeletonCard extends StatelessWidget {
  const _PulseSkeletonCard({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LuminColors.cardBorder),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    required this.isLive,
  });
  final String error;
  final Future<void> Function() onRetry;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(LuminSpacing.lg),
      children: [
        const SizedBox(height: LuminSpacing.xxl),
        const Icon(Icons.cloud_off, color: LuminColors.loss, size: 48),
        const SizedBox(height: LuminSpacing.md),
        const Text(
          'Could not reach engine',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: LuminColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LuminSpacing.sm),
        Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LuminColors.textSecondary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: LuminSpacing.lg),
        Center(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.accent,
              foregroundColor: LuminColors.bgDeep,
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ),
        if (isLive) ...[
          const SizedBox(height: LuminSpacing.sm),
          const Center(
            child: Text(
              'Pull down to refresh, or check Menu → API keys.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LuminColors.textMuted, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }
}

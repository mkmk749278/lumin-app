/// Pulse — engine status dashboard.
///
/// FutureBuilder against the live repo (or MockRepository when offline).
/// Pull-to-refresh re-fetches; tier-conditional rendering hooks added so
/// v0.0.8+ can hide paid-only widgets without restructuring the page.
import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
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

class _PulsePageState extends State<PulsePage> {
  // Stream-based load (Phase 2b perf push) — yields the cached
  // PulseBundle synchronously on subscribe when HttpRepository has a
  // fresh SWR entry, then yields fresh data when the network
  // round-trip completes.  First paint on tab re-entry goes from
  // "spinner during 200-2000ms RTT" to instant.
  late Stream<PulseBundle> _stream;
  LuminRepository? _lastRepo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppConfigScope.of(context).repo;
    if (repo != _lastRepo) {
      _lastRepo = repo;
      _resubscribe();
    }
  }

  void _resubscribe() {
    final repo = AppConfigScope.of(context).repo;
    setState(() {
      _stream = repo.watchPulseBundle();
    });
  }

  Future<void> _refresh() async {
    // Pull-to-refresh: drop the SWR entry so the next emit re-fetches
    // instead of serving stale.  We deliberately don't await the stream
    // — StreamBuilder repaints when fresh data lands, and
    // RefreshIndicator releases its spinner immediately.
    final repo = AppConfigScope.of(context).repo;
    repo.invalidatePulseBundleCache();
    _resubscribe();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pulse')),
      body: RefreshIndicator(
        color: LuminColors.accent,
        onRefresh: _refresh,
        child: StreamBuilder<PulseBundle>(
          stream: _stream,
          builder: (context, snap) {
            if (!snap.hasData && snap.connectionState != ConnectionState.done) {
              return const _PulseSkeleton();
            }
            if (snap.hasError && !snap.hasData) {
              return _ErrorView(
                error: snap.error.toString(),
                onRetry: _refresh,
                isLive: scope.repo.isLive,
              );
            }
            final data = snap.data!;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                if (!scope.repo.isLive) const PreviewBadge(),
                _EngineStatusCard(engine: data.engine),
                const SizedBox(height: LuminSpacing.md),
                _RegimeBar(engine: data.engine),
                const SizedBox(height: LuminSpacing.md),
                _TodayPnlCard(engine: data.engine),
                const SizedBox(height: LuminSpacing.md),
                _PnlChartCard(history: data.pnlHistory),
                const SizedBox(height: LuminSpacing.md),
                _DailyLossBudgetCard(engine: data.engine),
                const SizedBox(height: LuminSpacing.md),
                if (data.tickers.isNotEmpty) ...[
                  _TopPairTickerStrip(tickers: data.tickers),
                  const SizedBox(height: LuminSpacing.md),
                ],
                _RecentSignalsCard(recent: data.recent),
                const SizedBox(height: LuminSpacing.xl),
              ],
            );
          },
        ),
      ),
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
class _TodayPnlCard extends StatelessWidget {
  const _TodayPnlCard({required this.engine});
  final MockEngineSnapshot engine;

  @override
  Widget build(BuildContext context) {
    final positive = engine.todayPnlUsd >= 0;
    final color = positive ? LuminColors.success : LuminColors.loss;
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
                  children: const [
                    Text(
                      "TODAY'S P&L",
                      style: TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Realised across paper / live trades',
                      style: TextStyle(
                        color: LuminColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${positive ? '+' : ''}\$${engine.todayPnlUsd.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      '${positive ? '+' : ''}${engine.todayPnlPct.toStringAsFixed(2)}% on margin',
                      style: TextStyle(
                        color: color.withOpacity(0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            const Divider(color: LuminColors.cardBorder, height: 1),
            const SizedBox(height: 4),
            // Drill-down to the paginated per-trade ledger — owner asked
            // for honest "what would I have earned" context next to the
            // aggregate number.
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
/// Chat".  Sources from the engine's persistent ``pnl_history.json`` ledger
/// via the ``/api/pnl/history`` endpoint (engine PR #338).
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
                Text(
                  'P&L — LAST 30 DAYS',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
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
  const _PulseSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
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

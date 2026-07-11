/// Alerts — 100eyes-class market alert feed (Pulse → Alerts top tab).
///
/// Informational detector events (RSI extremes, RSI divergence, abnormal
/// volatility, near horizontal S/R, volume anomaly), each stamped with
/// the detector's natural timeframe (15m / 1h / 4h).  NOT trade signals:
/// no entry/SL/TP, no accountability — "look here now" nudges.  Tap a
/// card to open the symbol's chart.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/market_alert.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import '../charts/chart_page.dart';

class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});

  @override
  State<AlertsTab> createState() => AlertsTabState();
}

class AlertsTabState extends State<AlertsTab>
    with AutomaticKeepAliveClientMixin {
  StreamSubscription<List<MarketAlert>>? _sub;
  List<MarketAlert>? _alerts;
  Object? _streamError;
  LuminRepository? _lastRepo;
  Completer<void>? _refreshDone;

  /// 100eyes-style client-side feed filters: alert family + timeframe.
  /// Null = All.  Session-only — the feed itself is untouched.
  String? _familyFilter;
  String? _tfFilter;

  static const Map<String, List<String>> _families = {
    'RSI': ['RSI_OVERBOUGHT', 'RSI_OVERSOLD'],
    'Divergence': ['RSI_BULLISH_DIVERGENCE', 'RSI_BEARISH_DIVERGENCE'],
    'S/R': ['NEAR_SUPPORT', 'NEAR_RESISTANCE'],
    'Volume': ['VOLUME_SPIKE', 'ABNORMAL_VOLATILITY'],
  };

  List<MarketAlert> _filtered(List<MarketAlert> alerts) {
    return [
      for (final a in alerts)
        if ((_familyFilter == null ||
                (_families[_familyFilter]?.contains(a.alertType) ?? true)) &&
            (_tfFilter == null || a.timeframe == _tfFilter))
          a,
    ];
  }

  /// Keep the feed alive across top-tab switches — same reason the
  /// bottom tabs use IndexedStack: don't refetch on every swipe back.
  @override
  bool get wantKeepAlive => true;

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
    setState(() => _streamError = null);
    _sub = repo.watchAlerts().listen(
      (alerts) {
        if (!mounted) return;
        setState(() {
          _alerts = alerts;
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

  /// Silent refetch — used by the Pulse page's foreground-refresh hook.
  /// Current feed stays on screen until fresh data lands.
  void refreshSilently() {
    if (!mounted) return;
    AppConfigScope.of(context).repo.invalidateAlertsCache();
    _resubscribe();
  }

  Future<void> _refresh() async {
    final repo = AppConfigScope.of(context).repo;
    final completer = Completer<void>();
    _refreshDone = completer;
    repo.invalidateAlertsCache();
    _resubscribe();
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Backend stall — release the spinner; previous data stays up.
    } finally {
      if (identical(_refreshDone, completer)) _refreshDone = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isLive = AppConfigScope.of(context).repo.isLive;
    return RefreshIndicator(
      color: LuminColors.accent,
      onRefresh: _refresh,
      child: _buildBody(isLive: isLive),
    );
  }

  Widget _buildBody({required bool isLive}) {
    final alerts = _alerts;
    if (alerts == null) {
      if (_streamError != null) {
        return _AlertsErrorView(
          error: _streamError.toString(),
          onRetry: _refresh,
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: LuminColors.accent),
      );
    }
    if (alerts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.notifications_none, size: 48, color: LuminColors.textMuted),
          SizedBox(height: LuminSpacing.md),
          Center(
            child: Text(
              'No market alerts yet',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: LuminSpacing.xs),
          Center(
            child: Text(
              'RSI extremes, divergences, volatility and\n'
              'S/R proximity alerts will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: LuminColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      );
    }
    final visible = _filtered(alerts);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.lg,
        vertical: LuminSpacing.md,
      ),
      children: [
        _buildFilterRow(),
        const SizedBox(height: LuminSpacing.sm),
        if (!isLive) ...[
          const PreviewBadge(),
          const SizedBox(height: LuminSpacing.sm),
        ],
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                'No alerts match this filter',
                style: TextStyle(color: LuminColors.textSecondary, fontSize: 12),
              ),
            ),
          )
        else
          for (final a in visible) ...[
            _AlertCard(alert: a),
            const SizedBox(height: LuminSpacing.sm),
          ],
      ],
    );
  }

  Widget _buildFilterRow() {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          selected: selected,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('All', _familyFilter == null && _tfFilter == null, () {
            setState(() {
              _familyFilter = null;
              _tfFilter = null;
            });
          }),
          for (final f in _families.keys)
            chip(f, _familyFilter == f, () {
              setState(
                () => _familyFilter = _familyFilter == f ? null : f,
              );
            }),
          for (final tf in const ['15m', '1h', '4h'])
            chip(tf, _tfFilter == tf, () {
              setState(() => _tfFilter = _tfFilter == tf ? null : tf);
            }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alert card
// ---------------------------------------------------------------------------

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final MarketAlert alert;

  static IconData _iconFor(String type) {
    switch (type) {
      case 'RSI_OVERBOUGHT':
        return Icons.north_east;
      case 'RSI_OVERSOLD':
        return Icons.south_east;
      case 'RSI_BULLISH_DIVERGENCE':
      case 'RSI_BEARISH_DIVERGENCE':
        return Icons.call_split;
      case 'ABNORMAL_VOLATILITY':
        return Icons.bolt;
      case 'VOLUME_SPIKE':
        return Icons.equalizer;
      case 'NEAR_SUPPORT':
        return Icons.vertical_align_bottom;
      case 'NEAR_RESISTANCE':
        return Icons.vertical_align_top;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  Color _biasColor() {
    switch (alert.bias) {
      case 'BULLISH':
        return LuminColors.success;
      case 'BEARISH':
        return LuminColors.loss;
      default:
        return LuminColors.warn;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _biasColor();
    final label = alert.symbol.endsWith('USDT')
        ? alert.symbol.substring(0, alert.symbol.length - 4)
        : alert.symbol;
    return LuminCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChartPage(symbol: alert.symbol, alert: alert),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(alert.alertType), color: color, size: 19),
            ),
            const SizedBox(width: LuminSpacing.md),
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: LuminSpacing.xs),
                      _TimeframeChip(timeframe: alert.timeframe),
                      const Spacer(),
                      Text(
                        alert.agoLabel(),
                        style: const TextStyle(
                          color: LuminColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.title,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.message,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                      height: 1.35,
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

class _TimeframeChip extends StatelessWidget {
  const _TimeframeChip({required this.timeframe});
  final String timeframe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(LuminRadii.pill),
        border: Border.all(color: LuminColors.cardBorder),
      ),
      child: Text(
        timeframe,
        style: const TextStyle(
          color: LuminColors.textSecondary,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _AlertsErrorView extends StatelessWidget {
  const _AlertsErrorView({required this.error, required this.onRetry});
  final String error;
  final Future<void> Function() onRetry;

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
          'Could not load alerts',
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
      ],
    );
  }
}

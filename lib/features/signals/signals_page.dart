/// Signals — live + closed feed.
///
/// Filter chips trigger a re-fetch via the repository.  When the
/// "Closed" filter is active, a second row of sub-filter chips appears
/// (All / TP / SL / Invalidated / Expired) and is applied client-side
/// so we don't multiply API requests for what is essentially a status
/// projection of the same closed-pool.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/app_config.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import '../../shared/widgets/shimmer.dart';
import 'take_signal_sheet.dart';

/// Fetch mark prices for a batch of symbols from Binance's public
/// premiumIndex endpoint.  Fires requests concurrently; any individual
/// failure is silently dropped so a single bad symbol can't block the
/// rest.  Returns a map of symbol → mark price for every symbol that
/// responded successfully.
Future<Map<String, double>> _fetchMarkPrices(List<String> symbols) async {
  if (symbols.isEmpty) return const {};
  final client = http.Client();
  try {
    final results = await Future.wait(
      symbols.map((sym) async {
        try {
          final uri = Uri.parse(
              'https://fapi.binance.com/fapi/v1/premiumIndex?symbol=$sym');
          final resp = await client.get(uri).timeout(const Duration(seconds: 8));
          if (resp.statusCode != 200) return MapEntry(sym, 0.0);
          final j = jsonDecode(resp.body);
          if (j is Map<String, dynamic> && j['markPrice'] != null) {
            final price = double.tryParse(j['markPrice'].toString()) ?? 0.0;
            return MapEntry(sym, price);
          }
          return MapEntry(sym, 0.0);
        } catch (_) {
          return MapEntry(sym, 0.0);
        }
      }),
      eagerError: false,
    );
    final out = <String, double>{};
    for (final e in results) {
      if (e.value > 0) out[e.key] = e.value;
    }
    return out;
  } finally {
    client.close();
  }
}

enum _SignalFilter { all, open, closed }

extension _FilterStr on _SignalFilter {
  String get apiValue {
    switch (this) {
      case _SignalFilter.open:
        return 'open';
      case _SignalFilter.closed:
        return 'closed';
      case _SignalFilter.all:
        return 'all';
    }
  }

  String get label =>
      '${name[0].toUpperCase()}${name.substring(1)}';
}

enum _ClosedSubFilter { all, tp, sl, invalidated, expired }

extension _SubFilterStr on _ClosedSubFilter {
  String get label {
    switch (this) {
      case _ClosedSubFilter.all:
        return 'All';
      case _ClosedSubFilter.tp:
        return 'TP';
      case _ClosedSubFilter.sl:
        return 'SL';
      case _ClosedSubFilter.invalidated:
        return 'Invalidated';
      case _ClosedSubFilter.expired:
        return 'Expired';
    }
  }
}

/// Detect post-pre-TP-grab BE-ratchet state.  The engine moves
/// ``stop_loss`` to ``entry`` after pre-TP fires (per OWNER_BRIEF
/// §3.2a capital-preservation doctrine) so subscribers can recognise
/// "this signal is now risk-free; residual riding for TP1".  Both
/// signals — the explicit ``preTpHit`` flag and the numeric SL==entry
/// equivalence — are honoured so the badge still surfaces if a
/// pre-PR-411 cached signal didn't get the flag set.
bool _isBreakeven(MockSignal s) {
  if (s.preTpHit) return true;
  if (s.entry <= 0) return false;
  // Allow for float-precision wobble within 1e-9 of full equality.
  return (s.sl - s.entry).abs() / s.entry < 1e-6;
}

bool _matchesSubFilter(MockSignal s, _ClosedSubFilter f) {
  switch (f) {
    case _ClosedSubFilter.all:
      return true;
    case _ClosedSubFilter.tp:
      return s.status == 'TP1_HIT' ||
          s.status == 'TP2_HIT' ||
          s.status == 'TP3_HIT' ||
          s.status == 'FULL_TP_HIT';
    case _ClosedSubFilter.sl:
      return s.status == 'SL_HIT';
    case _ClosedSubFilter.invalidated:
      return s.status == 'INVALIDATED' || s.status == 'CANCELLED';
    case _ClosedSubFilter.expired:
      return s.status == 'EXPIRED';
  }
}

class SignalsPage extends StatefulWidget {
  const SignalsPage({super.key});

  @override
  State<SignalsPage> createState() => _SignalsPageState();
}

class _SignalsPageState extends State<SignalsPage> {
  _SignalFilter _filter = _SignalFilter.all;
  _ClosedSubFilter _subFilter = _ClosedSubFilter.all;
  // Stream-based load (Phase 2a perf push) — yields cached signals
  // synchronously on subscribe when ``HttpRepository`` has a fresh SWR
  // entry, then yields fresh data when the network round-trip
  // completes.  We listen directly (instead of feeding StreamBuilder)
  // so pull-to-refresh's Completer can signal off the same emit that
  // drives the UI — matching the Trade tab's spinner-holds-until-done
  // pattern.
  StreamSubscription<List<MockSignal>>? _sub;
  List<MockSignal>? _data;
  Object? _streamError;
  LuminRepository? _lastRepo;

  /// Completed by the stream listener on the post-invalidate emit so
  /// [_refresh] can hold the RefreshIndicator spinner until fresh
  /// data lands.  Same pattern as PulsePage / TradePage.
  Completer<void>? _refreshDone;

  /// Live Binance mark prices — polled every 5 s for ACTIVE signals.
  /// Key = symbol (e.g. "CHZUSDT"), value = latest mark price.
  /// Only populated when ``isLive == true`` and at least one ACTIVE
  /// signal is visible.  Empty in mock/preview mode — the card falls
  /// back to the static ``MockSignal.currentPrice`` field.
  final Map<String, double> _livePrices = {};
  Timer? _priceTimer;

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
    _priceTimer?.cancel();
    super.dispose();
  }

  /// Returns the unique set of symbols for ACTIVE signals in the current
  /// list.  Used to decide which symbols need live price polling.
  List<String> _activeSymbols() {
    final data = _data;
    if (data == null) return const [];
    final seen = <String>{};
    for (final s in data) {
      if (s.status == 'ACTIVE') seen.add(s.symbol);
    }
    return seen.toList();
  }

  /// Starts or restarts the live-price polling timer.  Cancels any
  /// existing timer first, then fires immediately and every 5 s.
  /// No-op when in mock/preview mode or when no ACTIVE signals are
  /// visible — avoids redundant Binance requests.
  void _restartPricePolling() {
    _priceTimer?.cancel();
    _priceTimer = null;
    // Only poll for live data — mock mode uses static fixture prices.
    if (!(_lastRepo?.isLive ?? false)) return;
    final syms = _activeSymbols();
    if (syms.isEmpty) return;
    _priceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _doFetchPrices();
    });
    // Fire immediately on start so prices appear without a 5 s delay.
    _doFetchPrices();
  }

  Future<void> _doFetchPrices() async {
    final syms = _activeSymbols();
    if (syms.isEmpty) {
      _priceTimer?.cancel();
      _priceTimer = null;
      return;
    }
    final fresh = await _fetchMarkPrices(syms);
    if (!mounted) return;
    if (fresh.isNotEmpty) {
      setState(() => _livePrices.addAll(fresh));
    }
  }

  void _resubscribe() {
    _sub?.cancel();
    final repo = AppConfigScope.of(context).repo;
    final stream = repo.watchSignals(status: _filter.apiValue, limit: 100);
    setState(() {
      _streamError = null;
    });
    _sub = stream.listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _data = items;
          _streamError = null;
        });
        _restartPricePolling();
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

  Future<void> _refresh() async {
    // Pull-to-refresh: invalidate the SWR entry, resubscribe to a
    // fresh stream, and hold the spinner until the next emit lands
    // (or 5s elapses).  Prior implementation released the spinner
    // instantly and users couldn't tell whether the pull triggered
    // a refresh — same regression the Trade tab fixed earlier.
    final repo = AppConfigScope.of(context).repo;
    final completer = Completer<void>();
    _refreshDone = completer;
    repo.invalidateSignalsCache(status: _filter.apiValue, limit: 100);
    _resubscribe();
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Stream didn't emit within 5s — release the spinner anyway.
    } finally {
      if (identical(_refreshDone, completer)) _refreshDone = null;
    }
  }

  void _setFilter(_SignalFilter f) {
    if (f == _filter) return;
    _priceTimer?.cancel();
    _priceTimer = null;
    setState(() {
      _filter = f;
      // Reset sub-filter when switching primary chip — hidden when not Closed.
      _subFilter = _ClosedSubFilter.all;
      // Clear data on filter change — the existing list is for a
      // different status projection so showing it while the new one
      // loads would be misleading.  Pull-to-refresh keeps data
      // visible (SWR stale-while-revalidate); filter-tap doesn't.
      _data = null;
    });
    _resubscribe();
  }

  void _setSubFilter(_ClosedSubFilter f) {
    if (f == _subFilter) return;
    setState(() => _subFilter = f);
  }

  @override
  Widget build(BuildContext context) {
    final isLive = AppConfigScope.of(context).repo.isLive;
    return Scaffold(
      appBar: AppBar(title: const Text('Signals')),
      body: Column(
        children: [
          if (!isLive) const PreviewBadge(),
          _FilterRow(current: _filter, onChanged: _setFilter),
          if (_filter == _SignalFilter.closed) ...[
            const SizedBox(height: LuminSpacing.sm),
            _SubFilterRow(current: _subFilter, onChanged: _setSubFilter),
          ],
          const SizedBox(height: LuminSpacing.sm),
          Expanded(
            child: RefreshIndicator(
              color: LuminColors.accent,
              onRefresh: _refresh,
              child: AnimatedSwitcher(
                // 200ms cross-fade between skeleton ↔ data so the
                // layout doesn't snap.  Matches PulsePage's pattern.
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _buildList(isLive: isLive),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList({required bool isLive}) {
    if (_data == null && _streamError == null) {
      return const _SignalsSkeleton(key: ValueKey('signals-skeleton'));
    }
    if (_data == null && _streamError != null) {
      return _SignalsError(
        key: const ValueKey('signals-error'),
        error: _streamError.toString(),
        onRetry: _refresh,
      );
    }
    var items = _data ?? const <MockSignal>[];
    if (_filter == _SignalFilter.closed &&
        _subFilter != _ClosedSubFilter.all) {
      items = items
          .where((s) => _matchesSubFilter(s, _subFilter))
          .toList(growable: false);
    }
    if (items.isEmpty) {
      return _SignalsEmpty(
        key: const ValueKey('signals-empty'),
        filter: _filter,
        subFilter: _subFilter,
        isLive: isLive,
      );
    }
    return ListView.separated(
      key: const ValueKey('signals-data'),
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: LuminSpacing.md),
      itemBuilder: (_, i) => _SignalCard(
        sig: items[i],
        livePrice: _livePrices[items[i].symbol],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.current, required this.onChanged});

  final _SignalFilter current;
  final ValueChanged<_SignalFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Row(
        children: [
          for (final f in _SignalFilter.values) ...[
            _Chip(
              label: f.label,
              selected: current == f,
              onTap: () => onChanged(f),
            ),
            if (f != _SignalFilter.values.last)
              const SizedBox(width: LuminSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _SubFilterRow extends StatelessWidget {
  const _SubFilterRow({required this.current, required this.onChanged});

  final _ClosedSubFilter current;
  final ValueChanged<_ClosedSubFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
        itemCount: _ClosedSubFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: LuminSpacing.sm),
        itemBuilder: (_, i) {
          final f = _ClosedSubFilter.values[i];
          return _Chip(
            label: f.label,
            selected: current == f,
            onTap: () => onChanged(f),
            compact: true,
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LuminRadii.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.pill),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? LuminSpacing.sm : LuminSpacing.md,
            vertical: compact ? LuminSpacing.xs : LuminSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: selected
                ? LuminColors.accent.withOpacity(0.15)
                : LuminColors.bgCard,
            borderRadius: BorderRadius.circular(LuminRadii.pill),
            border: Border.all(
              color: selected
                  ? LuminColors.accent.withOpacity(0.40)
                  : LuminColors.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? LuminColors.accent : LuminColors.textSecondary,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalsEmpty extends StatelessWidget {
  const _SignalsEmpty({
    super.key,
    required this.filter,
    required this.subFilter,
    required this.isLive,
  });
  final _SignalFilter filter;
  final _ClosedSubFilter subFilter;
  final bool isLive;

  String _heading() {
    if (filter == _SignalFilter.open) return 'No open signals right now';
    if (filter == _SignalFilter.closed) {
      switch (subFilter) {
        case _ClosedSubFilter.all:
          return 'No closed signals yet';
        case _ClosedSubFilter.tp:
          return 'No TP hits yet';
        case _ClosedSubFilter.sl:
          return 'No SL hits yet';
        case _ClosedSubFilter.invalidated:
          return 'No invalidated signals';
        case _ClosedSubFilter.expired:
          return 'No expired signals';
      }
    }
    return 'No signals yet';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        const SizedBox(height: LuminSpacing.xxl),
        const Icon(Icons.inbox_outlined,
            size: 48, color: LuminColors.textMuted),
        const SizedBox(height: LuminSpacing.md),
        Text(
          _heading(),
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: LuminSpacing.xs),
        Text(
          isLive
              ? 'Engine is scanning 75 pairs.\nNew paid signals appear here when they fire.'
              : 'Pull down to refresh.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: LuminColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

/// Skeleton placeholder rendered while the SWR cache has no entry yet
/// (typically cold start).  Five gray-box cards shaped like real
/// signal cards — gives the user something to look at while the
/// network round-trip completes, instead of a spinner over a blank
/// background.  No shimmer animation in v1 — adds a flutter_shimmer
/// dep we don't have yet; the static placeholder is already a big
/// perceived-speed win over CircularProgressIndicator.
class _SignalsSkeleton extends StatelessWidget {
  const _SignalsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.md,
          vertical: LuminSpacing.sm,
        ),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: LuminSpacing.sm),
        itemBuilder: (_, __) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: LuminColors.cardBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SkeletonBox(width: 80, height: 16),
              SizedBox(width: LuminSpacing.sm),
              _SkeletonBox(width: 48, height: 16),
              Spacer(),
              _SkeletonBox(width: 60, height: 16),
            ],
          ),
          SizedBox(height: LuminSpacing.sm),
          _SkeletonBox(width: double.infinity, height: 12),
          SizedBox(height: LuminSpacing.xs),
          _SkeletonBox(width: 180, height: 12),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SignalsError extends StatelessWidget {
  const _SignalsError({
    super.key,
    required this.error,
    required this.onRetry,
  });
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
        const Icon(Icons.cloud_off, color: LuminColors.loss, size: 40),
        const SizedBox(height: LuminSpacing.md),
        const Text(
          'Could not load signals',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: LuminColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LuminSpacing.sm),
        Text(
          error,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LuminColors.textSecondary,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: LuminSpacing.md),
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

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.sig, this.livePrice});
  final MockSignal sig;
  /// Live mark price from the 5 s Binance poll.  When non-null and the
  /// signal is still ACTIVE, overrides ``sig.currentPrice`` for display
  /// and drives a fresh PnL % calculation.
  final double? livePrice;

  /// Effective current price — live when available, API snapshot otherwise.
  double get _currentPrice =>
      (sig.status == 'ACTIVE' && (livePrice ?? 0) > 0)
          ? livePrice!
          : sig.currentPrice;

  /// Effective PnL % — recomputed from live price for ACTIVE signals;
  /// uses the finalised snapshot value for closed signals.
  double get _pnlPct {
    if (sig.status == 'ACTIVE' && (livePrice ?? 0) > 0 && sig.entry > 0) {
      return sig.direction == 'LONG'
          ? (livePrice! - sig.entry) / sig.entry * 100
          : (sig.entry - livePrice!) / sig.entry * 100;
    }
    return sig.pnlPct;
  }

  Color _statusColor() {
    switch (sig.status) {
      case 'TP1_HIT':
      case 'TP2_HIT':
      case 'TP3_HIT':
      case 'FULL_TP_HIT':
        return LuminColors.success;
      case 'SL_HIT':
        return LuminColors.loss;
      case 'INVALIDATED':
      case 'EXPIRED':
      case 'CANCELLED':
        return LuminColors.textMuted;
      default:
        return LuminColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLong = sig.direction == 'LONG';
    final effectivePnl = _pnlPct;
    final pnlPositive = effectivePnl >= 0;
    return LuminCard(
      onTap: () => _showDetail(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sig.symbol,
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: LuminSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LuminSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: (isLong ? LuminColors.success : LuminColors.loss)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                ),
                child: Text(
                  sig.direction,
                  style: TextStyle(
                    color: isLong ? LuminColors.success : LuminColors.loss,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (sig.preTpHit) ...[
                const SizedBox(width: LuminSpacing.sm),
                // Pre-TP banked badge — signals to the subscriber that
                // partial profit was already taken and the residual is
                // riding under a breakeven stop.  Explains the
                // "SL: BE" rendering in the price row below.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LuminSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: LuminColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(LuminRadii.sm),
                  ),
                  child: const Text(
                    '✓ BANKED',
                    style: TextStyle(
                      color: LuminColors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LuminSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: LuminColors.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(LuminRadii.sm),
                ),
                child: Text(
                  '${sig.confidence.toStringAsFixed(1)} ${sig.tier}',
                  style: const TextStyle(
                    color: LuminColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.xs),
          Text(
            '${sig.agentName} • ${sig.setupName}',
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: LuminSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PriceCol(
                  label: 'Entry',
                  value: formatPrice(sig.entry),
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'SL',
                  // BE-ratchet detection: after pre-TP fires, the engine
                  // moves stop_loss to entry — sig.sl == sig.entry by
                  // design.  Without this UX hint the card showed the
                  // same numeric price for ENTRY and SL columns (owner-
                  // reported 2026-05-18 confusion: "looks like SL ==
                  // entry, instant trigger?").  Pre-TP banked → render
                  // "BE" with the success accent (it's protection, not
                  // a risk-loss row anymore).
                  value: _isBreakeven(sig)
                      ? 'BE'
                      : formatPrice(sig.sl),
                  color: _isBreakeven(sig)
                      ? LuminColors.success
                      : LuminColors.loss,
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'TP1',
                  value: formatPrice(sig.tp1),
                  color: LuminColors.success,
                ),
              ),
              Expanded(
                child: _PriceCol(
                  label: 'TP2',
                  value: formatPrice(sig.tp2),
                  color: LuminColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.md),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor(),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: LuminSpacing.xs),
              Text(
                sig.status,
                style: TextStyle(
                  color: _statusColor(),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: LuminSpacing.sm),
              Text(
                '• ${formatAge(sig.minutesAgo)} ago',
                style: const TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              if (_currentPrice > 0) ...[
                Text(
                  formatPrice(_currentPrice),
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: LuminSpacing.sm),
              ],
              Text(
                formatPct(effectivePnl),
                style: TextStyle(
                  color: pnlPositive ? LuminColors.success : LuminColors.loss,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LuminColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(LuminRadii.lg),
        ),
      ),
      builder: (_) => _SignalDetailSheet(
        sig: sig,
        initialLivePrice: _currentPrice > 0 ? _currentPrice : null,
      ),
    );
  }
}

/// "Take signal" CTA on the detail sheet.  Opens the review sheet
/// (sized to wallet equity + per-user settings) on tap; the user
/// confirms there before any Binance call fires.
class _TakeSignalAction extends StatelessWidget {
  const _TakeSignalAction({required this.sig});
  final MockSignal sig;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: LuminColors.accent,
          foregroundColor: LuminColors.bgDeep,
          padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
        ),
        onPressed: () async {
          // Close the detail sheet first so the take sheet stacks
          // cleanly without an awkward double-modal.
          Navigator.of(context).pop();
          await showTakeSignalSheet(context, signal: sig);
        },
        icon: const Icon(Icons.bolt, size: 18),
        label: const Text(
          'Take signal',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Bottom-sheet detail view for a single signal.  Polls Binance's
/// public mark-price endpoint every 5 s while open (ACTIVE signals
/// only) so the "Current" row reflects live market price rather than
/// the SWR-cached snapshot.
class _SignalDetailSheet extends StatefulWidget {
  const _SignalDetailSheet({required this.sig, this.initialLivePrice});
  final MockSignal sig;
  final double? initialLivePrice;

  @override
  State<_SignalDetailSheet> createState() => _SignalDetailSheetState();
}

class _SignalDetailSheetState extends State<_SignalDetailSheet> {
  late double _livePrice;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _livePrice = widget.initialLivePrice ??
        (widget.sig.currentPrice > 0 ? widget.sig.currentPrice : 0.0);
    if (widget.sig.status == 'ACTIVE') {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
      // Fetch immediately so we show a fresh price on sheet open without
      // waiting the full 5 s interval.
      _fetch();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final prices = await _fetchMarkPrices([widget.sig.symbol]);
      final price = prices[widget.sig.symbol];
      if (!mounted || price == null || price <= 0) return;
      setState(() => _livePrice = price);
    } catch (_) {}
  }

  double get _pnlPct {
    if (widget.sig.status == 'ACTIVE' && _livePrice > 0 && widget.sig.entry > 0) {
      return widget.sig.direction == 'LONG'
          ? (_livePrice - widget.sig.entry) / widget.sig.entry * 100
          : (widget.sig.entry - _livePrice) / widget.sig.entry * 100;
    }
    return widget.sig.pnlPct;
  }

  @override
  Widget build(BuildContext context) {
    final sig = widget.sig;
    return Padding(
      padding: const EdgeInsets.all(LuminSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: LuminColors.textMuted,
                borderRadius: BorderRadius.circular(LuminRadii.pill),
              ),
            ),
          ),
          const SizedBox(height: LuminSpacing.lg),
          Text(
            '${sig.symbol} ${sig.direction}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: LuminSpacing.xs),
          Text(
            'Signal ${sig.id} • ${sig.agentName}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: LuminSpacing.lg),
          if (sig.preTpTriggerPrice > 0) ...[
            _PreTpCard(sig: sig),
            const SizedBox(height: LuminSpacing.md),
          ],
          _DetailRow('Entry', formatPrice(sig.entry)),
          if (_livePrice > 0)
            _DetailRow(
              'Current',
              formatPrice(_livePrice),
              valueColor: sig.status == 'ACTIVE' ? LuminColors.accent : null,
            ),
          _DetailRow(
            'SL',
            _isBreakeven(sig) ? 'BE (banked)' : formatPrice(sig.sl),
          ),
          _DetailRow('TP1', formatPrice(sig.tp1)),
          _DetailRow('TP2', formatPrice(sig.tp2)),
          _DetailRow(
            'PnL',
            formatPct(_pnlPct),
            valueColor: _pnlPct >= 0 ? LuminColors.success : LuminColors.loss,
          ),
          _DetailRow('Confidence',
              '${sig.confidence.toStringAsFixed(1)} (${sig.tier})'),
          _DetailRow('Status', sig.status),
          if (sig.status == 'ACTIVE') ...[
            const SizedBox(height: LuminSpacing.lg),
            _TakeSignalAction(sig: sig),
          ],
        ],
      ),
    );
  }
}

/// Pre-TP centerpiece card — banked-state highlight or stamped-target.
class _PreTpCard extends StatelessWidget {
  const _PreTpCard({required this.sig});
  final MockSignal sig;

  @override
  Widget build(BuildContext context) {
    final banked = sig.preTpHit;
    final accent = banked ? LuminColors.success : LuminColors.accent;
    final title = banked ? '⚡ Pre-TP Banked' : '⚡ Pre-TP Target';
    final priceLine = formatPrice(sig.preTpTriggerPrice);
    final pctLine =
        '+${sig.preTpThresholdPct.toStringAsFixed(2)}% raw → SL ratchets to breakeven';
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(LuminRadii.md),
        border: Border.all(color: accent.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            priceLine,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pctLine,
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCol extends StatelessWidget {
  const _PriceCol({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: LuminColors.textMuted,
            fontSize: 9,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color ?? LuminColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, {this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LuminSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? LuminColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

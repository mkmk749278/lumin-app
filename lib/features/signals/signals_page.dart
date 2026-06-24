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

import '../../app/foreground_refresh.dart';
import '../../data/app_config.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/free_tier_gate.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import '../../shared/widgets/shimmer.dart';
import 'take_signal_sheet.dart';

/// Fetch mark prices for a batch of symbols from Binance's public
/// premiumIndex endpoint.  Fires requests concurrently; any individual
/// failure is silently dropped so a single bad symbol can't block the
/// rest.  Returns a map of symbol → mark price for every symbol that
/// responded successfully.
///
/// [client] is a long-lived connection pool owned by the caller
/// (_SignalsPageState) so TCP connections are reused across 5 s polls
/// instead of being torn down and re-established every tick.
Future<Map<String, double>> _fetchMarkPrices(
  List<String> symbols,
  http.Client client,
) async {
  if (symbols.isEmpty) return const {};
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

class _SignalsPageState extends State<SignalsPage>
    implements ForegroundRefreshable {
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
  /// Per-filter data cache — retains the last-loaded list for each
  /// filter so switching Active ↔ Closed ↔ All is instant: the cached
  /// list is shown immediately while the background SWR refresh runs.
  /// The skeleton only appears on the very first load of a given filter
  /// within this page session.  Cleared on repo change (Live↔Mock).
  final Map<_SignalFilter, List<MockSignal>?> _dataByFilter = {};
  final Map<_SignalFilter, Object?> _errorByFilter = {};
  LuminRepository? _lastRepo;

  /// Completed by the stream listener on the post-invalidate emit so
  /// [_refresh] can hold the RefreshIndicator spinner until fresh
  /// data lands.  Same pattern as PulsePage / TradePage.
  Completer<void>? _refreshDone;

  /// Per-symbol live price notifiers — polled every 5 s for ACTIVE signals.
  /// Each card subscribes to its own notifier so only price-bearing rows
  /// rebuild on each tick, not the entire ListView.
  /// Only populated when ``isLive == true`` and at least one ACTIVE
  /// signal is visible.  Disposed in [dispose] + on filter change.
  final Map<String, ValueNotifier<double>> _priceNotifiers = {};
  Timer? _priceTimer;

  /// Persistent HTTP connection pool for Binance mark-price polls.
  /// Reused across every 5 s tick so TCP connections are kept alive
  /// instead of torn down and re-established on every poll.
  /// Closed in [dispose] when the page leaves the tree.
  final http.Client _markPriceClient = http.Client();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppConfigScope.of(context).repo;
    if (repo != _lastRepo) {
      _lastRepo = repo;
      // Repo switched (Live↔Mock toggle or sign-out) — stale data for
      // the old identity must not bleed into the new session.
      _dataByFilter.clear();
      _errorByFilter.clear();
      _resubscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _priceTimer?.cancel();
    _markPriceClient.close();
    for (final n in _priceNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Returns the unique set of symbols for ACTIVE signals in the current
  /// list.  Used to decide which symbols need live price polling.
  List<String> _activeSymbols() {
    final data = _dataByFilter[_filter];
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
    final fresh = await _fetchMarkPrices(syms, _markPriceClient);
    if (!mounted) return;
    for (final entry in fresh.entries) {
      _priceNotifiers
          .putIfAbsent(entry.key, () => ValueNotifier<double>(0.0))
          .value = entry.value;
    }
  }

  void _resubscribe() {
    _sub?.cancel();
    final repo = AppConfigScope.of(context).repo;
    // Capture the current filter so the listener closure always writes
    // to the right bucket even if the user switches filters before the
    // async fetch completes.
    final filter = _filter;
    final stream = repo.watchSignals(status: filter.apiValue, limit: 100);
    setState(() => _errorByFilter.remove(filter));
    _sub = stream.listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _dataByFilter[filter] = items;
          _errorByFilter.remove(filter);
        });
        _restartPricePolling();
        final done = _refreshDone;
        if (done != null && !done.isCompleted) done.complete();
      },
      onError: (Object e, StackTrace _) {
        if (!mounted) return;
        setState(() => _errorByFilter[filter] = e);
        final done = _refreshDone;
        if (done != null && !done.isCompleted) done.complete();
      },
    );
  }

  @override
  void refreshFromForeground() {
    // App resumed on the Signals tab. Mirror pull-to-refresh's data path
    // for the active filter (invalidate that filter's SWR key, resubscribe)
    // without the spinner. Retained `_dataByFilter[_filter]` keeps the list
    // on screen until fresh data lands.
    if (!mounted) return;
    final repo = AppConfigScope.of(context).repo;
    repo.invalidateSignalsCache(status: _filter.apiValue, limit: 100);
    _resubscribe();
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
      // Keep _dataByFilter[f]: if data was previously loaded for this
      // filter it is shown immediately while the background SWR refresh
      // runs, eliminating the skeleton flash on every tab switch.
      // DO dispose price notifiers — they're keyed to the previous
      // filter's ACTIVE symbols and must not accumulate across switches.
      for (final n in _priceNotifiers.values) {
        n.dispose();
      }
      _priceNotifiers.clear();
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
      appBar: AppBar(
        title: const Text('Signals'),
        // Engine-wide feed disclaimer — prevents subscribers from
        // confusing "ACTIVE" engine signals with their personal open
        // positions.  The Trade tab is the per-user execution view.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Engine-wide feed  •  Your open positions → Trade tab',
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
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
    final data = _dataByFilter[_filter];
    final error = _errorByFilter[_filter];
    if (data == null && error == null) {
      return const _SignalsSkeleton(key: ValueKey('signals-skeleton'));
    }
    if (data == null && error != null) {
      return _SignalsError(
        key: const ValueKey('signals-error'),
        error: error.toString(),
        onRetry: _refresh,
      );
    }
    var items = data ?? const <MockSignal>[];
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
        priceNotifier: _priceNotifiers[items[i].symbol],
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
              ? 'New signals appear here when they fire.\nCheck the Trade tab to see your open positions.'
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
  const _SignalCard({required this.sig, this.priceNotifier});
  final MockSignal sig;
  /// Per-symbol live-price notifier from the 5 s Binance poll.  When
  /// non-null and the signal is ACTIVE, the bottom price+PnL row
  /// rebuilds independently on each tick without rebuilding the rest of
  /// the card or any sibling cards in the ListView.
  final ValueNotifier<double>? priceNotifier;

  /// Shared fallback for closed signals that have no live price — never
  /// modified, never disposed, never triggers a rebuild.
  static final ValueNotifier<double> _kZeroPrice = ValueNotifier(0.0);

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

  /// Price helpers used inside [ValueListenableBuilder] — kept as
  /// static helpers so they don't capture any stale widget state.
  static double _effectivePrice(MockSignal sig, double live) =>
      (sig.status == 'ACTIVE' && live > 0) ? live : sig.currentPrice;

  static double _effectivePnl(MockSignal sig, double live) {
    if (sig.status == 'ACTIVE' && live > 0 && sig.entry > 0) {
      return sig.direction == 'LONG'
          ? (live - sig.entry) / sig.entry * 100
          : (sig.entry - live) / sig.entry * 100;
    }
    return sig.pnlPct;
  }

  static const _terminalStatuses = {
    'SL_HIT', 'BREAKEVEN_EXIT', 'PROFIT_LOCKED',
    'INVALIDATED', 'EXPIRED', 'CANCELLED',
    'FULL_TP_HIT', 'TP3_HIT', 'TP2_HIT', 'TP1_HIT', 'CLOSED',
  };

  @override
  Widget build(BuildContext context) {
    final isLong = sig.direction == 'LONG';
    final card = LuminCard(
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
          // Only the price+PnL suffix rebuilds when the notifier ticks.
          // Status dot, status text, and hold-time label are static for
          // the signal's lifetime and stay outside the builder.
          ValueListenableBuilder<double>(
            valueListenable: priceNotifier ?? _kZeroPrice,
            builder: (_, live, __) {
              final currentPrice = _effectivePrice(sig, live);
              final effectivePnl = _effectivePnl(sig, live);
              final pnlPositive = effectivePnl >= 0;
              return Row(
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
                  Builder(builder: (_) {
                    final isTerminal = const {
                      'SL_HIT', 'BREAKEVEN_EXIT', 'PROFIT_LOCKED',
                      'INVALIDATED', 'EXPIRED', 'CANCELLED',
                      'FULL_TP_HIT', 'TP3_HIT', 'CLOSED',
                    }.contains(sig.status);
                    final holdMins = sig.holdMins;
                    final String timeLabel;
                    if (isTerminal && holdMins != null) {
                      timeLabel = '• held ${formatAge(holdMins)} · ${formatAge(sig.minutesAgo)} ago';
                    } else if (!isTerminal && holdMins != null) {
                      timeLabel = '• open ${formatAge(holdMins)}';
                    } else {
                      timeLabel = '• ${formatAge(sig.minutesAgo)} ago';
                    }
                    return Text(
                      timeLabel,
                      style: const TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 11,
                      ),
                    );
                  }),
                  const Spacer(),
                  if (currentPrice > 0) ...[
                    Text(
                      formatPrice(currentPrice),
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
              );
            },
          ),
        ],
      ),
    );
    // Closed signals stay visible in the feed but faded out (owner brief
    // 2026-06-24) — the story stays, the eye goes to live signals.
    return _terminalStatuses.contains(sig.status)
        ? Opacity(opacity: 0.55, child: card)
        : card;
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
      builder: (_) {
        final live = priceNotifier?.value ?? 0.0;
        final initialPrice = _effectivePrice(sig, live);
        return _SignalDetailSheet(
          sig: sig,
          initialLivePrice: initialPrice > 0 ? initialPrice : null,
        );
      },
    );
  }
}

/// "Take signal" CTA on the detail sheet.  Opens the review sheet
/// (sized to wallet equity + per-user settings) on tap; the user
/// confirms there before any Binance call fires.
class _TakeSignalAction extends StatelessWidget {
  const _TakeSignalAction({required this.sig, this.enabled = true});
  final MockSignal sig;

  /// When false the bar is still shown (owner brief: visible after close) but
  /// faded and non-interactive — a closed signal can't be taken.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Opacity(
        opacity: 0.45,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.textMuted,
              foregroundColor: LuminColors.bgDeep,
              padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
            ),
            onPressed: null, // disabled — signal closed
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text(
              'Signal closed',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: LuminColors.accent,
          foregroundColor: LuminColors.bgDeep,
          padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
        ),
        onPressed: () async {
          // One-tap "take trade" is the Assist tier (B16). Free users see
          // the full signal + levels and can trade it manually on their own
          // exchange; the in-app one-tap placement is the paid feature.
          final tier = AppConfigScope.of(context).tier;
          // Close the detail sheet first so the next sheet stacks cleanly.
          Navigator.of(context).pop();
          if (!canAssist(tier)) {
            showUpgradeSheet(context);
            return;
          }
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
  final http.Client _markPriceClient = http.Client();

  // Per-symbol auto-trade management mode ('full' | 'entry').
  String _mgmtMode = 'full';
  bool _mgmtLoaded = false;
  bool _mgmtSaving = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_mgmtLoaded) _loadMgmt();
  }

  Future<void> _loadMgmt() async {
    final repo = AppConfigScope.of(context).repo;
    try {
      final map = await repo.fetchSymbolManagement();
      if (!mounted) return;
      setState(() {
        _mgmtMode = map[widget.sig.symbol.toUpperCase()] ?? 'full';
        _mgmtLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _mgmtLoaded = true); // fall back to 'full'
    }
  }

  Future<void> _setMgmt(String mode) async {
    if (_mgmtSaving || mode == _mgmtMode) return;
    setState(() => _mgmtSaving = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final map = await repo.setSymbolManagement(widget.sig.symbol, mode);
      if (!mounted) return;
      setState(() {
        _mgmtMode = map[widget.sig.symbol.toUpperCase()] ?? 'full';
        _mgmtSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == 'entry'
                ? '${widget.sig.symbol}: entry-only — engine places entry + SL, you manage the rest'
                : '${widget.sig.symbol}: full — engine manages the whole trade',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _mgmtSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: LuminColors.loss,
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _markPriceClient.close();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final prices = await _fetchMarkPrices([widget.sig.symbol], _markPriceClient);
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
      child: SingleChildScrollView(
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
          // Outcome summary — the centerpiece (owner brief 2026-06-24):
          // highlight the positive result and the MAX PROFIT the trade
          // reached before SL.  Default exit is TP1-full + fixed SL, so this
          // replaces the old pre-TP/BE card as the headline.
          _OutcomeSummaryCard(sig: sig, pnlPct: _pnlPct),
          const SizedBox(height: LuminSpacing.md),
          // Pre-TP card only when banking actually fired (opt-in users) — the
          // engine default no longer banks, so don't imply it did.
          if (sig.preTpHit) ...[
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
          if (sig.holdMins != null) ...[
            Builder(builder: (_) {
              final isTerminal = const {
                'SL_HIT', 'BREAKEVEN_EXIT', 'PROFIT_LOCKED',
                'INVALIDATED', 'EXPIRED', 'CANCELLED',
                'FULL_TP_HIT', 'TP3_HIT', 'CLOSED',
              }.contains(sig.status);
              return _DetailRow(
                'Hold',
                isTerminal
                    ? '${formatAge(sig.holdMins!)} (closed ${formatAge(sig.minutesAgo)} ago)'
                    : 'open ${formatAge(sig.holdMins!)}',
              );
            }),
          ],
          const SizedBox(height: LuminSpacing.lg),
          _managementSection(),
          const SizedBox(height: LuminSpacing.lg),
          // Take-signal bar stays visible after close (owner brief) but faded
          // + disabled — a closed signal can't be taken.
          _TakeSignalAction(sig: sig, enabled: sig.status == 'ACTIVE'),
        ],
        ),
      ),
    );
  }

  /// Per-symbol auto-trade management chooser — the two modes the owner
  /// asked to surface on tapping a symbol:
  ///   • Full      — engine takes the trade and auto-closes 100% at TP1 or SL
  ///     (the Session-34 default exit: no pre-TP, no invalidation).
  ///   • Entry-only — engine places the entry + protective SL only; you
  ///     manage the exit.
  /// Applies to every auto-trade on ``sig.symbol`` (not just this signal)
  /// and takes effect on the next dispatch for that symbol.
  Widget _managementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'AUTO-TRADE ${widget.sig.symbol}',
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: LuminSpacing.sm),
            if (_mgmtSaving || !_mgmtLoaded)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: LuminSpacing.sm),
        _ManagementOption(
          title: 'Take full (auto execute)',
          subtitle: 'Engine takes the trade and auto-closes 100% at TP1 or SL.',
          selected: _mgmtMode == 'full',
          onTap: () => _setMgmt('full'),
        ),
        const SizedBox(height: LuminSpacing.sm),
        _ManagementOption(
          title: 'Entry only',
          subtitle: 'Engine places the entry + a protective SL, then you '
              'manage the exit. No pre-TP, no TP ladder, no auto-invalidation.',
          selected: _mgmtMode == 'entry',
          onTap: () => _setMgmt('entry'),
        ),
      ],
    );
  }
}

/// One selectable management-mode tile (Full / Entry-only).  Highlights
/// when selected — the "highlight two things" the owner asked for.
class _ManagementOption extends StatelessWidget {
  const _ManagementOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = LuminColors.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LuminRadii.md),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : LuminColors.bgDeep,
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(
            color: selected ? accent.withOpacity(0.6) : LuminColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? accent : LuminColors.textMuted,
              size: 18,
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? accent : LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
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

/// Outcome summary — the headline card on the detail sheet (owner brief
/// 2026-06-24).  Highlights the positive result and the MAX PROFIT the trade
/// reached before SL.  Default exit is TP1-full + fixed SL, so this is the
/// centerpiece (replacing the old pre-TP/BE card).  Engine-recorded values
/// only — no fabricated numbers (B3 / Hard Limit).
class _OutcomeSummaryCard extends StatelessWidget {
  const _OutcomeSummaryCard({required this.sig, required this.pnlPct});
  final MockSignal sig;
  final double pnlPct;

  static const _terminal = {
    'SL_HIT', 'BREAKEVEN_EXIT', 'PROFIT_LOCKED',
    'INVALIDATED', 'EXPIRED', 'CANCELLED',
    'FULL_TP_HIT', 'TP3_HIT', 'TP2_HIT', 'TP1_HIT', 'CLOSED',
  };

  @override
  Widget build(BuildContext context) {
    final closed = _terminal.contains(sig.status);
    final pnlPositive = pnlPct >= 0;
    final mfe = sig.maxFavorableExcursionPct;
    final hasMfe = mfe > 0;
    // Lean positive (owner: "highlight positive results"): green whenever the
    // trade closed in profit OR ever reached a positive peak.
    final accent =
        (pnlPositive || hasMfe) ? LuminColors.success : LuminColors.loss;
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(LuminRadii.md),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            closed ? 'OUTCOME' : 'LIVE',
            style: TextStyle(
              color: accent,
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _stat(
                  label: closed ? 'Result' : 'Live PnL',
                  value: formatPct(pnlPct),
                  color: pnlPositive ? LuminColors.success : LuminColors.loss,
                ),
              ),
              Expanded(
                child: _stat(
                  label: closed ? 'Max profit before SL' : 'Peak so far',
                  value: hasMfe ? '+${mfe.toStringAsFixed(2)}%' : '—',
                  color:
                      hasMfe ? LuminColors.success : LuminColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: LuminColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
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

/// Trade — top-level Live and Paper tabs, each with its own on/off toggle.
///
/// Owner 2026-05-17 redesign — replaced the tri-state Off/Paper/Live card
/// inside the Live body (which caused "two paper modes" confusion when
/// mode=paper made the Live tab render paper positions) with two
/// independent per-tab binary toggles:
///
///   * **Live tab**: shows ONLY live execution.  Binary toggle flips
///     mode ``'live' <-> 'off'``.  Binance positions render when the
///     user has keys connected and the toggle is on; an off-state
///     notice otherwise.
///   * **Paper tab**: shows ONLY paper trading.  Binary toggle flips
///     mode ``'paper' <-> 'off'``.  Renders paper P&L + open positions
///     + trade history (with ``include_open=true`` so live activity
///     surfaces alongside closed history).
///
/// The two tabs are mutually exclusive at the engine — the ``mode`` field
/// is a single tri-state string, so turning ON one auto-forces the other
/// OFF on the next refresh.  Each tab's toggle is a view onto the shared
/// state from that tab's perspective.
///
/// Phase 3c carries forward: when the user has Binance keys connected,
/// the Live tab queries their real Binance positions via
/// ``GET /fapi/v2/positionRisk``.
///
/// Mode flip writes to the **per-user** ``user_auto_trade_settings``
/// table (Phase 2 endpoint) and kicks the AutoTradeWatcher (Phase 3b-2)
/// to pick up the new mode without waiting for its next tick.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../data/server_side_execution_models.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import '../settings/pages/symbol_preference_page.dart';
import 'paper_trades_page.dart';

class _TradeBundle {
  const _TradeBundle({
    required this.autoMode,
    required this.userSettings,
    required this.positions,
    required this.activity,
  });
  /// Engine-wide auto-mode (read by all tiers).  Drives the P&L card
  /// + open positions for the Paper sub-tab.
  final AutoModeStatus autoMode;

  /// Per-user override.  Drives the Paper sub-tab's on/off toggle.
  /// Server-side auto-trade execution is independent (governed by
  /// the engine's ``auto_trade_globally_enabled`` Firestore flag,
  /// see Settings → Server-side auto-trade).
  final AutoTradeSettings userSettings;

  /// Engine paper positions — rendered by the Paper sub-tab.  The
  /// engine maintains a single paper book for the whole project;
  /// per-user PnL is a future hardening item.
  final List<MockPosition> positions;
  final List<MockActivityEvent> activity;
}

/// Which top-tab the Trade page is currently showing.  Each owns its
/// own on/off toggle for the corresponding mode; see ``_buildLiveBody``
/// and ``_buildPaperBody`` for the per-tab content.
enum _TradeView { live, paper }

class TradePage extends StatefulWidget {
  const TradePage({super.key});

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  _TradeView _view = _TradeView.live;
  // Phase 2c — engine slice as a SWR stream + Binance slice as a
  // parallel future; combined into a single Stream<_TradeBundle> via
  // a StreamController so the page-side build path stays
  // StreamBuilder-driven (matching Phase 2a/2b's Signals + Pulse
  // migration).
  late Stream<_TradeBundle> _stream;
  StreamSubscription<TradeEngineSnapshot>? _engineSub;
  StreamController<_TradeBundle>? _bundleController;
  LuminRepository? _lastRepo;
  bool _switchingMode = false;
  // Set by ``_refresh`` so it can await the next fresh engine emit.
  // Completed by the engine listener in ``_resubscribe`` on the first
  // post-invalidate fetch landing.  Without this, the RefreshIndicator
  // released its spinner instantly (``_refresh`` returned before the
  // network round-trip) and users couldn't tell whether the pull
  // actually triggered a refresh.
  Completer<void>? _refreshDone;

  // Auto-trade disabled banner state (PR-14 follow-up 3/3).
  // Now consumed via the SWR cache (``watchAutoTradeUserStatus``) so
  // the prewarm at sign-in lands the value before the user navigates
  // to Trade — first tap renders synchronously from cache instead of
  // waiting on a fresh network round-trip.  ``null`` while loading.
  AutoTradeUserStatus? _autoTradeStatus;
  StreamSubscription<AutoTradeUserStatus>? _userStatusSub;

  // Runtime composite status + server-side open positions (PR-C
  // 2026-05-19).  Same SWR-stream pattern as ``_autoTradeStatus`` —
  // prewarmed at sign-in for instant first paint.
  AutoTradeRuntimeStatus? _runtimeStatus;
  StreamSubscription<AutoTradeRuntimeStatus>? _runtimeStatusSub;
  List<ServerSidePosition>? _serverPositions;
  StreamSubscription<List<ServerSidePosition>>? _positionsSub;
  // Recent dispatch events (placed + rejected) — same SWR-stream
  // pattern.  Engine endpoint ``/api/auto-trade/recent-events`` is
  // user-scoped via Firebase ID token.
  List<DispatchEvent>? _recentDispatchEvents;
  StreamSubscription<List<DispatchEvent>>? _dispatchEventsSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppConfigScope.of(context).repo;
    if (repo != _lastRepo) {
      _lastRepo = repo;
      _resubscribe();
      _resubscribeAuxStreams();
    }
  }

  /// Re-subscribe to the four per-user SWR streams the page consumes
  /// alongside the engine snapshot.  Called on initial dependency
  /// resolution + on pull-to-refresh (after the relevant SWR keys
  /// are invalidated so the resubscribe yields fresh values).
  void _resubscribeAuxStreams() {
    final repo = AppConfigScope.of(context).repo;

    _userStatusSub?.cancel();
    _userStatusSub = repo.watchAutoTradeUserStatus().listen(
      (status) {
        if (!mounted) return;
        setState(() => _autoTradeStatus = status);
      },
      onError: (Object _, StackTrace __) {
        // Status fetch failure is non-fatal — the banner just doesn't
        // render.  Engine returns a safe default + 200 even under
        // Firestore outages, so the only way to hit this is a
        // network/5xx failure.
        if (!mounted) return;
        setState(() => _autoTradeStatus = null);
      },
    );

    _runtimeStatusSub?.cancel();
    _runtimeStatusSub = repo.watchAutoTradeRuntimeStatus().listen(
      (status) {
        if (!mounted) return;
        setState(() => _runtimeStatus = status);
      },
      onError: (Object _, StackTrace __) {
        // Keep whatever we last had — a transient 5xx shouldn't
        // blank the gate card.
      },
    );

    _positionsSub?.cancel();
    _positionsSub = repo.watchAutoTradePositions().listen(
      (positions) {
        if (!mounted) return;
        setState(() => _serverPositions = positions);
      },
      onError: (Object _, StackTrace __) {
        // Same posture as runtime status.
      },
    );

    _dispatchEventsSub?.cancel();
    _dispatchEventsSub = repo.watchRecentDispatchEvents(limit: 20).listen(
      (events) {
        if (!mounted) return;
        setState(() => _recentDispatchEvents = events);
      },
      onError: (Object _, StackTrace __) {
        // Same posture — transient failure keeps the prior list.
      },
    );
  }

  @override
  void dispose() {
    _engineSub?.cancel();
    _userStatusSub?.cancel();
    _runtimeStatusSub?.cancel();
    _positionsSub?.cancel();
    _dispatchEventsSub?.cancel();
    _bundleController?.close();
    super.dispose();
  }

  void _resubscribe() {
    _engineSub?.cancel();
    _bundleController?.close();
    final repo = AppConfigScope.of(context).repo;
    final uid = AppConfigScope.of(context).userId;
    final controller = StreamController<_TradeBundle>();
    _bundleController = controller;

    TradeEngineSnapshot? engine;

    void emit() {
      if (engine == null) return;
      if (controller.isClosed) return;
      controller.add(_TradeBundle(
        autoMode: engine!.autoMode,
        positions: engine!.positions,
        activity: engine!.activity,
        userSettings: engine!.userSettings,
      ));
    }

    // Engine: SWR — emits cached (instant) + fresh (on RTT).
    _engineSub = repo.watchTradeEngineSnapshot().listen(
      (snap) {
        engine = snap;
        emit();
        // Release the pull-to-refresh spinner on the first emit after
        // ``_refresh`` invalidated the cache.  Post-invalidate the SWR
        // entry has been dropped, so this emit is the fresh-fetch result,
        // not a stale read — the spinner releasing now is honest UX.
        final done = _refreshDone;
        if (done != null && !done.isCompleted) done.complete();
      },
      onError: (Object e, StackTrace st) {
        if (!controller.isClosed) controller.addError(e, st);
        final done = _refreshDone;
        if (done != null && !done.isCompleted) done.complete();
      },
    );

    // 2026-05-19: the OLD Binance fetch (``_fetchBinanceSlice``) is
    // no longer called.  It used to populate the now-removed
    // ``_UserPositionsCard`` in the Live body — gone with the
    // client-side-execution UI cleanup.  The fetch method itself
    // remains on-disk (referenced by nothing) so a follow-up PR
    // can delete it cleanly without churning this file twice.

    setState(() {
      _stream = controller.stream;
    });
  }

  // ``_fetchBinanceSlice`` was removed in the client-side-execution UI
  // cleanup (2026-05-19) — the Live body no longer renders the user's
  // real Binance positions, so the OLD ``BinanceKeysService``-driven
  // fetch is no longer needed.  Server-side execution surfaces
  // positions via Firestore listeners in a follow-up PR.

  Future<void> _refresh() async {
    // Pull-to-refresh: invalidate every SWR key this page consumes,
    // then resubscribe so the streams yield fresh values.  We hold
    // the RefreshIndicator spinner until the engine emit arrives
    // (the slowest of the bunch — auxes are typically smaller
    // single-shot Firestore reads) so the gesture has visible
    // feedback.  Owner reported 2026-05-20: "still old binance
    // activity showing not updating" — fixed once aux fetches
    // started going through the SWR invalidate path too.
    final repo = AppConfigScope.of(context).repo;
    final completer = Completer<void>();
    _refreshDone = completer;
    repo.invalidateTradeEngineSnapshotCache();
    repo.invalidateAutoTradeUserStatusCache();
    repo.invalidateAutoTradeRuntimeStatusCache();
    repo.invalidateAutoTradePositionsCache();
    repo.invalidateRecentDispatchEventsCache(limit: 20);
    _resubscribe();
    _resubscribeAuxStreams();
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Stream didn't emit within 5 s — release the spinner anyway.
      // The page either kept its previous data or shows the error
      // path via the StreamBuilder; this method has done its job.
    } finally {
      if (identical(_refreshDone, completer)) _refreshDone = null;
    }
  }

  /// Real-money confirmation modal before flipping per-user mode →
  /// LIVE.  Same gate as the Auto-trade settings page (Phase 3b-2),
  /// inlined here so both entry points to live-mode get the same
  /// explicit opt-in.
  Future<bool?> _confirmLiveFlip() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LuminColors.bgCard,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: LuminColors.loss, size: 20),
            SizedBox(width: LuminSpacing.sm),
            Expanded(
              child: Text(
                'Enable LIVE auto-trade?',
                style: TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lumin will place real Binance Futures orders without '
              'per-signal confirmation while the app is open.',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            SizedBox(height: LuminSpacing.sm),
            Text(
              '• Sized by your position-size % × leverage cap\n'
              '• Idempotent per signal (each fires at most once)\n'
              '• Auto-trade pauses when the app backgrounds\n'
              '• Tap the AUTO banner to stop immediately',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: LuminColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.loss,
              foregroundColor: LuminColors.bgDeep,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Enable LIVE',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeMode(String newMode) async {
    if (_switchingMode) return;
    final repo = AppConfigScope.of(context).repo;
    // Real-money confirmation before LIVE — same gate as the
    // Auto-trade settings page (3b-2).  Off / Paper bypass.
    if (newMode == 'live') {
      final ok = await _confirmLiveFlip();
      if (ok != true) return;
    }
    setState(() => _switchingMode = true);
    try {
      // Per-user mode flip (Phase 2 endpoint).  Every signed-in tier
      // can write its own profile — no 403 path here.  The engine-
      // wide mode lives on Settings → Engine defaults (owner-only).
      await repo.updateUserAutoTradeSettings(
        AutoTradeSettings(mode: newMode),
      );
      // 2026-05-19: AutoTradeWatcher removal — server-side execution
      // picks up the per-user mode change on the next signal via the
      // Position FSM gating (engine PRs #430-#451).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mode → ${newMode.toUpperCase()}'),
          duration: const Duration(seconds: 2),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refused: $e'),
          duration: const Duration(seconds: 4),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _switchingMode = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Owner 2026-05-17 redesign — the Trade page has two top-level tabs
    // (Live and Paper), each fully self-contained with its own binary
    // on/off toggle.  The previous tri-state mode card inside the Live
    // body confused users: when mode=paper the "Live" tab rendered paper
    // P&L + paper positions, making it look like two separate paper
    // modes were running.  The fix:
    //
    //   * Live tab: shows ONLY live-execution content (Binance positions
    //     when keys are connected).  Has a single Live toggle that flips
    //     mode 'live' <-> 'off'.
    //   * Paper tab: shows ONLY paper content (P&L + open positions +
    //     trade history).  Has a single Paper toggle that flips mode
    //     'paper' <-> 'off'.
    //
    // The two toggles are mutually exclusive at the engine layer (mode
    // is a single string).  Turning ON one automatically forces the
    // other to OFF on the next refresh — _activeMode resolution below.
    return Scaffold(
      appBar: AppBar(title: const Text('Trade')),
      body: Column(
        children: [
          _SubTabStrip(
            view: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          Expanded(
            child: RefreshIndicator(
              color: LuminColors.accent,
              onRefresh: _refresh,
              child: StreamBuilder<_TradeBundle>(
                stream: _stream,
                builder: (context, snap) {
                  // First emit happens when engine slice lands (cached
                  // or fresh).  Binance slice may still be in flight
                  // — bundle's binance* fields will be null and the
                  // page falls back to engine paper positions, same as
                  // PR #32's pre-Binance window.
                  if (!snap.hasData &&
                      snap.connectionState != ConnectionState.done) {
                    return const _TradeLoading();
                  }
                  if (snap.hasError && !snap.hasData) {
                    return _TradeError(
                        error: snap.error.toString(), onRetry: _refresh);
                  }
                  final data = snap.data!;
                  return _view == _TradeView.paper
                      ? _buildPaperBody(context, data)
                      : _buildLiveBody(context, data);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Live-tab body.  Owner 2026-05-17 — no longer renders paper data
  /// Live-tab body.  Post-server-side-execution cleanup (2026-05-19):
  /// the old "Live auto-trade" toggle, the OLD Binance-keys check, and
  /// the local user-positions card are all removed.  Server-side
  /// execution is now the only auto-trade path:
  ///
  ///   * Banner renders the engine-state (auto_trade_globally_enabled +
  ///     per-user disable) via [_AutoTradeDisabledBanner].
  ///   * Actionable CTA pointing at Settings → Server-side auto-trade
  ///     when the user hasn't connected yet (we detect this indirectly
  ///     via the activity card — if the engine has activity but the
  ///     user has no positions yet, show the CTA).
  ///   * Activity card streams the engine's signal events (global, not
  ///     per-user) — useful informational view of what the engine is
  ///     detecting.
  ///
  /// The Paper sub-tab is unchanged — it's the engine's paper trader
  /// preview surface, which stays useful regardless of which auto-trade
  /// path is in play.
  Widget _buildLiveBody(BuildContext context, _TradeBundle data) {
    final scope = AppConfigScope.of(context);
    final runtime = _runtimeStatus;
    final serverPositions = _serverPositions;
    final recentEvents = _recentDispatchEvents;
    // Non-traders get a stripped-down Live tab: just the gate checklist
    // pointing them at what they need to enable.  The dispatch-event
    // history + engine signal stream + open positions card are noise
    // when there's no Binance key connected — there's nothing to
    // surface in any of them, and stacking three empty cards under the
    // gates is the "Trade > Live tab became messy" symptom the owner
    // reported 2026-05-23.  Once the user connects a key, these come
    // back into view because the data they carry becomes meaningful.
    final hasBinanceKey =
        runtime != null && runtime.binanceKeyConnected;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        if (!scope.repo.isLive) const PreviewBadge(),
        // Server-side auto-trade state banner.  Hidden when the user
        // is fully enabled (operator has flipped the global flag AND
        // this user's per-user circuit breaker hasn't tripped).
        if (_autoTradeStatus != null && !_autoTradeStatus!.isFullyEnabled)
          _AutoTradeDisabledBanner(status: _autoTradeStatus!),
        // Insufficient-margin auto-pause banner (engine PR #479,
        // 2026-05-24).  Renders when the engine has stamped the user's
        // dispatcher as paused after N consecutive Binance -2019
        // rejections.  Carries an inline "Resume" button that fires
        // POST /api/auto-mode/resume-mine — the user-facing reset of
        // the pause flag.  Owner-reported 2026-05-23: every signal
        // was spamming the Recent Activity card with the same
        // insufficient-margin error.
        if (data.userSettings.isAutoPaused)
          _AutoPauseBanner(
            settings: data.userSettings,
            onResumed: _refresh,
          ),
        const SizedBox(height: LuminSpacing.md),
        // Auto-trade armed card (PR-C 2026-05-19) — per-gate green/red
        // checks + the symbol allowlist as a footnote.  Hidden until
        // the first runtime-status fetch lands so the card doesn't
        // flicker red→green during the initial RTT.
        if (runtime != null) ...[
          _AutoTradeArmedCard(
            runtime: runtime,
            userSettings: data.userSettings,
          ),
          const SizedBox(height: LuminSpacing.md),
        ],
        // The remaining cards (open positions, recent activity on
        // YOUR account, engine signal stream) only render once the
        // user has actually connected a Binance key.  Until then the
        // gate checklist above is the actionable surface.
        if (hasBinanceKey) ...[
          if (serverPositions != null) ...[
            _ServerPositionsCard(positions: serverPositions),
            const SizedBox(height: LuminSpacing.md),
          ],
          if (recentEvents != null) ...[
            _RecentDispatchEventsCard(events: recentEvents),
            const SizedBox(height: LuminSpacing.md),
          ],
          // Engine signal stream — what the engine is detecting right
          // now.  NOT user-specific.  Useful for traders to see
          // momentum; pure noise to users who haven't enabled.
          _ActivityCard(events: data.activity),
          const SizedBox(height: LuminSpacing.xl),
        ],
      ],
    );
  }

  /// Paper-tab body.  Owner 2026-05-17 — previously delegated entirely
  /// to PaperTradesPage (showing only the closed trade list).  Now the
  /// Paper tab carries everything paper:
  ///
  ///   * Paper on/off toggle (mode 'paper' <-> 'off').
  ///   * Paper P&L card (the engine-wide paper book, since the engine-
  ///     side paper broker is currently single-tenant; per-user paper
  ///     ledger lands in Phase 4).
  ///   * Paper open positions.
  ///   * Paper trade history (PaperTradesPage inline).
  Widget _buildPaperBody(BuildContext context, _TradeBundle data) {
    final scope = AppConfigScope.of(context);
    // Per-user only — do NOT fall back to ``data.autoMode.mode``
    // (engine-wide).  Pre-2026-05-23 the fallback was rendering Paper
    // mode "on" for every authenticated user whenever the engine's
    // global auto-mode was 'paper', because new users hadn't set
    // their own ``userSettings.mode`` yet.  Owner-reported: "trade>
    // paper there it's still showing default on".  Now null = off
    // and the off-state notice fires correctly.
    final activeMode = data.userSettings.mode ?? 'off';
    final paperActive = activeMode == 'paper' || activeMode == 'both';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        if (!scope.repo.isLive) const PreviewBadge(),
        _BinaryModeToggle(
          label: 'Paper trading',
          subtitle: paperActive
              ? 'Engine simulates fills — no real orders, zero risk.'
              : 'Off — turn on to simulate trades without real money.',
          icon: Icons.science_outlined,
          activeColor: LuminColors.warn, // Paper = caution colour, less than live
          isOn: paperActive,
          switching: _switchingMode,
          onChanged: (on) => _changeMode(on ? 'paper' : 'off'),
        ),
        if (!paperActive)
          const _OffStateNotice(
            label: 'Paper mode off',
            description: 'Flip the toggle above to start simulating fills '
                'against the engine\'s paper book.  Server-side live '
                'auto-trade is configured separately in Settings → '
                'Server-side auto-trade.',
          )
        else ...[
          const SizedBox(height: LuminSpacing.md),
          _ModePnlCard(
            autoMode: data.autoMode,
            hasBinance: false, // Paper view always shows engine paper P&L
          ),
          const SizedBox(height: LuminSpacing.md),
          _OpenPositionsCard(positions: data.positions),
          const SizedBox(height: LuminSpacing.md),
        ],
        // History below is independent of mode state — even when paper
        // is off, the user wants to see their past simulated trades.
        // PaperTradesPage owns its own header / pagination / refresh.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
          child: Text(
            'PAPER HISTORY',
            style: TextStyle(
              color: LuminColors.textMuted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: LuminSpacing.sm),
        // Embed the trade list as a sliver — physics: NeverScrollable so
        // the parent ListView drives the scroll; this lets the toggle +
        // P&L card scroll naturally above the trade history.
        const _EmbeddedPaperTrades(),
        const SizedBox(height: LuminSpacing.xl),
      ],
    );
  }

  static int _modeIndex(String mode) {
    switch (mode) {
      case 'paper':
        return 1;
      case 'live':
        return 2;
      default:
        return 0;
    }
  }

  static String _modeName(int idx) {
    switch (idx) {
      case 1:
        return 'paper';
      case 2:
        return 'live';
      default:
        return 'off';
    }
  }
}

/// Live | Paper sub-tab strip — sits just below the AppBar and toggles
/// the body between the existing execution-control surface and the new
/// paper trade history list.  Visual style mirrors the existing mode
/// toggle so the page feels coherent at a glance.
class _SubTabStrip extends StatelessWidget {
  const _SubTabStrip({required this.view, required this.onChanged});
  final _TradeView view;
  final ValueChanged<_TradeView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: LuminColors.bgDeep,
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg,
        LuminSpacing.sm,
        LuminSpacing.lg,
        LuminSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SubTabButton(
              label: 'Live',
              icon: Icons.bolt,
              selected: view == _TradeView.live,
              onTap: () => onChanged(_TradeView.live),
            ),
          ),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: _SubTabButton(
              label: 'Paper',
              icon: Icons.history,
              selected: view == _TradeView.paper,
              onTap: () => onChanged(_TradeView.paper),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTabButton extends StatelessWidget {
  const _SubTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LuminRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? LuminColors.accent.withOpacity(0.15)
                : LuminColors.bgElevated,
            borderRadius: BorderRadius.circular(LuminRadii.md),
            border: Border.all(
              color: selected
                  ? LuminColors.accent.withOpacity(0.50)
                  : LuminColors.cardBorder,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? LuminColors.accent
                    : LuminColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? LuminColors.accent
                      : LuminColors.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.switching,
    required this.onChanged,
  });

  final int mode;
  final bool switching;
  final ValueChanged<int> onChanged;

  static const _labels = ['Off', 'Paper', 'Live'];
  static const _icons = [
    Icons.power_settings_new,
    Icons.science_outlined,
    Icons.bolt,
  ];

  Color _modeColor(int i) {
    switch (i) {
      case 0:
        return LuminColors.textMuted;
      case 1:
        return LuminColors.warn;
      case 2:
        return LuminColors.loss;
      default:
        return LuminColors.textPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'AUTO-EXECUTION MODE',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (switching) ...[
                  const SizedBox(width: LuminSpacing.sm),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: LuminColors.accent,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            Row(
              children: [
                for (int i = 0; i < 3; i++) ...[
                  Expanded(
                    child: _ModeButton(
                      label: _labels[i],
                      icon: _icons[i],
                      selected: mode == i,
                      color: _modeColor(i),
                      onTap: switching ? null : () => onChanged(i),
                    ),
                  ),
                  if (i < 2) const SizedBox(width: LuminSpacing.sm),
                ],
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            Text(
              _description(mode),
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _description(int m) {
    switch (m) {
      case 0:
        return 'Auto-trade disabled. Signals still publish to Telegram.';
      case 1:
        return 'Paper mode — fills are simulated, no real orders. Zero risk.';
      case 2:
        return 'Live — real orders on Binance Futures. Risk gates active.';
      default:
        return '';
    }
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LuminRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : LuminColors.bgElevated,
            borderRadius: BorderRadius.circular(LuminRadii.md),
            border: Border.all(
              color: selected ? color.withOpacity(0.50) : LuminColors.cardBorder,
            ),
          ),
          child: Opacity(
            opacity: disabled ? 0.6 : 1.0,
            child: Column(
              children: [
                Icon(
                  icon,
                  color: selected ? color : LuminColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(height: LuminSpacing.xs),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : LuminColors.textSecondary,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mode-aware Today's P&L card.
///
/// Doctrine 2026-05-07: when the user selects PAPER mode the displayed PnL
/// must reflect the paper-trade ledger; LIVE mode → real-broker realised
/// PnL.  OFF mode → no trades are tracked, so the card shows a prompt to
/// switch rather than a misleading $0.00.
///
/// The backend already routes ``daily_pnl_usd`` through whichever broker
/// (PaperOrderManager or live OrderManager) is wired for the current mode,
/// so the value is correct out of the box — the card just labels it
/// appropriately and surfaces the equity / simulated-paper-total context
/// that subscribers asked for.
class _ModePnlCard extends StatelessWidget {
  const _ModePnlCard({required this.autoMode, this.hasBinance = false});
  final AutoModeStatus autoMode;

  /// Pre-server-side relabel flag — was used to switch the card's
  /// label between "user's real Binance P&L" vs "engine's paper
  /// P&L" when the OLD client-side path showed Binance positions
  /// alongside.  Now (post-server-side-execution cleanup) the card
  /// always shows engine paper P&L on the Paper sub-tab; left as
  /// a constructor parameter for now in case a follow-up restores
  /// per-user PnL via Firestore listeners.
  final bool hasBinance;

  @override
  Widget build(BuildContext context) {
    final mode = autoMode.mode;
    if (mode == 'off') {
      return _OffStateCard();
    }
    final isPaper = mode == 'paper' || mode == 'both';
    final pnl = autoMode.dailyPnlUsd;
    final positive = pnl >= 0;
    final accent = positive ? LuminColors.success : LuminColors.loss;
    // Phase 3c — honest label when Binance is connected: the
    // engine's paper P&L is not the user's P&L until Phase 4 ships
    // per-user PnL accounting.
    final label = hasBinance
        ? 'ENGINE PAPER P&L (not yours)'
        : isPaper
            ? "PAPER P&L TODAY"
            : "LIVE P&L TODAY";
    final subtitle = hasBinance
        ? 'Engine\'s reference paper trader.  Per-user PnL ships in Phase 4.'
        : isPaper
            ? 'Paper sim — zero risk, mirrors live execution'
            : 'Realised on Binance Futures';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPaper ? Icons.science_outlined : Icons.bolt,
                  size: 16,
                  color: isPaper ? LuminColors.warn : LuminColors.loss,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(
                  positive ? Icons.trending_up : Icons.trending_down,
                  size: 18,
                  color: accent,
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              formatPnl(pnl),
              style: TextStyle(
                color: accent,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${positive ? '+' : ''}${autoMode.dailyLossPct.toStringAsFixed(2)}% on equity',
              style: TextStyle(
                color: accent.withOpacity(0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            const Divider(color: LuminColors.cardBorder, height: 1),
            const SizedBox(height: LuminSpacing.sm),
            _MetaRow(
              label: 'Equity',
              value: '\$${autoMode.currentEquityUsd.toStringAsFixed(2)}',
            ),
            _MetaRow(
              label: 'Open positions',
              value: autoMode.openPositions.toString(),
            ),
            // Weekly + monthly aggregates from the persistent ledger
            // (engine PR #338).  Both default to 0.0 on pre-#338
            // backends so the row always renders.
            _MetaRow(
              label: 'Weekly P&L',
              value: formatPnl(autoMode.weeklyPnlUsd),
              valueColor: autoMode.weeklyPnlUsd >= 0
                  ? LuminColors.success
                  : LuminColors.loss,
            ),
            _MetaRow(
              label: 'Monthly P&L',
              value: formatPnl(autoMode.monthlyPnlUsd),
              valueColor: autoMode.monthlyPnlUsd >= 0
                  ? LuminColors.success
                  : LuminColors.loss,
            ),
            if (isPaper && autoMode.simulatedPnlUsd != null)
              _MetaRow(
                label: 'Paper total since boot',
                value: formatPnl(autoMode.simulatedPnlUsd!),
                valueColor: autoMode.simulatedPnlUsd! >= 0
                    ? LuminColors.success
                    : LuminColors.loss,
              ),
            if (autoMode.dailyKillTripped)
              const Padding(
                padding: EdgeInsets.only(top: LuminSpacing.sm),
                child: Text(
                  '⚠️  Daily-loss kill tripped — auto-trade halted',
                  style: TextStyle(
                    color: LuminColors.loss,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              subtitle,
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

class _OffStateCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Row(
          children: [
            const Icon(
              Icons.power_settings_new,
              size: 22,
              color: LuminColors.textMuted,
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Auto-trade is off',
                    style: TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'No trades tracked. Switch to Paper to simulate fills against live signals, or Live to trade with real funds.',
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? LuminColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenPositionsCard extends StatelessWidget {
  const _OpenPositionsCard({required this.positions});
  final List<MockPosition> positions;

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
                Icon(Icons.account_balance_wallet_outlined,
                    color: LuminColors.accent, size: 16),
                SizedBox(width: LuminSpacing.xs),
                Text(
                  'OPEN POSITIONS',
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
            if (positions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: LuminSpacing.lg),
                child: Center(
                  child: Text(
                    'No open positions',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              for (int i = 0; i < positions.length; i++) ...[
                _PositionRow(p: positions[i]),
                if (i < positions.length - 1)
                  const Divider(
                    color: LuminColors.cardBorder,
                    height: LuminSpacing.lg,
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.p});
  final MockPosition p;

  @override
  Widget build(BuildContext context) {
    final isLong = p.direction == 'LONG';
    final pnlPositive = p.pnlPct >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              p.symbol,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: LuminSpacing.xs),
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
                p.direction,
                style: TextStyle(
                  color: isLong ? LuminColors.success : LuminColors.loss,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Spacer(),
            Text(
              '${pnlPositive ? '+' : ''}\$${p.pnlUsd.toStringAsFixed(2)}',
              style: TextStyle(
                color: pnlPositive ? LuminColors.success : LuminColors.loss,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: LuminSpacing.xs),
        Text(
          'qty ${p.qty} @ ${p.entry.toStringAsFixed(2)} → ${p.currentPrice.toStringAsFixed(2)}',
          style: const TextStyle(
            color: LuminColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${p.minutesOpen}m open • ${pnlPositive ? '+' : ''}${p.pnlPct.toStringAsFixed(2)}%',
          style: TextStyle(
            color: pnlPositive ? LuminColors.success : LuminColors.loss,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.events});
  final List<MockActivityEvent> events;

  String _agoLabel(int m) {
    if (m < 60) return '${m}m';
    if (m < 1440) return '${(m / 60).round()}h';
    return '${(m / 1440).round()}d';
  }

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
                Icon(Icons.list_alt_outlined,
                    color: LuminColors.accent, size: 16),
                SizedBox(width: LuminSpacing.xs),
                Text(
                  'ACTIVITY',
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
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: LuminSpacing.lg),
                child: Center(
                  child: Text(
                    'No activity yet',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              for (int i = 0; i < events.length; i++) ...[
                _ActivityRow(
                  event: events[i],
                  ago: _agoLabel(events[i].minutesAgo),
                ),
                if (i < events.length - 1)
                  const SizedBox(height: LuminSpacing.md),
              ],
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event, required this.ago});
  final MockActivityEvent event;
  final String ago;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: event.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(LuminRadii.sm),
          ),
          alignment: Alignment.center,
          child: Text(
            event.kind,
            style: TextStyle(
              color: event.color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: LuminSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                event.subtitle,
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Text(
          ago,
          style: const TextStyle(
            color: LuminColors.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Section-shaped skeleton rendered before the first engine emit lands
/// (cold start with no cache).  Mirrors the Trade page layout: mode
/// pill row + balance card + positions list (3 row placeholders) +
/// activity log (4 row placeholders).  Static gray boxes — same
/// rationale as Phase 2a/2b's skeletons.
class _TradeLoading extends StatelessWidget {
  const _TradeLoading();

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
        _TradeSkeletonCard(height: 48), // Mode pill
        SizedBox(height: LuminSpacing.md),
        _TradeSkeletonCard(height: 104), // Balance / PnL card
        SizedBox(height: LuminSpacing.md),
        _TradeSkeletonCard(height: 72), // Position row
        SizedBox(height: LuminSpacing.sm),
        _TradeSkeletonCard(height: 72), // Position row
        SizedBox(height: LuminSpacing.sm),
        _TradeSkeletonCard(height: 72), // Position row
        SizedBox(height: LuminSpacing.md),
        _TradeSkeletonCard(height: 56), // Activity header
        SizedBox(height: LuminSpacing.sm),
        _TradeSkeletonCard(height: 44), // Activity row
        SizedBox(height: LuminSpacing.sm),
        _TradeSkeletonCard(height: 44), // Activity row
        SizedBox(height: LuminSpacing.sm),
        _TradeSkeletonCard(height: 44), // Activity row
        SizedBox(height: LuminSpacing.sm),
        _TradeSkeletonCard(height: 44), // Activity row
        SizedBox(height: LuminSpacing.xl),
      ],
    );
  }
}

class _TradeSkeletonCard extends StatelessWidget {
  const _TradeSkeletonCard({required this.height});
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

class _TradeError extends StatelessWidget {
  const _TradeError({required this.error, required this.onRetry});
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
          'Could not load Trade state',
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

/// Binary on/off toggle for a single mode (live or paper).  Owner
/// 2026-05-17 redesign — replaces the tri-state `_ModeToggle` card in
/// the Live body.  Each top-tab now hosts its own instance so the
/// user toggles the mode FROM the tab that displays it.
///
/// Visual style mirrors a hero card: large icon, label + descriptive
/// subtitle, prominent Switch.  ``activeColor`` is per-mode (LIVE uses
/// the loss/red accent for caution; Paper uses warn/amber).
class _BinaryModeToggle extends StatelessWidget {
  const _BinaryModeToggle({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.activeColor,
    required this.isOn,
    required this.switching,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final Color activeColor;
  final bool isOn;
  final bool switching;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final border = isOn ? activeColor : LuminColors.cardBorder;
    final iconColor = isOn ? activeColor : LuminColors.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg,
        LuminSpacing.md,
        LuminSpacing.lg,
        LuminSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(
            color: border,
            width: isOn ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: LuminSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: LuminColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
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
            if (switching)
              const Padding(
                padding: EdgeInsets.only(left: LuminSpacing.md),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Switch(
                value: isOn,
                activeColor: activeColor,
                onChanged: onChanged,
              ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight notice rendered when a tab's mode is off.  Less heavy
/// than _OffStateCard — fits naturally below the toggle without a
/// competing CTA, since the toggle IS the CTA.
class _OffStateNotice extends StatelessWidget {
  const _OffStateNotice({required this.label, required this.description});
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(LuminSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.circular(LuminRadii.md),
          border: Border.all(color: LuminColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: LuminColors.textMuted,
                  size: 16,
                ),
                const SizedBox(width: LuminSpacing.sm),
                Text(
                  label,
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              description,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Embedded paper-trades list — wraps PaperTradesPage for use inside
/// the Paper tab's scrollable parent.  PaperTradesPage owns its own
/// AppBar + Scaffold; we strip those by mounting it inside a sized
/// container that the parent ListView drives.
///
/// Implementation: PaperTradesPage is a full Scaffold; embedding it
/// raw inside the parent ListView would duplicate the AppBar and
/// crash on conflicting scroll controllers.  We give it a fixed-height
/// constraint and let its own ScrollController handle pagination —
/// the parent ListView's scroll physics defer to the embedded view
/// once the user reaches the trade-list region.  Future improvement:
/// extract a non-Scaffold widget from PaperTradesPage that this can
/// directly host without the height constraint.
class _EmbeddedPaperTrades extends StatelessWidget {
  const _EmbeddedPaperTrades();

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    // 60% of viewport — enough to show ~4 trade cards without the
    // parent ListView feeling cramped; the embedded list's own scroll
    // takes over when the user dives into history.
    return SizedBox(
      height: viewportHeight * 0.60,
      child: const PaperTradesPage(),
    );
  }
}


/// Banner shown at the top of the Trade tab when the user can't
/// currently auto-trade — engine PR-14 follow-up 3/3.
///
/// Two distinct messages:
///   * Globally disabled (operator hasn't flipped
///     ``auto_trade_globally_enabled``) — "Auto-trade is paused
///     engine-wide".
///   * User-specifically disabled (per-user circuit breaker tripped
///     or operator manual action) — "Your auto-trade is disabled.
///     Contact support to re-enable."  The disabledReason field
///     when populated is appended for context.
class _AutoTradeDisabledBanner extends StatelessWidget {
  const _AutoTradeDisabledBanner({required this.status});

  final AutoTradeUserStatus status;

  @override
  Widget build(BuildContext context) {
    final isUserSpecific = status.autoTradeUserDisabled;
    final title = isUserSpecific
        ? 'Your auto-trade is disabled'
        : 'Auto-trade paused engine-wide';
    final body = isUserSpecific
        ? 'Your account has been auto-disabled by a safety check.  '
            'Contact support via the Lumin Telegram channel to '
            're-enable.${status.disabledReason.isNotEmpty ? "\n\nReason: ${status.disabledReason}" : ""}'
        : 'The operator has not enabled auto-trade engine-wide yet.  '
            'New positions will not be placed until the global '
            'enable flag is flipped.';
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.lg,
        vertical: LuminSpacing.sm,
      ),
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUserSpecific ? LuminColors.loss : LuminColors.warn,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isUserSpecific ? Icons.block : Icons.pause_circle_outline,
            color: isUserSpecific ? LuminColors.loss : LuminColors.warn,
            size: 20,
          ),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isUserSpecific
                        ? LuminColors.loss
                        : LuminColors.warn,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: LuminSpacing.xs),
                Text(
                  body,
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// Per-user auto-pause banner (engine PR #479).
///
/// Renders on the Live tab when ``data.userSettings.pausedReason`` is set,
/// which happens after the engine sees N consecutive Binance ``-2019``
/// (insufficient margin) rejections for this user. Carries an inline
/// "Resume" button that fires :meth:`LuminRepository.resumeMineAutoTrade`
/// to clear the pause; the parent's ``onResumed`` callback triggers a
/// refresh so the banner disappears and Recent Activity starts updating
/// again on the next signal.
///
/// Why a separate banner rather than reusing ``_AutoTradeDisabledBanner``:
/// the existing banner is sourced from ``AutoTradeUserStatus`` (the
/// engine-wide + per-user safety-gate result), and its messaging is
/// "contact support" — the user can't self-recover. Auto-pause is the
/// opposite: it IS the user's job to fix (top up Futures wallet) and
/// they CAN self-recover (tap Resume).  Sharing the widget would force
/// awkward branches; cleaner to keep them as sibling banners.
class _AutoPauseBanner extends StatefulWidget {
  const _AutoPauseBanner({
    required this.settings,
    required this.onResumed,
  });

  final AutoTradeSettings settings;
  final Future<void> Function() onResumed;

  @override
  State<_AutoPauseBanner> createState() => _AutoPauseBannerState();
}

class _AutoPauseBannerState extends State<_AutoPauseBanner> {
  bool _resuming = false;

  /// Plain-English copy keyed off the engine's typed reason string.
  /// Forward-compatible default: when the engine introduces a new
  /// reason (e.g. ``'binance_key_revoked'``), the app renders a
  /// generic banner instead of a blank — the raw reason becomes the
  /// subtitle so the operator can still see what happened.
  String get _title {
    switch (widget.settings.pausedReason) {
      case 'insufficient_margin':
        return 'Auto-trade paused — wallet empty';
      default:
        return 'Auto-trade paused';
    }
  }

  String get _body {
    switch (widget.settings.pausedReason) {
      case 'insufficient_margin':
        return 'Your Binance Futures wallet does not have enough '
            'USDT to open positions at your current notional. '
            'Top up the Futures wallet, then tap Resume.';
      default:
        return 'The engine paused dispatching for this account. '
            'Reason: ${widget.settings.pausedReason ?? "unknown"}. '
            'Tap Resume to clear once the underlying issue is fixed.';
    }
  }

  Future<void> _onResume() async {
    if (_resuming) return;
    setState(() => _resuming = true);
    final repo = AppConfigScope.of(context).repo;
    try {
      final cleared = await repo.resumeMineAutoTrade();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cleared
                ? 'Auto-trade resumed. Next signal will dispatch.'
                : 'Already active — no pause to clear.',
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: LuminColors.success,
        ),
      );
      await widget.onResumed();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resume failed: $e'),
          duration: const Duration(seconds: 4),
          backgroundColor: LuminColors.loss,
        ),
      );
    } finally {
      if (mounted) setState(() => _resuming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.lg,
        vertical: LuminSpacing.sm,
      ),
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: LuminColors.warn, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.pause_circle_outline,
                color: LuminColors.warn,
                size: 20,
              ),
              const SizedBox(width: LuminSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: LuminColors.warn,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: LuminSpacing.xs),
                    Text(
                      _body,
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: LuminColors.warn,
                foregroundColor: LuminColors.bgDeep,
              ),
              onPressed: _resuming ? null : _onResume,
              icon: _resuming
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: LuminColors.bgDeep,
                      ),
                    )
                  : const Icon(Icons.play_arrow, size: 16),
              label: const Text(
                'Resume',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Live-tab gate-state card: shows the four configurable auto-trade
/// gates the FSM checks before placing any order, plus the symbol
/// allowlist as a footnote.  Card colour reflects ``armed`` —
/// green when all four gates pass + user_mode == 'live', warn-yellow
/// otherwise.
class _AutoTradeArmedCard extends StatelessWidget {
  const _AutoTradeArmedCard({
    required this.runtime,
    required this.userSettings,
  });

  final AutoTradeRuntimeStatus runtime;

  /// Per-user settings — carries the engine PR #479 ``pausedReason``
  /// flag the dispatcher sets after consecutive ``-2019`` rejections.
  /// Folded into the "Your account not paused" gate below so the card
  /// matches the [_AutoPauseBanner] sibling above it (pre-2026-05-24,
  /// the card read ``autoTradeUserDisabled`` only and would show "not
  /// paused ✓" while the banner above declared the user paused —
  /// owner-reported contradiction).
  final AutoTradeSettings userSettings;

  /// True when EITHER the engine-wide per-user circuit breaker has
  /// tripped (operator-managed, ``contact support`` flow) OR the
  /// dispatcher has auto-paused this user (#479, self-recoverable
  /// via the Resume button on the banner above). Either condition
  /// stops live orders — collapsing them under one gate row keeps
  /// the card honest about whether dispatch can fire.
  bool get _isPaused =>
      runtime.autoTradeUserDisabled || userSettings.isAutoPaused;

  /// Card-level "armed" state: the engine's snapshot AND no per-user
  /// pause. The engine's ``armed`` already accounts for
  /// ``autoTradeUserDisabled``; we AND-in ``isAutoPaused`` because
  /// the engine's runtime status is engine-wide-stack snapshot, not
  /// per-user pause state.
  bool get _armed => runtime.armed && !userSettings.isAutoPaused;

  @override
  Widget build(BuildContext context) {
    final accent = _armed ? LuminColors.success : LuminColors.warn;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.md),
        border: Border.all(color: accent.withOpacity(0.40)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _armed
                      ? Icons.shield_outlined
                      : Icons.shield_moon_outlined,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: LuminSpacing.sm),
                Text(
                  _armed
                      ? 'Auto-trade ARMED'
                      : 'Auto-trade not armed',
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            _gateRow(
              label: 'Engine-wide enabled',
              ok: runtime.autoTradeGloballyEnabled,
              hint: runtime.autoTradeGloballyEnabled
                  ? null
                  : 'Operator hasn\'t flipped the global flag yet.',
            ),
            _gateRow(
              label: 'Your account not paused',
              ok: !_isPaused,
              hint: _isPaused
                  ? (userSettings.isAutoPaused
                      ? (userSettings.pausedReason == 'insufficient_margin'
                          ? 'Wallet empty — top up + tap Resume above.'
                          : 'Auto-paused: ${userSettings.pausedReason ?? "unknown"}. '
                              'Tap Resume above.')
                      : 'Per-user circuit breaker tripped.')
                  : null,
            ),
            _gateRow(
              label: 'Binance key connected',
              ok: runtime.binanceKeyConnected,
              hint: runtime.binanceKeyConnected
                  ? null
                  : 'Settings → Server-side auto-trade.',
            ),
            _gateRow(
              label: 'Mode = live',
              ok: runtime.userMode == 'live' || runtime.userMode == 'both',
              hint: (runtime.userMode == 'live' || runtime.userMode == 'both')
                  ? null
                  : runtime.userMode == null
                      ? 'Settings → Auto-trade → enable Live.'
                      : 'Currently ${runtime.userMode!.toUpperCase()} — '
                          'enable Live in Auto-trade settings.',
            ),
            // Symbol allowlist — only meaningful once the user has a
            // Binance key connected (otherwise no orders flow through
            // anyway, so showing "85 active symbols" is just clutter).
            // When shown, render as a compact count + "view details"
            // link to Settings → Symbol preference rather than dumping
            // the full 85-pair list as a wall of text.  Owner-reported
            // 2026-05-23: "pairs list is ugly".
            if (runtime.binanceKeyConnected &&
                runtime.allowedSymbols.isNotEmpty) ...[
              const SizedBox(height: LuminSpacing.sm),
              _SymbolAllowlistSummary(runtime: runtime),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gateRow({
    required String label,
    required bool ok,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: ok ? LuminColors.success : LuminColors.warn,
          ),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
                if (hint != null)
                  Text(
                    hint,
                    style: const TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// Compact replacement for the pre-2026-05-23 80-pair wall-of-text
/// inside :class:`_AutoTradeArmedCard`.  Renders one line summarising
/// the user's effective allowlist + a single-line variant of the
/// "blast-radius cap" footnote.  Detail belongs on Settings → Symbol
/// preference, not on the Live tab.
///
/// Three states:
///   * Effective list empty: explicit "opted out of everything" note.
///   * Effective < engine cap (user has narrowed): "N of M symbols".
///   * Effective == engine cap: "N symbols allowed".
class _SymbolAllowlistSummary extends StatelessWidget {
  const _SymbolAllowlistSummary({required this.runtime});

  final AutoTradeRuntimeStatus runtime;

  @override
  Widget build(BuildContext context) {
    final effective = runtime.effectiveAllowedSymbols.length;
    final total = runtime.allowedSymbols.length;
    final narrowed = effective != total;
    final String headline;
    final Color headlineColor;
    if (effective == 0) {
      headline = 'You opted out of every symbol';
      headlineColor = LuminColors.loss;
    } else if (narrowed) {
      headline = '$effective of $total symbols enabled';
      headlineColor = LuminColors.accent;
    } else {
      headline = '$total symbols enabled — engine allowlist';
      headlineColor = LuminColors.textSecondary;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const SymbolPreferencePage(),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LuminSpacing.sm,
            vertical: LuminSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: LuminColors.bgDeep,
            borderRadius: BorderRadius.circular(LuminRadii.sm),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.filter_list,
                size: 14,
                color: LuminColors.textMuted,
              ),
              const SizedBox(width: LuminSpacing.xs),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    color: headlineColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const Text(
                'Edit',
                style: TextStyle(
                  color: LuminColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.arrow_forward,
                size: 12,
                color: LuminColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Live-tab open-positions card backed by ``/api/auto-trade/positions``.
/// Empty list → empty-state copy explaining that auto-trade will
/// surface positions here when a whitelisted signal fires.
class _ServerPositionsCard extends StatelessWidget {
  const _ServerPositionsCard({required this.positions});

  final List<ServerSidePosition> positions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: LuminColors.textSecondary,
                ),
                const SizedBox(width: LuminSpacing.sm),
                const Text(
                  'YOUR OPEN POSITIONS',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${positions.length}',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            if (positions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: LuminSpacing.sm),
                child: Text(
                  'No open positions yet.  When a whitelisted signal '
                  'fires and every gate above is green, Lumin places the '
                  'order on Binance and it shows up here.',
                  style: TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              )
            else
              for (final p in positions) _ServerPositionRow(position: p),
          ],
        ),
      ),
    );
  }
}


class _ServerPositionRow extends StatelessWidget {
  const _ServerPositionRow({required this.position});

  final ServerSidePosition position;

  @override
  Widget build(BuildContext context) {
    final isLong = position.side == 'LONG';
    final dirColor = isLong ? LuminColors.success : LuminColors.loss;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: dirColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(LuminRadii.sm),
            ),
            child: Text(
              position.side,
              style: TextStyle(
                color: dirColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      position.symbol,
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: LuminSpacing.sm),
                    Text(
                      position.state,
                      style: const TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (position.pretpFired) ...[
                      const SizedBox(width: 4),
                      const Text(
                        '· Pre-TP banked',
                        style: TextStyle(
                          color: LuminColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  'Entry ${_fmtPrice(position.entryPriceFilled > 0 ? position.entryPriceFilled : position.entryPriceTarget)}'
                  ' • SL ${_fmtPrice(position.slPrice)}'
                  ' • TP1 ${_fmtPrice(position.tp1Price)}',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (position.realizedPnlTotal.abs() > 0.01)
            Text(
              '${position.realizedPnlTotal >= 0 ? '+' : ''}'
              '\$${position.realizedPnlTotal.toStringAsFixed(2)}',
              style: TextStyle(
                color: position.realizedPnlTotal >= 0
                    ? LuminColors.success
                    : LuminColors.loss,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }

  String _fmtPrice(double v) {
    if (v >= 1000) return v.toStringAsFixed(2);
    if (v >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(6);
  }
}


/// Trade-tab "Recent activity for your account" card.  Renders the
/// last N dispatch events (placed + rejected) from
/// ``/api/auto-trade/recent-events`` with a severity-coloured chip
/// per row + plain-English translation of the rejection reason from
/// [DispatchEventTranslation].
///
/// Hierarchy in the Live body (top → bottom):
///
///   1. Auto-trade disabled banner (if user/global disabled)
///   2. Auto-trade armed card (gate states)
///   3. Your open positions
///   4. **Recent activity for your account** ← this card
///   5. Engine signal stream (global, not per-user)
///
/// This card sits between #3 and #5 because conceptually it's the
/// audit log of "what did the engine try to do on MY account" —
/// natural follow-on from "what's open on my account" and natural
/// precursor to "what's the engine seeing globally".
class _RecentDispatchEventsCard extends StatelessWidget {
  const _RecentDispatchEventsCard({required this.events});

  final List<DispatchEvent> events;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history_outlined,
                  size: 16,
                  color: LuminColors.textSecondary,
                ),
                const SizedBox(width: LuminSpacing.sm),
                const Text(
                  'RECENT ACTIVITY ON YOUR ACCOUNT',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${events.length}',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: LuminSpacing.sm),
                child: Text(
                  'No order activity on your account yet.  Each time the '
                  'engine tries to place an order for you — successful or '
                  'rejected — it will show up here with the reason.',
                  style: TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              )
            else
              for (final e in events) _DispatchEventRow(event: e),
          ],
        ),
      ),
    );
  }
}


class _DispatchEventRow extends StatelessWidget {
  const _DispatchEventRow({required this.event});

  final DispatchEvent event;

  @override
  Widget build(BuildContext context) {
    final tx = DispatchEventTranslation.forEvent(event);
    final chipColor = _chipColor(tx.severity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: chipColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(LuminRadii.sm),
            ),
            child: Text(
              _chipLabel(tx.severity),
              style: TextStyle(
                color: chipColor,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      event.symbol,
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: LuminSpacing.sm),
                    Text(
                      event.direction,
                      style: TextStyle(
                        color: event.direction == 'LONG'
                            ? LuminColors.success
                            : LuminColors.loss,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatRelativeTime(event.timestamp),
                      style: const TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  tx.headline,
                  style: TextStyle(
                    color: chipColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (tx.action.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    tx.action,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _chipColor(DispatchEventSeverity sev) {
    switch (sev) {
      case DispatchEventSeverity.success:
        return LuminColors.success;
      case DispatchEventSeverity.userAction:
        return LuminColors.warn;
      case DispatchEventSeverity.system:
        return LuminColors.loss;
      case DispatchEventSeverity.transient:
        return LuminColors.textSecondary;
    }
  }

  static String _chipLabel(DispatchEventSeverity sev) {
    switch (sev) {
      case DispatchEventSeverity.success:
        return 'PLACED';
      case DispatchEventSeverity.userAction:
        return 'ACTION';
      case DispatchEventSeverity.system:
        return 'SYSTEM';
      case DispatchEventSeverity.transient:
        return 'RETRY';
    }
  }

  static String _formatRelativeTime(DateTime ts) {
    final now = DateTime.now().toUtc();
    final diff = now.difference(ts.toUtc());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

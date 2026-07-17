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
/// Both tabs can be ON simultaneously via ``mode='both'``: enabling live
/// while paper is active sends 'both'; the toggle on each tab preserves
/// the other tab's state.  Each tab's toggle is a view onto the shared
/// ``mode`` string from that tab's perspective.
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

import '../../app/foreground_refresh.dart';
import '../../data/app_config.dart';
import '../../data/mock_data.dart';
import '../../data/order_log.dart';
import '../../data/repository.dart';
import '../../data/server_side_execution_models.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';
import 'live_status_card.dart';
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

class _TradePageState extends State<TradePage>
    implements ForegroundRefreshable {
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
  _TradeBundle? _lastBundle;
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

  // Orders placed from THIS phone via the device-key path (one-tap
  // signal takes + alert takes) — read from the existing per-user
  // OrderLogService so the Live feed shows everything the Binance API
  // actually executed for this user, whichever path placed it
  // (owner decision, 2026-07-17).
  List<OrderLogEntry> _phoneOrders = const [];
  final _phoneOrderLog = OrderLogService();

  Future<void> _loadPhoneOrders() async {
    final uid = AppConfigScope.of(context).userId;
    if (uid == null) return;
    try {
      final entries = (await _phoneOrderLog.load(uid)).values.toList()
        ..sort((a, b) => b.placedAt.compareTo(a.placedAt));
      if (!mounted) return;
      setState(() => _phoneOrders = entries.take(10).toList());
    } catch (_) {
      // Non-fatal — the phone-placed section just stays empty.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppConfigScope.of(context).repo;
    if (repo != _lastRepo) {
      _lastRepo = repo;
      _resubscribe();
      _resubscribeAuxStreams();
      _loadPhoneOrders();
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
    if (!mounted) return;
    _engineSub?.cancel();
    _bundleController?.close();
    final repo = AppConfigScope.of(context).repo;
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

  @override
  void refreshFromForeground() {
    // App resumed on the Trade tab — the trust surface for auto-trade.
    // Mirror pull-to-refresh's invalidate set (engine snapshot + the four
    // per-user aux streams) so a backgrounded view doesn't show stale
    // positions/activity — the exact "old binance activity not updating"
    // class the aux invalidation fixed for the gesture path. No spinner;
    // retained data stays on screen until fresh values arrive.
    if (!mounted) return;
    final repo = AppConfigScope.of(context).repo;
    repo.invalidateTradeEngineSnapshotCache();
    repo.invalidateAutoTradeUserStatusCache();
    repo.invalidateAutoTradeRuntimeStatusCache();
    repo.invalidateAutoTradePositionsCache();
    repo.invalidateRecentDispatchEventsCache(limit: 20);
    _resubscribe();
    _resubscribeAuxStreams();
    _loadPhoneOrders();
  }

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
    _loadPhoneOrders();
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
    if (newMode == 'live' || newMode == 'both') {
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not change the mode — check your connection and '
            'try again.',
          ),
          duration: Duration(seconds: 4),
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
    // Both toggles can be ON simultaneously (mode='both').  Each toggle
    // preserves the other tab's state — enabling live while paper is on
    // sends 'both' rather than overwriting paper with 'off'.
    return Scaffold(
      appBar: AppBar(title: const Text('Trade')),
      body: Column(
        children: [
          _SubTabStrip(
            view: _view,
            onChanged: (v) {
              setState(() => _view = v);
              // Auto-enable paper when switching to the Paper tab only if
              // mode is currently off — no confirmation needed since paper
              // is zero-risk simulated fills.  Live is left untouched.
              if (v == _TradeView.paper) {
                final mode = _lastBundle?.userSettings.mode ?? 'off';
                if (mode == 'off') {
                  _changeMode('paper');
                }
              }
            },
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
                  // Cache latest bundle so tab-switch handler above can
                  // read the current mode without a round-trip.
                  if (_lastBundle != data) {
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) { if (mounted) setState(() => _lastBundle = data); });
                  }
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

  /// Live-tab body — 2026-07-17 redesign.
  ///
  /// Owner decisions behind this shape:
  ///   * ONE status surface ([LiveStatusCard]) replaces the old
  ///     three-card stack (disabled banner + auto-pause banner + armed
  ///     checklist) that read like an ops console.  Same engine truth,
  ///     one verdict + one next step; the full gate list lives behind
  ///     its Details expander.
  ///   * The Live feed is PER-USER ONLY: your open positions + what
  ///     the Binance API actually executed for you (auto dispatches,
  ///     one-tap takes, and phone-placed alert takes from the device
  ///     order log).  The engine-wide signal stream is gone from this
  ///     tab — that life belongs to the Signals/Pulse tabs.
  ///   * One merged "no trades yet" state instead of two stacked empty
  ///     cards.
  Widget _buildLiveBody(BuildContext context, _TradeBundle data) {
    final scope = AppConfigScope.of(context);
    final runtime = _runtimeStatus;
    final serverPositions = _serverPositions;
    final recentEvents = _recentDispatchEvents;
    // usingDefaults is true when fetchUserAutoTradeSettings failed AND no
    // disk cache exists — the engine couldn't be reached and we have no
    // prior data.  In that case mode is null and we must NOT render both
    // toggles as "Off" (that would falsely imply the engine is idle).
    final settingsUnknown = data.userSettings.usingDefaults ?? false;
    final activeMode = data.userSettings.mode ?? 'off';
    final liveActive = activeMode == 'live' || activeMode == 'both';
    final paperActive = activeMode == 'paper' || activeMode == 'both';
    // Non-traders get a stripped-down Live tab until a key is
    // connected — the status card is the actionable surface and the
    // trade cards would all be structurally empty.
    final hasBinanceKey =
        runtime != null && runtime.binanceKeyConnected;
    final hasAnyTrades = (serverPositions?.isNotEmpty ?? false) ||
        (recentEvents?.isNotEmpty ?? false) ||
        _phoneOrders.isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: [
        if (!scope.repo.isLive) const PreviewBadge(),
        // When the settings fetch failed and no disk cache exists, we
        // genuinely don't know the user's mode — show a banner rather
        // than rendering both toggles Off (which reads as "trading is
        // stopped" when it might not be).
        if (settingsUnknown)
          _SettingsUnknownBanner(onRetry: _refresh),
        // Live-mode toggle — same pattern as the Paper tab.  Preserves
        // paper mode when toggling live: enabling live while paper is on
        // sends 'both'; disabling live while paper is on keeps 'paper'.
        _BinaryModeToggle(
          label: 'Live auto-trade',
          subtitle: liveActive
              ? 'Lumin places real Binance Futures orders on your account.'
              : 'Off — enable to place real orders on the next signal.',
          icon: Icons.bolt_rounded,
          activeColor: LuminColors.accent,
          isOn: liveActive,
          switching: _switchingMode,
          onChanged: (on) {
            if (on) {
              _changeMode(paperActive ? 'both' : 'live');
            } else {
              _changeMode(paperActive ? 'paper' : 'off');
            }
          },
        ),
        const SizedBox(height: LuminSpacing.md),
        // Single status surface — hidden until the first runtime-status
        // fetch lands so the card doesn't flicker red→green during the
        // initial RTT.
        if (runtime != null) ...[
          LiveStatusCard(
            runtime: runtime,
            userStatus: _autoTradeStatus,
            userSettings: data.userSettings,
            onResumed: _refresh,
          ),
          const SizedBox(height: LuminSpacing.md),
        ],
        // Per-user trade surfaces, only once a key is connected.
        if (hasBinanceKey) ...[
          if (!hasAnyTrades &&
              serverPositions != null &&
              recentEvents != null)
            const _NoTradesYetCard()
          else ...[
            if (serverPositions != null) ...[
              _ServerPositionsCard(positions: serverPositions),
              const SizedBox(height: LuminSpacing.md),
            ],
            if (recentEvents != null) ...[
              _RecentDispatchEventsCard(
                events: recentEvents,
                phoneOrders: _phoneOrders,
              ),
              const SizedBox(height: LuminSpacing.md),
            ],
          ],
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
          onChanged: (on) {
            // Preserve live mode: turning paper on while live is active
            // sends 'both'; turning paper off while live is active keeps
            // 'live' rather than falling back to 'off'.
            final liveActive =
                activeMode == 'live' || activeMode == 'both';
            if (on) {
              _changeMode(liveActive ? 'both' : 'paper');
            } else {
              _changeMode(liveActive ? 'live' : 'off');
            }
          },
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

/// Banner shown when the engine couldn't be reached and no disk cache
/// exists — we genuinely don't know the user's current mode.  Prevents
/// the UI from rendering both toggles as "Off" (which falsely implies
/// trading is stopped) when the engine might still be executing.
class _SettingsUnknownBanner extends StatelessWidget {
  const _SettingsUnknownBanner({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LuminSpacing.lg, LuminSpacing.md, LuminSpacing.lg, 0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.md,
          vertical: LuminSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: LuminColors.warn.withOpacity(0.10),
          borderRadius: BorderRadius.circular(LuminRadii.sm),
          border: Border.all(color: LuminColors.warn.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: LuminColors.warn, size: 16),
            const SizedBox(width: LuminSpacing.sm),
            const Expanded(
              child: Text(
                'Status unknown — could not reach engine. '
                'Toggles below may not reflect actual state.',
                style: TextStyle(
                  color: LuminColors.warn,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Retry',
                style: TextStyle(color: LuminColors.warn, fontSize: 12),
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
                  'No open positions right now.  When an eligible signal '
                  'fires, Lumin places the order on your Binance account '
                  'and it shows up here.',
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
  const _RecentDispatchEventsCard({
    required this.events,
    this.phoneOrders = const [],
  });

  final List<DispatchEvent> events;

  /// Orders placed from this phone via device keys (one-tap signal
  /// takes + alert takes), merged chronologically with the server-side
  /// events so the card is the complete "what actually executed on my
  /// Binance account" record (owner decision, 2026-07-17).
  final List<OrderLogEntry> phoneOrders;

  @override
  Widget build(BuildContext context) {
    // Merge the two sources newest-first.
    final rows = <(DateTime, Widget)>[
      for (final e in events)
        (e.timestamp, _DispatchEventRow(event: e)),
      for (final o in phoneOrders)
        (o.placedAt, _PhoneOrderRow(entry: o)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
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
                  'YOUR TRADES',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${rows.length}',
                  style: const TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.sm),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: LuminSpacing.sm),
                child: Text(
                  'No trades on your account yet.  Every order Lumin '
                  'places — or skips — for you shows up here with the '
                  'reason.',
                  style: TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              )
            else
              for (final (_, w) in rows) w,
          ],
        ),
      ),
    );
  }
}


/// One trade you place from THIS phone (device-key path: one-tap
/// signal takes and alert takes) — read from the local order log,
/// which records what Binance actually accepted.
class _PhoneOrderRow extends StatelessWidget {
  const _PhoneOrderRow({required this.entry});

  final OrderLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final isBuy = entry.side == 'BUY';
    final dirColor = isBuy ? LuminColors.success : LuminColors.loss;
    final isAlert = entry.signalId.startsWith('alert-');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: LuminColors.accent.withOpacity(0.16),
              borderRadius: BorderRadius.circular(LuminRadii.sm),
            ),
            child: const Text(
              'PHONE',
              style: TextStyle(
                color: LuminColors.accent,
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
                      entry.symbol,
                      style: const TextStyle(
                        color: LuminColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: LuminSpacing.sm),
                    Text(
                      isBuy ? 'LONG' : 'SHORT',
                      style: TextStyle(
                        color: dirColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _DispatchEventRow._formatRelativeTime(entry.placedAt),
                      style: const TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isAlert
                      ? 'Placed from this phone (alert take)'
                      : 'Placed from this phone (signal take)',
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
    );
  }
}


/// Merged empty state — replaces the two stacked verbose empty cards
/// (positions + activity) that made a fresh account's Live tab read
/// like a wall of warnings (owner screenshots, 2026-07-17).
class _NoTradesYetCard extends StatelessWidget {
  const _NoTradesYetCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        padding: const EdgeInsets.all(LuminSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Icon(
                  Icons.hourglass_empty_rounded,
                  size: 16,
                  color: LuminColors.textSecondary,
                ),
                SizedBox(width: LuminSpacing.sm),
                Text(
                  'NO TRADES YET',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SizedBox(height: LuminSpacing.sm),
            Text(
              'When Lumin places — or skips — a trade on your account, '
              'your positions and full activity appear here with the '
              'reason for every decision.',
              style: TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
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
                    if (event.source == 'manual_take' ||
                        event.source == 'auto') ...[
                      const SizedBox(width: LuminSpacing.sm),
                      Text(
                        event.source == 'manual_take' ? 'One-tap' : 'Auto',
                        style: const TextStyle(
                          color: LuminColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

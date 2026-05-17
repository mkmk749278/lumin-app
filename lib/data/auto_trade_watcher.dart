/// AutoTradeWatcher — polls /api/signals on a timer and auto-fires
/// orders for new ACTIVE signals when the user's auto-trade mode is
/// live or paper.
///
/// Phase 3b-2 of the per-user expansion.
///
/// Lifecycle:
///   * One watcher per app lifetime, owned by ``AppConfigScope``.
///   * ``ensureRunning()`` starts the poll loop iff the cached mode
///     is ``live`` or ``paper``.  Called at boot from NavShell and
///     after every Auto-trade-settings Save (via ``refreshSettings``).
///   * ``stop()`` cancels the timer immediately — used when the user
///     flips mode to ``off`` or taps the kill-switch on the AUTO
///     banner.
///   * App lifecycle: pause on ``AppLifecycleState.paused``; resume
///     on ``resumed``.  Handled by NavShell which owns the
///     WidgetsBindingObserver.
///
/// Throttling: one new-signal firing per tick.  If a tick surfaces
/// multiple untaken ACTIVE signals (engine just woke from a quiet
/// stretch), we take the first by newest-first sort and let the next
/// tick handle the rest — keeps a burst from over-leveraging the
/// user in one batch.
library;

import 'dart:async';

import 'binance_client.dart';
import 'binance_keys_service.dart';
import 'mock_data.dart';
import 'order_executor.dart';
import 'order_log.dart';
import 'repository.dart';

class AutoTradeStatus {
  const AutoTradeStatus({
    required this.running,
    required this.mode,
    this.lastTickAt,
    this.lastError,
    this.lastFiredSignalId,
    this.lastFiredAt,
  });

  /// True when the poll loop is active.  Implies mode != off and
  /// (for live) keys present.
  final bool running;

  /// Cached user setting — ``off`` / ``paper`` / ``live`` / null
  /// (when nothing has been loaded yet).
  final String? mode;

  final DateTime? lastTickAt;
  final String? lastError;
  final String? lastFiredSignalId;
  final DateTime? lastFiredAt;

  AutoTradeStatus copyWith({
    bool? running,
    String? mode,
    DateTime? lastTickAt,
    String? lastError,
    String? lastFiredSignalId,
    DateTime? lastFiredAt,
    bool clearError = false,
    bool clearFired = false,
  }) {
    return AutoTradeStatus(
      running: running ?? this.running,
      mode: mode ?? this.mode,
      lastTickAt: lastTickAt ?? this.lastTickAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastFiredSignalId:
          clearFired ? null : (lastFiredSignalId ?? this.lastFiredSignalId),
      lastFiredAt: clearFired ? null : (lastFiredAt ?? this.lastFiredAt),
    );
  }
}

class AutoTradeWatcher {
  AutoTradeWatcher({
    required int? Function() getUserId,
    required LuminRepository Function() getRepo,
    Duration? interval,
    BinanceKeysService? keysService,
    OrderExecutor? executor,
    OrderLogService? logService,
  })  : _getUserId = getUserId,
        _getRepo = getRepo,
        _interval = interval ?? const Duration(seconds: 15),
        _keysService = keysService ?? BinanceKeysService(),
        _executor = executor ?? OrderExecutor(),
        _logService = logService ?? OrderLogService();

  final int? Function() _getUserId;
  final LuminRepository Function() _getRepo;
  final Duration _interval;
  final BinanceKeysService _keysService;
  final OrderExecutor _executor;
  final OrderLogService _logService;

  Timer? _timer;
  bool _tickInFlight = false;

  AutoTradeStatus _status = const AutoTradeStatus(running: false, mode: null);
  AutoTradeStatus get status => _status;

  final _statusController = StreamController<AutoTradeStatus>.broadcast();
  Stream<AutoTradeStatus> get statusStream => _statusController.stream;

  /// Start the loop if cached mode is live/paper.  Idempotent — safe
  /// to call from NavShell.initState every time.
  Future<void> ensureRunning() async {
    if (_timer != null) return;
    final settings = await _safeFetchSettings();
    final mode = settings?.mode;
    _setStatus(_status.copyWith(mode: mode));
    if (mode == 'live' || mode == 'paper') {
      _start();
    }
  }

  /// Called by the Auto-trade settings page after Save so the watcher
  /// picks up a fresh mode without waiting for its next tick.
  Future<void> refreshSettings() async {
    final settings = await _safeFetchSettings();
    final mode = settings?.mode;
    _setStatus(_status.copyWith(mode: mode, clearError: true));
    if (mode == 'off' || mode == null) {
      stop();
      return;
    }
    if (_timer == null) _start();
  }

  void _start() {
    _timer = Timer.periodic(_interval, (_) => _tick());
    _setStatus(_status.copyWith(running: true));
    // Fire one immediate tick so the user doesn't wait 15s for the
    // first action after enabling.
    unawaited(_tick());
  }

  /// Cancel the poll loop.  Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _setStatus(_status.copyWith(running: false));
  }

  void dispose() {
    stop();
    _statusController.close();
  }

  Future<void> _tick() async {
    if (_tickInFlight) return;
    _tickInFlight = true;
    try {
      final uid = _getUserId();
      if (uid == null) {
        _setStatus(_status.copyWith(
          running: false,
          lastError: 'Sign in with phone to enable auto-trade.',
        ));
        stop();
        return;
      }
      final settings = await _safeFetchSettings();
      final mode = settings?.mode;
      _setStatus(_status.copyWith(
        mode: mode,
        lastTickAt: DateTime.now(),
        clearError: true,
      ));
      if (settings == null || mode == null || mode == 'off') {
        stop();
        return;
      }
      if (mode == 'live') {
        final keys = await _keysService.load(uid);
        if (keys == null) {
          _setStatus(_status.copyWith(
            lastError:
                'Auto-trade is LIVE but Binance keys are missing.  Connect on Settings → API keys.',
          ));
          return;
        }
      }
      final signals = await _getRepo()
          .fetchSignals(status: 'all')
          .timeout(const Duration(seconds: 12));
      final active = signals.where((s) => s.status == 'ACTIVE').toList()
        // Newest first — smallest minutesAgo is newest.
        ..sort((a, b) => a.minutesAgo.compareTo(b.minutesAgo));

      // Pass 1 — new-entry firing.  Skip signals already in the log.
      for (final s in active) {
        final existing = await _logService.entryFor(uid, s.id);
        if (existing != null) continue;
        await _fireOne(uid, s, settings, mode);
        // Hard throttle: one entry-firing per tick.
        break;
      }

      // Pass 2 — per-user pre-TP partial close (Phase 4, live mode only).
      // Walk active signals where the engine reports preTpHit=true AND
      // this user has a logged entry whose pre-TP hasn't banked yet.
      // Paper mode skips — paper accounts don't move on Binance.
      //
      // Independent of pass 1 throttle: pre-TP is time-sensitive
      // (capital preservation requires banking the partial before the
      // edge evaporates), and one extra broker call per tick is well
      // inside any rate-limit envelope.
      if (mode == 'live') {
        for (final s in active) {
          if (!s.preTpHit) continue;
          final existing = await _logService.entryFor(uid, s.id);
          if (existing == null) continue;       // never entered
          if (existing.isPaper) continue;       // paper entry; no broker
          if (existing.preTpBanked) continue;   // already banked locally
          if (existing.entryOrderId == null) continue; // entry never filled
          await _firePreTp(uid, s, existing);
          // Hard throttle: one pre-TP per tick.
          break;
        }
      }
    } catch (e) {
      _setStatus(_status.copyWith(lastError: 'Watcher: $e'));
    } finally {
      _tickInFlight = false;
    }
  }

  /// Fire the per-user pre-TP partial close for a single signal whose
  /// engine state shows pre-TP hit.  Reads the user's
  /// ``PretpSettings.grabFraction`` at fire-time (so a slider change
  /// since entry is honored).  Live mode only — the caller guarantees
  /// mode == 'live' and the logged entry isn't paper.
  Future<void> _firePreTp(
    int uid,
    MockSignal signal,
    OrderLogEntry existing,
  ) async {
    final keys = await _keysService.load(uid);
    if (keys == null) {
      _setStatus(_status.copyWith(
        lastError: 'Pre-TP skipped — Binance keys missing on ${signal.symbol}.',
      ));
      return;
    }

    // Resolve the user's grab fraction.  Fallback to 0.50 (engine
    // default per OWNER_BRIEF B17) when the user hasn't set the slider
    // — matches the engine's own default-fallback logic in trade_monitor.
    double fraction = 0.50;
    try {
      final pretp = await _getRepo()
          .fetchUserPretpSettings()
          .timeout(const Duration(seconds: 8));
      if (pretp.grabFraction != null) fraction = pretp.grabFraction!;
    } catch (e) {
      // Fall through to default; capital preservation still applies.
      _setStatus(_status.copyWith(
        lastError: 'Pre-TP grab_fraction fetch failed for '
            '${signal.symbol}: $e — using engine default 50%.',
      ));
    }

    final result = await _executor.executePreTpPartial(
      userId: uid,
      logEntry: existing,
      keys: keys,
      grabFraction: fraction,
    );
    if (result.success && result.entry != null) {
      _setStatus(_status.copyWith(
        lastFiredSignalId: signal.id,
        lastFiredAt: DateTime.now(),
        clearError: true,
      ));
    } else {
      _setStatus(_status.copyWith(lastError: result.message));
    }
  }

  Future<void> _fireOne(
    int uid,
    MockSignal signal,
    AutoTradeSettings settings,
    String mode,
  ) async {
    if (mode == 'paper') {
      final result = await _executor.recordPaper(
        userId: uid,
        signal: signal,
        settings: settings,
        // Default simulated equity is 10k USDT.  Users see realistic
        // sizing without us querying Binance.  Phase 4 will let users
        // configure this.
        simulatedEquity: 10000.0,
      );
      if (result.success && result.entry != null) {
        _setStatus(_status.copyWith(
          lastFiredSignalId: signal.id,
          lastFiredAt: DateTime.now(),
        ));
      }
      return;
    }
    // mode == 'live'
    final keys = await _keysService.load(uid);
    if (keys == null) return;
    // Equity must come from /fapi/v2/account at fire-time — it moves
    // between ticks.  Cheap signed call.
    final client = BinanceClient(
      apiKey: keys.apiKey,
      apiSecret: keys.apiSecret,
      testnet: keys.testnet,
    );
    double equity = 0.0;
    int openCount = 0;
    try {
      final account = await client.getAccount();
      equity = account.totalWalletBalance;
      openCount = account.openPositionCount;
    } catch (e) {
      _setStatus(_status.copyWith(lastError: 'Auto-trade equity fetch: $e'));
      return;
    } finally {
      client.dispose();
    }
    // B12 per-user concurrent-position cap.  Engine PR #355 enforces
    // the engine-wide cap; this guard adds the per-user layer using
    // the openPositionCount we already paid for in getAccount.
    final cap = settings.maxConcurrentPositions ?? 999;
    if (openCount >= cap) {
      _setStatus(_status.copyWith(
        lastError:
            'Skipped — already at concurrent-position cap ($openCount / $cap).',
      ));
      return;
    }
    final result = await _executor.placeFromSignal(
      userId: uid,
      signal: signal,
      keys: keys,
      settings: settings,
      equity: equity,
      executionMode: 'auto-live',
    );
    if (result.success && result.entry != null) {
      _setStatus(_status.copyWith(
        lastFiredSignalId: signal.id,
        lastFiredAt: DateTime.now(),
        clearError: true,
      ));
    } else {
      _setStatus(_status.copyWith(lastError: result.message));
    }
  }

  Future<AutoTradeSettings?> _safeFetchSettings() async {
    try {
      return await _getRepo()
          .fetchUserAutoTradeSettings()
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  void _setStatus(AutoTradeStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }
}

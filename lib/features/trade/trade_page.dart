/// Trade — auto-execution control + open positions + activity log.
///
/// Phase 3c: when the user has Binance keys connected, this page shows
/// their real Binance positions (queried live from
/// ``GET /fapi/v2/positionRisk``) instead of the engine-wide paper
/// view.  Falls back to engine paper positions when no keys are
/// connected so the page still renders something useful.
///
/// The Off/Paper/Live mode toggle writes the **per-user** auto-trade
/// setting via ``repo.updateUserAutoTradeSettings`` (Phase 2 endpoint)
/// and kicks the AutoTradeWatcher (Phase 3b-2) to pick up the new
/// mode without waiting for its next tick.
import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/binance_client.dart';
import '../../data/binance_keys_service.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import '../../shared/widgets/preview_badge.dart';

class _TradeBundle {
  const _TradeBundle({
    required this.autoMode,
    required this.userSettings,
    required this.positions,
    required this.activity,
    this.binancePositions,
    this.binanceAccount,
    this.binanceError,
  });
  /// Engine-wide auto-mode (read by all tiers).  Drives the P&L card
  /// + open positions until Phase 4 ships per-user PnL.
  final AutoModeStatus autoMode;

  /// Per-user override (Phase 2).  Drives the mode pill selection +
  /// the AutoTradeWatcher (Phase 3b-2).  ``mode`` falls back to
  /// engine-wide via ``using_defaults`` if the user hasn't picked one.
  final AutoTradeSettings userSettings;

  /// Engine paper positions — only rendered when the user has not
  /// connected Binance keys.  Phase 3c prefers
  /// :attr:`binancePositions` when present.
  final List<MockPosition> positions;
  final List<MockActivityEvent> activity;

  /// User's real Binance positions (Phase 3c).  Null when the user
  /// hasn't connected keys or the fetch errored — caller falls back
  /// to ``positions`` (engine paper) in that case.
  final List<BinancePosition>? binancePositions;

  /// User's Binance account snapshot for the per-user P&L card.
  /// Same fetch as ``binancePositions``; null on the same conditions.
  final BinanceAccount? binanceAccount;

  /// Error string when the Binance fetch failed despite keys being
  /// present.  Surfaced as a small banner above the engine paper
  /// fallback so the user knows why they're not seeing their real
  /// positions.
  final String? binanceError;
}

class TradePage extends StatefulWidget {
  const TradePage({super.key});

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  late Future<_TradeBundle> _future;
  LuminRepository? _lastRepo;
  bool _switchingMode = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppConfigScope.of(context).repo;
    if (repo != _lastRepo) {
      _lastRepo = repo;
      _future = _load(repo);
    }
  }

  Future<_TradeBundle> _load(LuminRepository repo) async {
    final results = await Future.wait([
      repo.fetchAutoMode(),
      repo.fetchPositions(),
      repo.fetchActivity(limit: 30),
      repo.fetchUserAutoTradeSettings().catchError(
        // Anonymous device JWTs → 404.  Fall back to "no overrides"
        // so the page still renders; the mode pill follows engine
        // until the user signs in with phone.
        (_) => const AutoTradeSettings(usingDefaults: true),
      ),
    ]);
    final bundle = _TradeBundle(
      autoMode: results[0] as AutoModeStatus,
      positions: (results[1] as List).cast<MockPosition>(),
      activity: (results[2] as List).cast<MockActivityEvent>(),
      userSettings: results[3] as AutoTradeSettings,
    );
    // Phase 3c — query user's real Binance positions in parallel
    // when keys are connected.  Falls back to the engine paper view
    // silently on missing keys / mock mode / fetch failure.
    return _augmentWithBinance(bundle);
  }

  Future<_TradeBundle> _augmentWithBinance(_TradeBundle base) async {
    final uid = AppConfigScope.of(context).userId;
    if (uid == null) return base;
    final keys = await BinanceKeysService().load(uid);
    if (keys == null || !keys.isValid) return base;
    final client = BinanceClient(
      apiKey: keys.apiKey,
      apiSecret: keys.apiSecret,
      testnet: keys.testnet,
    );
    try {
      final results = await Future.wait([
        client.getAccount(),
        client.getOpenPositions(),
      ]);
      return _TradeBundle(
        autoMode: base.autoMode,
        userSettings: base.userSettings,
        positions: base.positions,
        activity: base.activity,
        binanceAccount: results[0] as BinanceAccount,
        binancePositions: results[1] as List<BinancePosition>,
      );
    } on BinanceError catch (e) {
      return _TradeBundle(
        autoMode: base.autoMode,
        userSettings: base.userSettings,
        positions: base.positions,
        activity: base.activity,
        binanceError: 'Binance: ${e.message} (code ${e.code ?? "?"})',
      );
    } catch (e) {
      return _TradeBundle(
        autoMode: base.autoMode,
        userSettings: base.userSettings,
        positions: base.positions,
        activity: base.activity,
        binanceError: 'Binance fetch: $e',
      );
    } finally {
      client.dispose();
    }
  }

  Future<void> _refresh() async {
    final repo = AppConfigScope.of(context).repo;
    setState(() => _future = _load(repo));
    await _future;
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
    final scope = AppConfigScope.of(context);
    final repo = scope.repo;
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
      // Kick the watcher so the new mode takes effect immediately.
      // Same pattern as the Auto-trade settings page.
      await scope.autoTradeWatcher.refreshSettings();
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
    final scope = AppConfigScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Trade')),
      body: RefreshIndicator(
        color: LuminColors.accent,
        onRefresh: _refresh,
        child: FutureBuilder<_TradeBundle>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const _TradeLoading();
            }
            if (snap.hasError) {
              return _TradeError(error: snap.error.toString(), onRetry: _refresh);
            }
            final data = snap.data!;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              children: [
                if (!scope.repo.isLive) const PreviewBadge(),
                _ModeToggle(
                  // Pill reflects the user's per-user mode (what the
                  // AutoTradeWatcher will act on).  Falls back to the
                  // engine-wide mode when the user has no override
                  // (usingDefaults == true).
                  mode: _modeIndex(
                    data.userSettings.mode ?? data.autoMode.mode,
                  ),
                  switching: _switchingMode,
                  onChanged: (i) => _changeMode(_modeName(i)),
                ),
                if (data.userSettings.mode != null &&
                    data.userSettings.mode != data.autoMode.mode)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LuminSpacing.lg,
                      vertical: LuminSpacing.xs,
                    ),
                    child: Text(
                      'Engine globally on ${data.autoMode.mode?.toUpperCase() ?? "—"}; '
                      'your auto-trade overrides to '
                      '${data.userSettings.mode!.toUpperCase()}.',
                      style: const TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                const SizedBox(height: LuminSpacing.md),
                _ModePnlCard(
                  autoMode: data.autoMode,
                  hasBinance: data.binancePositions != null,
                ),
                const SizedBox(height: LuminSpacing.md),
                // Phase 3c — prefer the user's real Binance positions
                // when they've connected keys; fall back to engine
                // paper when not connected or fetch errored.
                if (data.binancePositions != null)
                  _UserPositionsCard(
                    positions: data.binancePositions!,
                    account: data.binanceAccount,
                  )
                else ...[
                  if (data.binanceError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LuminSpacing.lg,
                        vertical: LuminSpacing.xs,
                      ),
                      child: Text(
                        data.binanceError!,
                        style: const TextStyle(
                          color: LuminColors.loss,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  _OpenPositionsCard(positions: data.positions),
                ],
                const SizedBox(height: LuminSpacing.md),
                _ActivityCard(events: data.activity),
                const SizedBox(height: LuminSpacing.xl),
              ],
            );
          },
        ),
      ),
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

  /// When true, the user has Binance keys connected and the
  /// :class:`_UserPositionsCard` below is showing their real
  /// positions.  This card still surfaces the engine's paper
  /// trader stats (Phase 4 ships per-user PnL) — we relabel
  /// to be honest about it.
  final bool hasBinance;

  @override
  Widget build(BuildContext context) {
    final mode = autoMode.mode;
    if (mode == 'off') {
      return _OffStateCard();
    }
    final isPaper = mode == 'paper';
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

/// User's real Binance positions (Phase 3c).  Rendered in place of
/// :class:`_OpenPositionsCard` when ``BinanceKeysService.load``
/// returned non-null on this load.  Falls back to the engine paper
/// view otherwise.
class _UserPositionsCard extends StatelessWidget {
  const _UserPositionsCard({
    required this.positions,
    required this.account,
  });

  final List<BinancePosition> positions;
  final BinanceAccount? account;

  @override
  Widget build(BuildContext context) {
    final totalUpnl = positions.fold<double>(
        0.0, (sum, p) => sum + p.unrealizedProfit);
    final positive = totalUpnl >= 0;
    final accent = positive ? LuminColors.success : LuminColors.loss;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    color: LuminColors.accent, size: 16),
                const SizedBox(width: LuminSpacing.xs),
                const Text(
                  'YOUR BINANCE POSITIONS',
                  style: TextStyle(
                    color: LuminColors.textMuted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (positions.isNotEmpty)
                  Text(
                    '${positive ? "+" : ""}\$${totalUpnl.toStringAsFixed(2)} uPnL',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            if (account != null) ...[
              const SizedBox(height: LuminSpacing.sm),
              _StatRow(
                label: 'Wallet equity',
                value: '\$${account!.totalWalletBalance.toStringAsFixed(2)}',
              ),
              _StatRow(
                label: 'Available',
                value: '\$${account!.availableBalance.toStringAsFixed(2)}',
              ),
            ],
            const SizedBox(height: LuminSpacing.md),
            if (positions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: LuminSpacing.lg),
                child: Center(
                  child: Text(
                    'No open positions on Binance.',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              for (int i = 0; i < positions.length; i++) ...[
                _UserPositionRow(p: positions[i]),
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

class _UserPositionRow extends StatelessWidget {
  const _UserPositionRow({required this.p});
  final BinancePosition p;

  @override
  Widget build(BuildContext context) {
    final positive = p.unrealizedProfit >= 0;
    final accent = positive ? LuminColors.success : LuminColors.loss;
    final isLong = p.isLong;
    final sideColor = isLong ? LuminColors.success : LuminColors.loss;
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
                color: sideColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
              ),
              child: Text(
                p.side,
                style: TextStyle(
                  color: sideColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: LuminSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LuminSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: LuminColors.textMuted.withOpacity(0.15),
                borderRadius: BorderRadius.circular(LuminRadii.sm),
              ),
              child: Text(
                '${p.leverage.toStringAsFixed(0)}x',
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Text(
              '${positive ? "+" : ""}\$${p.unrealizedProfit.toStringAsFixed(2)}',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: LuminSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                'Qty ${p.qty.toString()}',
                style: const TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
            Text(
              'Entry ${p.entryPrice.toStringAsFixed(4)}  →  '
              'Mark ${p.markPrice.toStringAsFixed(4)}',
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        if (p.liquidationPrice > 0) ...[
          const SizedBox(height: 2),
          Text(
            'Liq ${p.liquidationPrice.toStringAsFixed(4)}  •  ${p.marginType}',
            style: const TextStyle(
              color: LuminColors.loss,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: LuminColors.textPrimary,
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

class _TradeLoading extends StatelessWidget {
  const _TradeLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      children: const [
        SizedBox(height: LuminSpacing.xxl),
        Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: LuminColors.accent,
            ),
          ),
        ),
      ],
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

/// Take Trade (from a market alert) — entry-only order review sheet.
///
/// An alert is an observation, not a signal: it carries no SL/TP
/// geometry.  Explicit owner decision: "Take trade" places ONLY a
/// market entry on the user's own Binance account (same device-key
/// custody as Take Signal) — **no stop-loss and no take-profit are
/// placed**, and the sheet says so in an unmissable warning.  The user
/// owns the exit (Binance app or the Trade tab).
///
/// Side defaults from the alert's bias (BULLISH → LONG, BEARISH →
/// SHORT); NEUTRAL alerts (volume/volatility) make the user pick.
/// Sizing reuses the user's Auto-trade settings (position size % ×
/// leverage cap on live equity) so the numbers match every other
/// order path in the app.  Idempotent on the alert_id.
library;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/binance_client.dart';
import '../../data/binance_keys_service.dart';
import '../../data/market_alert.dart';
import '../../data/order_executor.dart';
import '../../data/order_log.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';

/// Show the entry-only Take Trade sheet for a market alert.  Returns
/// ``true`` when an order was placed.
Future<bool?> showTakeAlertTradeSheet(
  BuildContext context, {
  required MarketAlert alert,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: LuminColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
    ),
    builder: (_) => TakeAlertTradeSheet(alert: alert),
  );
}

class TakeAlertTradeSheet extends StatefulWidget {
  const TakeAlertTradeSheet({super.key, required this.alert});

  final MarketAlert alert;

  @override
  State<TakeAlertTradeSheet> createState() => _TakeAlertTradeSheetState();
}

class _TakeAlertTradeSheetState extends State<TakeAlertTradeSheet> {
  bool _loading = true;
  String? _loadError;

  BinanceKeys? _keys;
  AutoTradeSettings? _settings;
  double _equity = 0.0;
  double? _markPrice;
  OrderLogEntry? _alreadyTaken;

  /// LONG / SHORT — pre-seeded from the alert's bias, user-switchable.
  /// Null for NEUTRAL alerts until the user picks (Confirm stays off).
  String? _side;

  bool _placing = false;
  String? _placeResult;
  bool _placeSuccess = false;

  final _keysService = BinanceKeysService();
  final _logService = OrderLogService();
  final _executor = OrderExecutor();

  @override
  void initState() {
    super.initState();
    switch (widget.alert.bias) {
      case 'BULLISH':
        _side = 'LONG';
        break;
      case 'BEARISH':
        _side = 'SHORT';
        break;
      default:
        _side = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final scope = AppConfigScope.of(context);
    final uid = scope.userId;
    if (uid == null) {
      setState(() {
        _loading = false;
        _loadError = 'Sign in with phone first to take trades.';
      });
      return;
    }
    try {
      final keys = await _keysService.load(uid);
      if (keys == null) {
        setState(() {
          _loading = false;
          _loadError =
              'Connect your Binance keys on Settings → API keys first.';
        });
        return;
      }
      final settings = await scope.repo.fetchUserAutoTradeSettings();
      final taken =
          await _logService.entryFor(uid, 'alert-${widget.alert.alertId}');

      final client = BinanceClient(
        apiKey: keys.apiKey,
        apiSecret: keys.apiSecret,
        testnet: keys.testnet,
      );
      double equity = 0.0;
      double? mark;
      try {
        final results = await Future.wait([
          client.getAccount(),
          client.getMarkPrice(widget.alert.symbol),
        ]);
        equity = (results[0] as BinanceAccount).totalWalletBalance;
        mark = results[1] as double;
      } catch (_) {
        // Equity stays 0 → Confirm stays disabled; retry via reload.
      } finally {
        client.dispose();
      }

      if (!mounted) return;
      setState(() {
        _keys = keys;
        _settings = settings;
        _equity = equity;
        _markPrice = mark;
        _alreadyTaken = taken;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  /// Mirrors OrderExecutor's sizing so the preview shows the numbers
  /// the executor will use.
  ({double qty, int leverage, double notional})? get _preview {
    final s = _settings;
    final mark = _markPrice;
    if (s == null || mark == null || mark <= 0 || _equity <= 0) return null;
    final sizingPct = s.positionSizePct;
    final leverage = s.leverageCap;
    if (sizingPct == null || leverage == null) return null;
    final leverageCapped = leverage.clamp(1.0, 30.0);
    final notional = _equity * (sizingPct / 100.0) * leverageCapped;
    return (
      qty: notional / mark,
      leverage: leverageCapped.toInt(),
      notional: notional,
    );
  }

  Future<void> _confirm() async {
    final keys = _keys;
    final settings = _settings;
    final side = _side;
    final mark = _markPrice;
    final uid = AppConfigScope.of(context).userId;
    if (keys == null || settings == null || side == null || uid == null) {
      return;
    }
    setState(() {
      _placing = true;
      _placeResult = null;
    });
    final result = await _executor.placeAlertEntry(
      userId: uid,
      alertId: widget.alert.alertId,
      symbol: widget.alert.symbol,
      direction: side,
      keys: keys,
      settings: settings,
      equity: _equity,
      markPrice: mark ?? 0.0,
    );
    if (!mounted) return;
    setState(() {
      _placing = false;
      _placeResult = result.message;
      _placeSuccess = result.success;
      _alreadyTaken = result.entry ?? result.alreadyTaken;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: LuminSpacing.lg,
          right: LuminSpacing.lg,
          top: LuminSpacing.md,
          bottom: MediaQuery.of(context).viewInsets.bottom + LuminSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LuminColors.cardBorder,
                  borderRadius: BorderRadius.circular(LuminRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: LuminSpacing.md),
            _header(),
            const SizedBox(height: LuminSpacing.md),
            _body(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final a = widget.alert;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Take trade on ${a.symbol}',
          style: const TextStyle(
            color: LuminColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${a.title} (${a.timeframe}) — ${a.message}',
          style: const TextStyle(
            color: LuminColors.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(LuminSpacing.xl),
        child: Center(
          child: CircularProgressIndicator(color: LuminColors.accent),
        ),
      );
    }
    final loadError = _loadError;
    if (loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
        child: Text(
          loadError,
          style: const TextStyle(color: LuminColors.warn, fontSize: 13),
        ),
      );
    }
    final taken = _alreadyTaken;
    final result = _placeResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sideSelector(),
        const SizedBox(height: LuminSpacing.md),
        _previewBox(),
        const SizedBox(height: LuminSpacing.md),
        _noSlWarning(),
        if (result != null) ...[
          const SizedBox(height: LuminSpacing.md),
          Text(
            result,
            style: TextStyle(
              color: _placeSuccess ? LuminColors.success : LuminColors.warn,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: LuminSpacing.md),
        if (result == null || !_placeSuccess)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.accent,
              foregroundColor: LuminColors.bgDeep,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: (_placing ||
                    _side == null ||
                    _preview == null ||
                    (taken != null && result == null))
                ? null
                : _confirm,
            child: _placing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    taken != null && result == null
                        ? 'Already taken'
                        : 'Confirm entry — no SL / no TP',
                  ),
          )
        else
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.success,
              foregroundColor: LuminColors.bgDeep,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Done'),
          ),
      ],
    );
  }

  Widget _sideSelector() {
    final neutral = widget.alert.bias == 'NEUTRAL';
    return Row(
      children: [
        _sideChip('LONG', LuminColors.success),
        const SizedBox(width: LuminSpacing.sm),
        _sideChip('SHORT', LuminColors.loss),
        if (neutral && _side == null) ...[
          const SizedBox(width: LuminSpacing.sm),
          const Expanded(
            child: Text(
              'Pick a side',
              style: TextStyle(color: LuminColors.textMuted, fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sideChip(String side, Color color) {
    final selected = _side == side;
    return ChoiceChip(
      label: Text(
        side,
        style: TextStyle(
          color: selected ? color : LuminColors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      selected: selected,
      selectedColor: color.withOpacity(0.15),
      backgroundColor: LuminColors.bgElevated,
      onSelected: (_) => setState(() => _side = side),
    );
  }

  Widget _previewBox() {
    final p = _preview;
    final mark = _markPrice;
    if (p == null) {
      return const Text(
        'Set position size + leverage on the Auto-trade page first '
        '(and make sure your Binance balance loaded).',
        style: TextStyle(color: LuminColors.warn, fontSize: 12.5, height: 1.4),
      );
    }
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: LuminColors.cardBorder),
      ),
      child: Column(
        children: [
          _kv('Order', 'Market entry (${_side ?? "—"})'),
          _kv('Mark price', mark != null ? mark.toStringAsFixed(6) : '—'),
          _kv('Quantity', p.qty.toStringAsFixed(6)),
          _kv('Leverage', '${p.leverage}x'),
          _kv('Notional', '${p.notional.toStringAsFixed(2)} USDT'),
          _kv('Stop-loss', 'NONE'),
          _kv('Take-profit', 'NONE'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            k,
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            v,
            style: const TextStyle(
              color: LuminColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noSlWarning() {
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: LuminColors.loss.withOpacity(0.08),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: LuminColors.loss.withOpacity(0.45)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: LuminColors.loss, size: 18),
          SizedBox(width: LuminSpacing.sm),
          Expanded(
            child: Text(
              'Entry only. NO stop-loss and NO take-profit will be placed. '
              'This position is fully yours to manage and close — the app '
              'and engine will not protect or exit it for you.',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

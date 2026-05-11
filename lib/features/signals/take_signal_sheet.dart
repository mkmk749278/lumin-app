/// Take Signal — manual order-placement review sheet.
///
/// Phase 3b-1.  Composed from the signal + the user's per-user
/// auto-trade settings + their Binance equity.  Shows the resolved
/// order parameters (symbol, direction, qty, leverage, SL, TP) and
/// the testnet-vs-mainnet flag.  Confirm fires the entry+SL+TP
/// triplet via :class:`OrderExecutor`.
///
/// Idempotency: ``OrderExecutor.placeFromSignal`` short-circuits when
/// the signal_id is already in the user's order log (this PR's
/// :class:`OrderLogService`).  We also render an "Already taken"
/// state up-front when this sheet is opened on a previously-taken
/// signal so the user doesn't even reach Confirm.
library;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/binance_client.dart';
import '../../data/binance_keys_service.dart';
import '../../data/mock_data.dart';
import '../../data/order_executor.dart';
import '../../data/order_log.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';

/// Show the Take Signal review sheet.  Returns ``true`` when an order
/// was placed (caller can refresh the signals list); ``null`` when
/// the user cancelled or the sheet was dismissed.
Future<bool?> showTakeSignalSheet(
  BuildContext context, {
  required MockSignal signal,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: LuminColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
    ),
    builder: (_) => TakeSignalSheet(signal: signal),
  );
}

class TakeSignalSheet extends StatefulWidget {
  const TakeSignalSheet({super.key, required this.signal});

  final MockSignal signal;

  @override
  State<TakeSignalSheet> createState() => _TakeSignalSheetState();
}

class _TakeSignalSheetState extends State<TakeSignalSheet> {
  bool _loading = true;
  String? _loadError;

  BinanceKeys? _keys;
  AutoTradeSettings? _settings;
  double _equity = 0.0;
  OrderLogEntry? _alreadyTaken;
  double? _markPrice;

  bool _placing = false;
  String? _placeResult;
  bool _placeSuccess = false;

  final _keysService = BinanceKeysService();
  final _logService = OrderLogService();
  final _executor = OrderExecutor();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final scope = AppConfigScope.of(context);
    final uid = scope.userId;
    if (uid == null) {
      setState(() {
        _loading = false;
        _loadError = 'Sign in with phone first to take signals.';
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
      final taken = await _logService.entryFor(uid, widget.signal.id);

      // Pull equity + mark price in parallel.  Failures here are
      // non-fatal — we surface them inline but don't block the sheet.
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
          client.getMarkPrice(widget.signal.symbol),
        ]);
        equity = (results[0] as BinanceAccount).totalWalletBalance;
        mark = results[1] as double;
      } catch (_) {
        // Equity stays 0 → Confirm button stays disabled until the
        // user retries (load button below).
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

  /// Resolved order params for display, computed locally.  Mirrors
  /// the math in :class:`OrderExecutor` so the user sees the same
  /// numbers the executor will use.  Returns null if any input is
  /// missing.
  _OrderPreview? get _preview {
    final s = _settings;
    if (s == null) return null;
    final sizingPct = s.positionSizePct;
    final leverage = s.leverageCap;
    if (sizingPct == null || leverage == null) return null;
    if (_equity <= 0) return null;
    final leverageCapped = leverage.clamp(1.0, 30.0);
    final notional = _equity * (sizingPct / 100.0) * leverageCapped;
    final qty = notional / widget.signal.entry;
    return _OrderPreview(
      qty: qty,
      leverage: leverageCapped.toInt(),
      notional: notional,
      sizingPct: sizingPct,
    );
  }

  Future<void> _confirm() async {
    final keys = _keys;
    final settings = _settings;
    final scope = AppConfigScope.of(context);
    final uid = scope.userId;
    if (keys == null || settings == null || uid == null) return;
    setState(() {
      _placing = true;
      _placeResult = null;
    });
    final result = await _executor.placeFromSignal(
      userId: uid,
      signal: widget.signal,
      keys: keys,
      settings: settings,
      equity: _equity,
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
            _grabber(),
            const SizedBox(height: LuminSpacing.md),
            _header(),
            const SizedBox(height: LuminSpacing.md),
            _body(),
            const SizedBox(height: LuminSpacing.md),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _grabber() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: LuminColors.cardBorder,
            borderRadius: BorderRadius.circular(LuminRadii.pill),
          ),
        ),
      );

  Widget _header() {
    final s = widget.signal;
    final isLong = s.direction == 'LONG';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Take ${s.direction} on ${s.symbol}',
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${s.agentName} • ${s.setupName}',
                style: const TextStyle(
                  color: LuminColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (isLong ? LuminColors.success : LuminColors.loss)
                .withOpacity(0.15),
            borderRadius: BorderRadius.circular(LuminRadii.sm),
          ),
          child: Text(
            s.direction,
            style: TextStyle(
              color: isLong ? LuminColors.success : LuminColors.loss,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: LuminSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return _errorCard(_loadError!);
    }
    if (_alreadyTaken != null && _placeResult == null) {
      return _alreadyTakenCard(_alreadyTaken!);
    }
    return Column(
      children: [
        _envCard(),
        const SizedBox(height: LuminSpacing.md),
        _signalSummary(),
        const SizedBox(height: LuminSpacing.md),
        _orderPreview(),
        if (_placeResult != null) ...[
          const SizedBox(height: LuminSpacing.md),
          _resultBanner(_placeResult!, _placeSuccess),
        ],
      ],
    );
  }

  Widget _errorCard(String msg) {
    return LuminCard(
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: LuminColors.loss, size: 18),
          const SizedBox(width: LuminSpacing.md),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alreadyTakenCard(OrderLogEntry e) {
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: LuminColors.success, size: 16),
              SizedBox(width: 6),
              Text(
                'Already taken',
                style: TextStyle(
                  color: LuminColors.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: LuminSpacing.sm),
          _kv('Order ID', '${e.entryOrderId ?? "—"}'),
          _kv('Quantity', e.quantity.toString()),
          if (e.avgFillPrice != null)
            _kv('Avg fill', formatPrice(e.avgFillPrice!)),
          _kv('Placed', _ageFromNow(e.placedAt)),
          if (e.testnet) _kv('Env', 'TESTNET'),
        ],
      ),
    );
  }

  Widget _envCard() {
    final testnet = _keys?.testnet ?? false;
    final colour = testnet ? LuminColors.warn : LuminColors.loss;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.md,
        vertical: LuminSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.10),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: colour.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Icon(
            testnet ? Icons.science_outlined : Icons.warning_amber_rounded,
            color: colour,
            size: 16,
          ),
          const SizedBox(width: LuminSpacing.sm),
          Text(
            testnet ? 'TESTNET — fake balance, real APIs' : 'MAINNET — real money',
            style: TextStyle(
              color: colour,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _signalSummary() {
    final s = widget.signal;
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SIGNAL',
            style: TextStyle(
              color: LuminColors.textMuted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          _kv('Entry', formatPrice(s.entry)),
          if (_markPrice != null) _kv('Mark now', formatPrice(_markPrice!)),
          _kv('Stop-Loss', formatPrice(s.sl)),
          _kv('TP1', formatPrice(s.tp1)),
        ],
      ),
    );
  }

  Widget _orderPreview() {
    final p = _preview;
    return LuminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ORDER',
            style: TextStyle(
              color: LuminColors.textMuted,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LuminSpacing.sm),
          _kv('Wallet equity', '\$${_equity.toStringAsFixed(2)}'),
          if (p != null) ...[
            _kv('Position size', '${p.sizingPct.toStringAsFixed(2)}%'),
            _kv('Leverage', '${p.leverage}x'),
            _kv(
              'Notional',
              '\$${p.notional.toStringAsFixed(2)}',
            ),
            _kv('Quantity', p.qty.toStringAsFixed(6)),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: LuminSpacing.xs),
              child: Text(
                'Set position size + leverage on the Auto-trade page first.',
                style: TextStyle(
                  color: LuminColors.warn,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultBanner(String msg, bool ok) {
    final colour = ok ? LuminColors.success : LuminColors.loss;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: LuminSpacing.md,
        vertical: LuminSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.10),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: colour.withOpacity(0.30)),
      ),
      child: Text(
        msg,
        style: TextStyle(color: colour, fontSize: 12, height: 1.4),
      ),
    );
  }

  Widget _actions() {
    final canPlace = !_loading &&
        _loadError == null &&
        _alreadyTaken == null &&
        _preview != null &&
        !_placing &&
        _placeResult == null;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _placing ? null : () => Navigator.of(context).pop(_placeSuccess),
            child: Text(_placeResult != null ? 'Close' : 'Cancel'),
          ),
        ),
        const SizedBox(width: LuminSpacing.md),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LuminColors.accent,
              foregroundColor: LuminColors.bgDeep,
              disabledBackgroundColor: LuminColors.textMuted,
            ),
            onPressed: canPlace ? _confirm : null,
            child: _placing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: LuminColors.bgDeep,
                    ),
                  )
                : const Text(
                    'Confirm',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                color: LuminColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            v,
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

  static String _ageFromNow(DateTime t) {
    final delta = DateTime.now().toUtc().difference(t.toUtc());
    if (delta.inMinutes < 1) return '${delta.inSeconds}s ago';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}

class _OrderPreview {
  const _OrderPreview({
    required this.qty,
    required this.leverage,
    required this.notional,
    required this.sizingPct,
  });
  final double qty;
  final int leverage;
  final double notional;
  final double sizingPct;
}

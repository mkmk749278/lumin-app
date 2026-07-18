/// Manual trade builder sheet — server-side (2026-07-18,
/// `docs/MANUAL_TRADE_BUILDER_DESIGN.md` in the engine repo).
///
/// The user builds a trade against the live price: MARKET entry or a LIMIT at
/// a chosen entry price, with OPTIONAL stop-loss / take-profit. The ENGINE
/// places it on their server-connected key (stable VPS IP), so it works on
/// mobile networks where the old client-side alert take (device key, IP
/// whitelist) could not. SL is not compulsory for a manual take — the user
/// owns the exit (they can set/adjust it here or later).
///
/// Launchable from an alert, a signal, or the chart — the caller passes the
/// symbol, a stable `refId` (idempotency key), the current price (sizing +
/// entry seed), and an optional bias to pre-seed the side.
library;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/server_side_execution_models.dart';
import '../../shared/tokens.dart';

/// Show the server-side manual trade builder. Returns `true` when a trade was
/// placed (or is resting), so the caller can refresh the Trade tab.
Future<bool?> showManualTradeSheet(
  BuildContext context, {
  required String symbol,
  required String refId,
  required double currentPrice,
  String? bias, // 'BULLISH' | 'BEARISH' | 'NEUTRAL' → seeds the side
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: LuminColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
    ),
    builder: (_) => ManualTradeSheet(
      symbol: symbol, refId: refId, currentPrice: currentPrice, bias: bias,
    ),
  );
}

class ManualTradeSheet extends StatefulWidget {
  const ManualTradeSheet({
    super.key,
    required this.symbol,
    required this.refId,
    required this.currentPrice,
    this.bias,
  });

  final String symbol;
  final String refId;
  final double currentPrice;
  final String? bias;

  @override
  State<ManualTradeSheet> createState() => _ManualTradeSheetState();
}

class _ManualTradeSheetState extends State<ManualTradeSheet> {
  String _entryType = 'market'; // 'market' | 'limit'
  String? _side; // 'LONG' | 'SHORT'
  final _entryCtl = TextEditingController();
  final _slCtl = TextEditingController();
  final _tpCtl = TextEditingController();
  final _ttlCtl = TextEditingController(text: '15');

  bool _placing = false;
  ManualTradeResult? _result;

  @override
  void initState() {
    super.initState();
    switch (widget.bias) {
      case 'BULLISH':
        _side = 'LONG';
        break;
      case 'BEARISH':
        _side = 'SHORT';
        break;
      default:
        _side = null;
    }
    if (widget.currentPrice > 0) {
      _entryCtl.text = _fmt(widget.currentPrice);
    }
  }

  @override
  void dispose() {
    _entryCtl.dispose();
    _slCtl.dispose();
    _tpCtl.dispose();
    _ttlCtl.dispose();
    super.dispose();
  }

  String _fmt(double v) => v >= 100 ? v.toStringAsFixed(2) : v.toStringAsFixed(6);

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0.0;

  bool get _canConfirm {
    if (_side == null || _placing) return false;
    if (_entryType == 'limit' && _parse(_entryCtl) <= 0) return false;
    if (_entryType == 'market' && widget.currentPrice <= 0 && _parse(_entryCtl) <= 0) {
      return false;
    }
    return true;
  }

  Future<void> _confirm() async {
    final side = _side;
    if (side == null) return;
    setState(() {
      _placing = true;
      _result = null;
    });
    final repo = AppConfigScope.of(context).repo;
    final entryPrice = _entryType == 'limit'
        ? _parse(_entryCtl)
        : (widget.currentPrice > 0 ? widget.currentPrice : _parse(_entryCtl));
    final tp = _parse(_tpCtl);
    ManualTradeResult res;
    try {
      res = await repo.placeManualTrade(ManualTradeRequest(
        refId: widget.refId,
        symbol: widget.symbol,
        direction: side,
        entryType: _entryType,
        entryPrice: entryPrice,
        slPrice: _parse(_slCtl),
        tpPrices: tp > 0 ? [tp] : const [],
        validForMinutes:
            _entryType == 'limit' ? (int.tryParse(_ttlCtl.text.trim()) ?? 15) : 0,
      ));
    } catch (e) {
      res = ManualTradeResult(
        outcome: 'rejected', refId: widget.refId, rejectDetail: '$e',
      );
    }
    if (!mounted) return;
    setState(() {
      _placing = false;
      _result = res;
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
        child: SingleChildScrollView(
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
              Text(
                'Trade ${widget.symbol}',
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.currentPrice > 0
                    ? 'Live price ${_fmt(widget.currentPrice)} · placed server-side on your connected key'
                    : 'Placed server-side on your connected key',
                style: const TextStyle(
                  color: LuminColors.textSecondary, fontSize: 12, height: 1.35,
                ),
              ),
              const SizedBox(height: LuminSpacing.md),
              _sideSelector(),
              const SizedBox(height: LuminSpacing.md),
              _entryTypeSelector(),
              const SizedBox(height: LuminSpacing.sm),
              if (_entryType == 'limit')
                _field(_entryCtl, 'Entry price (limit)')
              else
                _readonlyField(
                  'Entry',
                  widget.currentPrice > 0
                      ? 'Market (~${_fmt(widget.currentPrice)})'
                      : 'Market',
                ),
              _field(_slCtl, 'Stop-loss (optional)'),
              _field(_tpCtl, 'Take-profit (optional)'),
              if (_entryType == 'limit')
                _field(_ttlCtl, 'Valid for (minutes)', number: false),
              const SizedBox(height: LuminSpacing.sm),
              _noSlHint(),
              if (_result != null) ...[
                const SizedBox(height: LuminSpacing.md),
                _resultBox(_result!),
              ],
              const SizedBox(height: LuminSpacing.md),
              _confirmButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sideSelector() {
    final neutral = widget.bias == 'NEUTRAL' || widget.bias == null;
    return Row(
      children: [
        _chip('LONG', _side == 'LONG', LuminColors.success,
            () => setState(() => _side = 'LONG')),
        const SizedBox(width: LuminSpacing.sm),
        _chip('SHORT', _side == 'SHORT', LuminColors.loss,
            () => setState(() => _side = 'SHORT')),
        if (neutral && _side == null) ...[
          const SizedBox(width: LuminSpacing.sm),
          const Expanded(
            child: Text('Pick a side',
                style: TextStyle(color: LuminColors.textMuted, fontSize: 11)),
          ),
        ],
      ],
    );
  }

  Widget _entryTypeSelector() {
    return Row(
      children: [
        _chip('MARKET', _entryType == 'market', LuminColors.accent,
            () => setState(() => _entryType = 'market')),
        const SizedBox(width: LuminSpacing.sm),
        _chip('LIMIT', _entryType == 'limit', LuminColors.accent, () {
          setState(() {
            _entryType = 'limit';
            if (_entryCtl.text.trim().isEmpty && widget.currentPrice > 0) {
              _entryCtl.text = _fmt(widget.currentPrice);
            }
          });
        }),
      ],
    );
  }

  Widget _chip(String label, bool selected, Color color, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? color : LuminColors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      selected: selected,
      selectedColor: color.withOpacity(0.15),
      backgroundColor: LuminColors.bgElevated,
      onSelected: (_) => onTap(),
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = true}) {
    return Padding(
      padding: const EdgeInsets.only(top: LuminSpacing.sm),
      child: TextField(
        controller: c,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.number,
        style: const TextStyle(color: LuminColors.textPrimary, fontSize: 14),
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              const TextStyle(color: LuminColors.textSecondary, fontSize: 12),
          filled: true,
          fillColor: LuminColors.bgElevated,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(LuminRadii.sm),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _readonlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: LuminSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(LuminSpacing.md),
        decoration: BoxDecoration(
          color: LuminColors.bgElevated,
          borderRadius: BorderRadius.circular(LuminRadii.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: LuminColors.textSecondary, fontSize: 12)),
            Text(value,
                style: const TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _noSlHint() {
    if (_parse(_slCtl) > 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.sm),
      decoration: BoxDecoration(
        color: LuminColors.loss.withOpacity(0.08),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: LuminColors.loss.withOpacity(0.35)),
      ),
      child: const Text(
        'No stop-loss set — this position is yours to manage and close. '
        'You can add a stop here or later from the chart.',
        style: TextStyle(color: LuminColors.textPrimary, fontSize: 11.5, height: 1.35),
      ),
    );
  }

  Widget _resultBox(ManualTradeResult r) {
    final ok = r.placed || r.queued;
    final String msg;
    if (r.placed) {
      msg = r.resting
          ? 'Limit order resting on Binance — it will fill when price reaches your entry.'
          : 'Order placed on Binance.';
    } else if (r.queued) {
      msg = r.detail ?? 'Working — the result will appear in Recent Activity.';
    } else {
      msg = r.rejectDetail ?? r.rejectClass ?? 'Trade rejected.';
    }
    return Container(
      padding: const EdgeInsets.all(LuminSpacing.md),
      decoration: BoxDecoration(
        color: (ok ? LuminColors.success : LuminColors.loss).withOpacity(0.10),
        borderRadius: BorderRadius.circular(LuminRadii.sm),
      ),
      child: Text(
        msg,
        style: TextStyle(
          color: ok ? LuminColors.success : LuminColors.loss,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _confirmButton() {
    final placed = _result?.placed == true || _result?.queued == true;
    if (placed) {
      return FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: LuminColors.success,
          foregroundColor: LuminColors.bgDeep,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Done'),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: LuminColors.accent,
        foregroundColor: LuminColors.bgDeep,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: _canConfirm ? _confirm : null,
      child: _placing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(_parse(_slCtl) > 0 ? 'Confirm trade' : 'Confirm — no stop-loss'),
    );
  }
}

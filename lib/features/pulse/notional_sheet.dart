/// "What would this book have done at MY size?"
///
/// Asked for by the owner (2026-08-11: *"give user to enter his own notional
/// number"*), and it is an honest question with an exact answer rather than a
/// model: the engine sizes every signal at a fixed notional, so a percentage
/// move on a fixed size is exactly linear in the amount.
///
/// **The app does not do that multiplication.** The number goes to
/// `/api/track-record?amount=` and the engine returns the priced book, echoing
/// `amount_usdt` so every rendered figure is labelled with the size the engine
/// actually used. A card scaling figures itself is one refactor away from
/// disagreeing with the endpoint it claims to be showing — and this repo's
/// standing rule is that the engine is the source of truth for anything
/// money-adjacent the UI renders.
///
/// It is a **notional**, not margin and not an account balance. That word is
/// on screen, because "500" meaning position size and "500" meaning what is in
/// your account differ by whatever leverage the reader assumes, and a figure
/// they mis-set is a figure they will mis-read for as long as it is stored.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/track_record_prefs.dart';
import '../../shared/tokens.dart';

/// Opens the editor. Returns true when the stored size changed.
Future<bool> showNotionalSheet(BuildContext context) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _NotionalSheet(),
  );
  return changed ?? false;
}

class _NotionalSheet extends StatefulWidget {
  const _NotionalSheet();

  @override
  State<_NotionalSheet> createState() => _NotionalSheetState();
}

class _NotionalSheetState extends State<_NotionalSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: _initial(),
  );
  String? _error;

  static String _initial() {
    final a = TrackRecordPrefs.instance.amountOrNull;
    if (a == null) return '';
    return a == a.roundToDouble() ? a.toStringAsFixed(0) : a.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      // Empty means "whatever the engine assumes" — a distinct state from
      // typing 100, and the only way back to it.
      await TrackRecordPrefs.instance.clear();
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    final value = double.tryParse(raw);
    if (value == null) {
      setState(() => _error = 'Enter a number.');
      return;
    }
    final ok = await TrackRecordPrefs.instance.setAmount(value);
    if (!ok) {
      setState(() => _error =
          'Between ${TrackRecordPrefs.minAmount.toStringAsFixed(0)} and '
          '${TrackRecordPrefs.maxAmount.toStringAsFixed(0)} USDT.');
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: LuminColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
          border: Border(top: BorderSide(color: LuminColors.cardBorder)),
        ),
        padding: const EdgeInsets.all(LuminSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Size per signal',
              style: TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'The track record is priced by taking every delivered signal at '
              'the same size. Set yours and every figure re-prices.',
              style: TextStyle(
                  color: LuminColors.textSecondary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: LuminSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText:
                    TrackRecordPrefs.defaultAmount.toStringAsFixed(0),
                hintStyle: const TextStyle(color: LuminColors.textMuted),
                suffixText: 'USDT',
                suffixStyle: const TextStyle(
                    color: LuminColors.textSecondary, fontSize: 13),
                errorText: _error,
                filled: true,
                fillColor: LuminColors.bgElevated,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LuminRadii.md),
                  borderSide: const BorderSide(color: LuminColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LuminRadii.md),
                  borderSide: const BorderSide(color: LuminColors.cardBorder),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: LuminSpacing.md),
            Wrap(
              spacing: LuminSpacing.sm,
              children: [
                for (final preset in const [50.0, 100.0, 250.0, 500.0, 1000.0])
                  _Preset(
                    amount: preset,
                    onTap: () {
                      _controller.text = preset.toStringAsFixed(0);
                      setState(() => _error = null);
                    },
                  ),
              ],
            ),
            const SizedBox(height: LuminSpacing.lg),
            const Text(
              // Said plainly, because "500" meaning position size and "500"
              // meaning account balance differ by whatever leverage the reader
              // assumes — and a figure they mis-set is one they will mis-read
              // for as long as it is stored.
              'This is the position NOTIONAL, the same thing the engine means '
              'by size — not your margin and not your account balance. It '
              'changes nothing about how signals are generated or traded; it '
              'only re-prices the record you are reading. Leave it blank to '
              'use the default.',
              style: TextStyle(
                  color: LuminColors.textMuted, fontSize: 10.5, height: 1.45),
            ),
            const SizedBox(height: LuminSpacing.lg),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel',
                      style: TextStyle(color: LuminColors.textSecondary)),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: LuminColors.accent,
                    foregroundColor: LuminColors.bgDeep,
                  ),
                  child: const Text('Apply',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({required this.amount, required this.onTap});

  final double amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LuminRadii.pill),
            border: Border.all(color: LuminColors.cardBorder),
          ),
          child: Text(
            amount.toStringAsFixed(0),
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

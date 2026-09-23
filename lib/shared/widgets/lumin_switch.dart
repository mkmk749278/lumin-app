/// The app's one switch: Material's [Switch] plus a toggle haptic.
///
/// Every settings toggle in Lumin changes how real orders are handled
/// (pre-TP, invalidation, auto-trade, notifications), and until 2026-09-23
/// flipping one gave no physical feedback at all. Routing all of them
/// through this widget means a switch added later gets the same feel
/// without anyone remembering to wire it — `test/shared/haptics_test.dart`
/// fails the build if a raw `Switch(` appears anywhere else in `lib/`.
library;

import 'package:flutter/material.dart';

import '../haptics.dart';

class LuminSwitch extends StatelessWidget {
  const LuminSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.materialTapTargetSize,
  });

  final bool value;

  /// Null disables the switch, exactly as with [Switch].
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final MaterialTapTargetSize? materialTapTargetSize;

  @override
  Widget build(BuildContext context) {
    final cb = onChanged;
    return Switch(
      value: value,
      activeColor: activeColor,
      materialTapTargetSize: materialTapTargetSize,
      onChanged: cb == null
          ? null
          : (v) {
              LuminHaptics.toggle();
              cb(v);
            },
    );
  }
}

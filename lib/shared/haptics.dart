/// Haptic vocabulary for Lumin — one name per *kind* of moment, so the
/// same gesture feels the same wherever it happens.
///
/// Added 2026-09-23. Until then the app used no haptics at all
/// (`HapticFeedback`: 0 call sites), so taking a trade, flipping an
/// auto-trade switch or switching tabs felt inert on Android — the
/// moments that commit a user's money had no physical confirmation.
///
/// Keep the set small and semantic. A call site picks the MEANING
/// (`commit`, `success`, `failure`), never an intensity, so the mapping to
/// platform impacts can be tuned here once. Web and platforms without a
/// vibration motor treat every call as a no-op, and a haptic must never
/// block or fail the action it accompanies — hence fire-and-forget.
library;

import 'package:flutter/services.dart';

abstract final class LuminHaptics {
  /// Moving between peers: a tab, a filter chip, a segmented control.
  static void selection() => _fire(HapticFeedback.selectionClick);

  /// Changing a setting: a switch or checkbox flipping state.
  static void toggle() => _fire(HapticFeedback.lightImpact);

  /// The user commits to something with consequences — confirming an
  /// order. Fired on the press, before the network round trip, so the
  /// confirmation is felt even if the result takes a second.
  static void commit() => _fire(HapticFeedback.mediumImpact);

  /// The committed action landed.
  static void success() => _fire(HapticFeedback.lightImpact);

  /// The committed action was refused or failed. Heavier than success so
  /// the two cannot be confused without looking.
  static void failure() => _fire(HapticFeedback.heavyImpact);

  static void _fire(Future<void> Function() impact) {
    // A haptic is decoration on an action, never part of it.
    impact().catchError((Object _) {});
  }
}

/// The position size the track record is priced at — the reader's own number.
///
/// The engine sizes every signal at a fixed notional, so a percentage move on a
/// fixed size is exactly linear in the amount. That is what makes "what would
/// this book have done at MY size" an honest question with an exact answer
/// rather than a model — and why the owner asked for it (2026-08-11).
///
/// **The arithmetic still happens engine-side.** This stores the number and
/// passes it to `/api/track-record`; it never multiplies anything itself. The
/// engine is the source of truth for anything money-adjacent the UI renders,
/// and a card doing its own scaling is one refactor away from disagreeing with
/// the endpoint it claims to be showing.
///
/// One value, app-wide, persisted. Two surfaces read it — the Pulse cards and
/// the track record page — and a size that meant different things on two
/// screens would be worse than no control at all.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrackRecordPrefs {
  TrackRecordPrefs._();

  static final TrackRecordPrefs instance = TrackRecordPrefs._();

  static const _key = 'lumin.trackRecord.amountUsdt';

  /// What the engine assumes when we send nothing. Kept in sync with
  /// `TRACK_RECORD_DEFAULT_AMOUNT_USDT` by [amountOrNull] returning null
  /// rather than by this constant being authoritative — see below.
  static const defaultAmount = 100.0;

  /// Bounds on what a reader may type.
  ///
  /// The engine clamps too (`0..1_000_000`), which is what actually protects
  /// it; these exist so the input can refuse before a round trip and say why.
  /// A size of zero would render a book of `+$0.00` and read as "the signals
  /// made nothing".
  static const minAmount = 1.0;
  static const maxAmount = 1000000.0;

  /// The current size. Null until [load] has run, which is what lets the first
  /// fetch send **no** `amount` at all and inherit the engine's default —
  /// rather than this file asserting a default the engine might have changed.
  final ValueNotifier<double?> amount = ValueNotifier<double?>(null);

  /// What to send to the endpoint: the reader's number, or null for "yours".
  double? get amountOrNull => amount.value;

  /// The number to show. Falls back to the engine's own default only for
  /// display; every payload also carries `amount_usdt`, so a rendered figure is
  /// always labelled with the size the ENGINE used, never with this.
  double get amountForDisplay => amount.value ?? defaultAmount;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(_key);
      if (stored != null && stored >= minAmount && stored <= maxAmount) {
        amount.value = stored;
      }
    } catch (_) {
      // A preferences read must never block the app. Unset means "the engine's
      // default", which is a correct book rather than a broken one.
    }
  }

  /// Store a new size. Returns false when the value is out of bounds, so the
  /// caller can say why rather than silently clamping to something the reader
  /// did not type.
  Future<bool> setAmount(double value) async {
    if (!value.isFinite || value < minAmount || value > maxAmount) return false;
    amount.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, value);
    } catch (_) {
      // In-memory value still applies for this session; the next launch falls
      // back to the engine default, which is honest rather than wrong.
    }
    return true;
  }

  /// Back to the engine's default — distinct from typing 100, because it means
  /// "whatever the engine assumes" rather than "one hundred".
  Future<void> clear() async {
    amount.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Same reasoning as above.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    amount.value = null;
  }
}

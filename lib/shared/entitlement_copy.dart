/// What is free and what is paid, in one place (2026-11-26).
///
/// The Trade tab said "Signals stay free", the web paywall said "Signals,
/// levels & charts are free", and the subscription page said live signals
/// need a plan after three free days. Only the last is true (owner,
/// 2026-09-25). Every screen that states entitlements reads these.
library;

class EntitlementCopy {
  EntitlementCopy._();

  static const String free = 'Closed signals and their results are free.';
  static const String live =
      'Live signals need the Signals plan after 3 free days.';

  /// Both halves, for a screen that states the rule once.
  static const String summary = '$free $live';

  static const String newAccount =
      'New accounts get 3 days of live signals free.';
}

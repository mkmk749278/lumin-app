/// Engine vocabulary → the words a subscriber actually reads.
///
/// Why this exists (handoff §9/§10, 2026-09-21): the signal card rendered the
/// engine's own identifiers straight at the reader — a status of
/// `BREAKEVEN_EXIT`, a setup of `FAILED AUCTION RECLAIM`. Both are exact, both
/// are internal, and neither is English. The card is the app's core screen and
/// the handoff's target is that a signal reads in about two seconds.
///
/// **Every lookup here falls back to the engine's own string rather than to a
/// blank or a guess.** A hand-kept map is silent by construction on the next
/// member — this repo has paid for that under several names — and the engine
/// adds setups and statuses without asking the app. So an unmapped value is
/// tidied into sentence case and shown, never swallowed: the reader sees
/// something imperfect instead of nothing, and a new engine value is visible
/// rather than absent.
library;

import '../agents/agent_data.dart';

/// Human wording for a signal's lifecycle status.
///
/// The raw values are the engine's `status` strings. Anything unrecognised is
/// de-underscored and sentence-cased, so a status shipped by a newer engine
/// still reads as words.
String signalStatusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'ACTIVE':
      return 'Active';
    case 'TP1_HIT':
      return 'Target 1 hit';
    case 'TP2_HIT':
      return 'Target 2 hit';
    case 'TP3_HIT':
      return 'Target 3 hit';
    case 'FULL_TP_HIT':
      return 'All targets hit';
    case 'SL_HIT':
      return 'Stopped out';
    case 'BREAKEVEN_EXIT':
      return 'Closed at breakeven';
    case 'INVALIDATED':
      return 'Setup invalidated';
    case 'EXPIRED':
      return 'Expired';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return _sentenceCase(status);
  }
}

/// The one-line plain-English description of a setup, or null when we have
/// none for it.
///
/// **Sourced from [kAgents] rather than from a second list.** Those taglines
/// were written for the Agents page and are the same sentence a reader needs
/// beside a branded strategy name — duplicating them here would be a mirror
/// that drifts, which is the defect this codebase records most often.
///
/// Returns null rather than a placeholder when the setup is not one of the
/// described ones: the card then shows the strategy name alone, which is
/// honest, instead of an invented description.
String? setupTagline(String setupName) {
  if (setupName.trim().isEmpty) return null;
  final id = setupName.trim().toUpperCase().replaceAll(' ', '_');
  for (final a in kAgents) {
    if (a.id == id) return a.tagline;
  }
  return null;
}

/// How the setup reads when there is no tagline for it: the engine's own
/// name, de-underscored and sentence-cased.
///
/// `MOVER_TREND_PULLBACK` -> `Mover trend pullback`. Not a translation, but a
/// great deal more readable than the raw shout-case the card used to print,
/// and it cannot hide a setup the engine has that this build has not heard of.
String setupDisplayName(String setupName) => _sentenceCase(setupName);

String _sentenceCase(String raw) {
  final cleaned = raw.trim().replaceAll('_', ' ').toLowerCase();
  if (cleaned.isEmpty) return raw.trim();
  return cleaned[0].toUpperCase() + cleaned.substring(1);
}

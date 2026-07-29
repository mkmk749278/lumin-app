/// Timestamp parsing for engine payloads.
///
/// One rule, and it exists because getting it wrong is silent: **a zone-less
/// timestamp from the engine is UTC, not device-local.**
///
/// `DateTime.parse` returns a UTC value when the string carries `Z` or an
/// offset, and a *local* value when it carries neither. So a naive stamp like
/// `2026-07-29T03:00:33` binds to whatever zone the phone is in — 5h30m of
/// error on an IST device, with no exception and no visible symptom. The
/// engine normalises its stamps (engine #829), but a cached snapshot written
/// by an older build can still serve a zone-less one, and this is the seam
/// where a chart marker's x-coordinate is decided.
///
/// Added 2026-07-29 alongside the fix for chart markers being placed by
/// arithmetic on `minutes_ago` instead of by the engine's own stamps.
library;

/// Parse an engine timestamp to UTC, or `null` when it cannot be read.
///
/// Returns `null` rather than a fallback: a caller plotting this omits its
/// marker instead of drawing one at a fabricated time. Accepts a `DateTime`
/// (round-tripped mock data), an ISO-8601 `String`, `null`, or anything else
/// (which yields `null`).
DateTime? parseUtcTimestamp(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toUtc();
  if (raw is! String) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  // `isUtc` is exactly "the string carried a zone designator": Dart applies
  // the offset and flags the result UTC. Anything else came in zone-less.
  if (parsed.isUtc) return parsed;
  // Zone-less — reinterpret the same wall-clock digits as UTC. The getters
  // below read back the literal parsed components regardless of device zone,
  // so this re-labels rather than shifts.
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}

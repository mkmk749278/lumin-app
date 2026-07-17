/// Number / time formatting for global-audience rendering.
///
/// Pure-Dart helpers — no `intl` package dep.  Crypto + financial
/// surfaces should route through these so we don't accumulate
/// locale-hostile patterns ($-hardcoded, no thousands separators) that
/// will need unwinding when subscriber localisation lands.

String _withSeparators(String integerPart) {
  return integerPart.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}

/// Auto-precision price.  $1,234.56 for liquid pairs; preserves precision
/// on micro-cap altcoins (down to 7 decimals) so $0.0000123 doesn't
/// collapse to $0.00.  No currency symbol — that's the caller's job.
String formatPrice(num value) {
  if (value == 0) return '0.00';
  final absV = value.abs().toDouble();
  int decimals;
  if (absV >= 100) {
    decimals = 2;
  } else if (absV >= 1) {
    decimals = 4;
  } else if (absV >= 0.01) {
    decimals = 5;
  } else {
    decimals = 7;
  }
  final s = absV.toStringAsFixed(decimals);
  final parts = s.split('.');
  final integer = _withSeparators(parts[0]);
  final body = parts.length > 1 ? '$integer.${parts[1]}' : integer;
  return value < 0 ? '-$body' : body;
}

/// P&L in USD with explicit sign and currency symbol.  '+\$12.84' / '-\$3.20'.
String formatPnl(num usd) {
  final absV = usd.abs().toDouble();
  final s = absV.toStringAsFixed(2);
  final parts = s.split('.');
  final integer = _withSeparators(parts[0]);
  final body = '\$$integer.${parts[1]}';
  return usd >= 0 ? '+$body' : '-$body';
}

/// Percentage with explicit sign.  '+1.28%' / '-0.45%'.
String formatPct(num pct, {int decimals = 2}) {
  final sign = pct >= 0 ? '+' : '-';
  return '$sign${pct.abs().toStringAsFixed(decimals)}%';
}

/// Short relative-age label.  '5m' / '2h' / '3d'.  Caller appends 'ago'
/// where needed — most card layouts already have that suffix baked into
/// adjacent copy.
String formatAge(int minutes) {
  if (minutes < 0) return '';
  if (minutes < 60) return '${minutes}m';
  if (minutes < 1440) return '${(minutes / 60).round()}h';
  return '${(minutes / 1440).round()}d';
}

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Human date for the engine's `paid_until` ISO-8601 timestamp:
/// '17 Aug 2026'.  Null / unparseable → null so the caller can drop the
/// renewal line entirely instead of rendering garbage (older backends
/// may omit the field).
String? formatPaidUntil(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  final local = dt.toLocal();
  return '${local.day} ${_monthNames[local.month - 1]} ${local.year}';
}

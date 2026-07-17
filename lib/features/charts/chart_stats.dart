/// Pure helpers for the chart header (2026-07-17 charts polish).
///
/// Kept widget-free so the header's formatting is unit-testable without
/// a WebView: the live price comes from the freshest candle close, the
/// 24h % from the Binance single-symbol ticker (a small-TF candle
/// window doesn't span 24h, so the percent can't be derived from the
/// loaded candles without lying).
library;

/// '1,822.42' style price for the header — precision follows the
/// symbol's own chart precision so sub-dollar alts don't flatten.
String formatHeaderPrice(double price, int precision) {
  final s = price.toStringAsFixed(precision);
  final parts = s.split('.');
  final withSep = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return parts.length > 1 ? '$withSep.${parts[1]}' : withSep;
}

/// '+1.28%' / '-0.45%' for the 24h change chip.
String formatHeaderPct(double pct) =>
    '${pct >= 0 ? '+' : '-'}${pct.abs().toStringAsFixed(2)}%';

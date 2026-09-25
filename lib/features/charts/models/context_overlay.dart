/// Lumin's read of a pair drawn on the chart (Charts redesign part 3).
///
/// Pure: [ContextChartOverlay.from] turns the engine's [PairContext] into the
/// bridge payload — support/resistance bands, the value-area POC line, and a
/// marker for each of Lumin's closed signals on the pair at the bar it
/// opened. Wins AND losses are drawn; a record that showed only the winners
/// would be a win-rate claim in pictures.
library;

import '../../../data/pair_context.dart';

class ContextChartOverlay {
  const ContextChartOverlay({required this.zones, required this.lines, required this.markers});

  final List<Map<String, dynamic>> zones;
  final List<Map<String, dynamic>> lines;
  final List<Map<String, dynamic>> markers;

  bool get isEmpty => zones.isEmpty && lines.isEmpty && markers.isEmpty;

  Map<String, dynamic> toJson() => {'zones': zones, 'lines': lines, 'markers': markers};

  /// Half-width of a level band, as a fraction of the level. A level is a
  /// zone the market reacted around, not a single tick.
  static const double bandFrac = 0.0015;

  static const String _green = '#22e39b';
  static const String _red = '#ff4d6d';
  static const String _accent = '#7bd3f7';

  /// [tfSeconds] snaps each past signal to the start of the bar it opened in
  /// (a marker off the bar grid is dropped by the chart). [oldestBar] /
  /// [newestBar] (seconds) drop markers outside the loaded candles.
  factory ContextChartOverlay.from(
    PairContext c, {
    required int tfSeconds,
    int? oldestBar,
    int? newestBar,
  }) {
    final zones = <Map<String, dynamic>>[];
    for (final (lv, sup) in [
      for (final l in c.supports) (l, true),
      for (final l in c.resistances) (l, false),
    ]) {
      final half = lv.price * bandFrac;
      zones.add({
        'low': lv.price - half,
        'high': lv.price + half,
        'color': sup ? 'rgba(34,227,155,0.10)' : 'rgba(255,77,109,0.10)',
        'borderColor': sup ? 'rgba(34,227,155,0.55)' : 'rgba(255,77,109,0.55)',
        'labelColor': sup ? _green : _red,
        'label': '${sup ? 'Support' : 'Resistance'} · ${lv.touches} touch${lv.touches == 1 ? '' : 'es'}',
      });
    }
    final lines = <Map<String, dynamic>>[
      if (c.valueArea != null) {'price': c.valueArea!.poc, 'color': _accent, 'title': 'POC'},
    ];
    final markers = <Map<String, dynamic>>[];
    for (final p in c.pastSignals) {
      final at = p.openedAt;
      if (at == null || tfSeconds <= 0) continue;
      final sec = at.millisecondsSinceEpoch ~/ 1000;
      final bar = sec - sec % tfSeconds;
      if (oldestBar != null && bar < oldestBar) continue;
      if (newestBar != null && bar > newestBar) continue;
      final won = p.won;
      final color = won == null ? _accent : (won ? _green : _red);
      final pnl = p.pnlPct;
      markers.add({
        'time': bar,
        'position': p.isLong ? 'below' : 'above',
        'shape': p.isLong ? 'arrowUp' : 'arrowDown',
        'color': color,
        'text': pnl == null ? 'Lumin' : '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(1)}%',
      });
    }
    return ContextChartOverlay(zones: zones, lines: lines, markers: markers);
  }
}

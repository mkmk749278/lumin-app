/// Signal-sheet mini chart — the alert-card "setup snap" pattern applied to
/// signals.
///
/// The detail sheet shows a small candle chart with the signal's setup
/// drawn on it: the entry line, the effective stop (entry once break-even
/// has armed), the TP ladder, and a marker on the entry bar.  Pure
/// [CustomPainter] over cached klines ([KlinesThumbnailService]) — no
/// WebView, no engine load; level logic delegates to [ChartOverlay], the
/// same source the full chart draws from.
///
/// Signals carry no timeframe, so the snap picks the smallest TF whose
/// painted window still reaches back to the entry bar ([SignalSnapData.pickTf]).
/// Unlike alerts (immutable, memoised per alert_id), signals are live —
/// break-even arms, status flips — so there is no static memo; the klines
/// service TTL is the cache.
library;

import 'package:flutter/material.dart';

import '../../data/klines_thumbnail_service.dart';
import '../../data/mock_data.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/shimmer.dart';
import '../charts/mini_chart_paint.dart';
import '../charts/models/alert_overlay.dart';
import '../charts/models/candle.dart';
import '../charts/models/chart_overlay.dart';

/// Paint-space setup resolved from a signal + its candles.  Pure and
/// synchronous so tests can pin the mapping without widgets.
class SignalSnapData {
  const SignalSnapData({
    required this.candles,
    required this.entryIndex,
    required this.direction,
    required this.entry,
    required this.stop,
    required this.beArmed,
    this.tp1,
    this.tp2,
    this.tp3,
  });

  /// Trimmed, time-ascending candles actually painted.
  final List<Candle> candles;

  /// Index of the candle the signal entered on.  Null when the entry
  /// precedes the painted window — the marker is suppressed rather than
  /// drawn on a wrong bar (unlike alerts, which fall back to the last bar).
  final int? entryIndex;

  final String direction; // LONG / SHORT
  final double entry;

  /// Effective stop: entry once break-even has armed, else the signal SL —
  /// exactly what the full chart overlay shows.
  final double stop;
  final bool beArmed;
  final double? tp1;
  final double? tp2;
  final double? tp3;

  /// How many painted candles a snap targets.
  static const int targetBars = 60;

  /// Bars of margin kept between the entry bar and the window edge when
  /// picking a timeframe, so the marker never sits pinned to the border.
  static const int _edgeMarginBars = 4;

  /// Smallest supported timeframe whose ~[targetBars]-bar window still
  /// contains the entry with [_edgeMarginBars] of headroom.  Signals carry
  /// no TF of their own (scalp-tier); fresh signals get 15m like the full
  /// chart's default.
  static String pickTf(int minutesAgo) {
    const window = targetBars - _edgeMarginBars; // bars available to reach back
    if (minutesAgo <= window * 15) return '15m';
    if (minutesAgo <= window * 60) return '1h';
    return '4h';
  }

  factory SignalSnapData.build(
    MockSignal sig,
    String tf,
    List<Candle> raw, {
    DateTime? now,
  }) {
    // Canonical level logic — BE-armed effective stop, tpN>0 filtering,
    // openedAtSec — comes from the full-chart overlay model.
    final overlay = ChartOverlay.fromSignal(sig, now: now);

    final start = raw.length > targetBars ? raw.length - targetBars : 0;
    final candles = raw.sublist(start);

    // Entry bar: floor the open time to the TF bucket, then find the last
    // candle at-or-before it.  Entries older than the window get no marker.
    final tfSec = kAlertTfSeconds[tf] ?? 3600;
    final entryBarSec = (overlay.openedAtSec ~/ tfSec) * tfSec;
    int? entryIndex;
    for (var i = candles.length - 1; i >= 0; i--) {
      if (candles[i].time <= entryBarSec) {
        entryIndex = i;
        break;
      }
    }

    return SignalSnapData(
      candles: candles,
      entryIndex: entryIndex,
      direction: overlay.side,
      entry: overlay.entry,
      stop: overlay.stop,
      beArmed: overlay.beArmed,
      tp1: overlay.tp1,
      tp2: overlay.tp2,
      tp3: overlay.tp3,
    );
  }
}

class SignalSnap extends StatefulWidget {
  const SignalSnap({super.key, required this.sig, this.onTap, this.service});

  final MockSignal sig;

  /// Tap-through to the full chart; the snap stays a plain box when null.
  final VoidCallback? onTap;

  /// Test seam — production uses [KlinesThumbnailService.instance].
  final KlinesThumbnailService? service;

  static const double height = 110;

  @override
  State<SignalSnap> createState() => _SignalSnapState();
}

class _SignalSnapState extends State<SignalSnap> {
  SignalSnapData? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final service = widget.service ?? KlinesThumbnailService.instance;
      final tf = SignalSnapData.pickTf(widget.sig.minutesAgo);
      final candles = await service.get(widget.sig.symbol, tf);
      if (!mounted) return;
      if (candles.isEmpty) {
        setState(() => _failed = true);
        return;
      }
      setState(
        () => _data = SignalSnapData.build(widget.sig, tf, candles),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = ClipRRect(
      borderRadius: BorderRadius.circular(LuminRadii.sm),
      child: Container(
        height: SignalSnap.height,
        width: double.infinity,
        color: LuminColors.bgElevated,
        child: _body(),
      ),
    );
    if (widget.onTap == null) return box;
    return GestureDetector(onTap: widget.onTap, child: box);
  }

  Widget _body() {
    final data = _data;
    if (data != null) {
      return CustomPaint(
        painter: SignalSnapPainter(data),
        size: const Size(double.infinity, SignalSnap.height),
      );
    }
    if (_failed) {
      return const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 16, color: LuminColors.textMuted),
            SizedBox(width: 6),
            Text(
              'chart unavailable',
              style: TextStyle(color: LuminColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      );
    }
    // The shimmer masks its child's pixels — give it a filled box to sweep.
    return const Shimmer(
      child: ColoredBox(
        color: LuminColors.bgElevated,
        child: SizedBox.expand(),
      ),
    );
  }
}

class SignalSnapPainter extends CustomPainter {
  SignalSnapPainter(this.data);
  final SignalSnapData data;

  /// TP ladder fades with distance: TP1 strongest, TP3 faintest.
  static const List<double> _tpOpacity = [0.9, 0.55, 0.35];

  @override
  void paint(Canvas canvas, Size size) {
    final candles = data.candles;
    if (candles.isEmpty || size.width <= 0 || size.height <= 0) return;

    final range = miniPriceRange(candles, [
      data.entry,
      data.stop,
      data.tp1,
      data.tp2,
      data.tp3,
    ]);
    if (range == null) return;
    final (minP, maxP) = range;

    // x: index-linear with a right gutter so the levels visibly "run on"
    // past the last bar — same framing as the alert thumbnails.
    final gutter = size.width * 0.10;
    final plotW = size.width - gutter;
    final xStep = plotW / candles.length;
    double xAt(int i) => (i + 0.5) * xStep;
    double yAt(double p) =>
        size.height - ((p - minP) / (maxP - minP)) * size.height;

    void level(double price, Color color) {
      final y = yAt(price);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = color
          ..strokeWidth = 1,
      );
    }

    // 1. Level lines under the candles: TP ladder, stop, entry on top.
    final tps = [data.tp1, data.tp2, data.tp3];
    for (var i = 0; i < tps.length; i++) {
      final tp = tps[i];
      if (tp == null) continue;
      level(tp, LuminColors.success.withOpacity(_tpOpacity[i]));
    }
    level(data.stop, LuminColors.loss.withOpacity(0.9));
    level(data.entry, LuminColors.accent.withOpacity(0.9));

    // 2. Candles.
    paintMiniCandles(canvas, candles, xAt, yAt, xStep);

    // 3. Entry marker: up-triangle under the low for LONG, down-triangle
    // over the high for SHORT — same geometry as the alert marker.
    final idx = data.entryIndex;
    if (idx != null && idx >= 0 && idx < candles.length) {
      final c = candles[idx];
      final x = xAt(idx);
      final above = data.direction == 'SHORT';
      final tipY = above ? yAt(c.high) - 4 : yAt(c.low) + 4;
      final baseY = above ? tipY - 5 : tipY + 5;
      final path = Path()
        ..moveTo(x, tipY)
        ..lineTo(x - 4, baseY)
        ..lineTo(x + 4, baseY)
        ..close();
      canvas.drawPath(path, Paint()..color = LuminColors.accent);
    }
  }

  @override
  bool shouldRepaint(SignalSnapPainter oldDelegate) =>
      !identical(oldDelegate.data, data);
}

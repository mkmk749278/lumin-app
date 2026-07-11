/// Alert-card mini chart — the 100eyes Telegram look, natively painted.
///
/// Each Alerts-feed card shows a small candle chart with the alert's
/// setup drawn on it: the shaded S/R zone running to the right edge, the
/// divergence trend line, the level line, and a marker on the candle
/// that fired.  Pure [CustomPainter] over cached klines
/// ([KlinesThumbnailService]) — no WebView, no engine load.
///
/// Missing geometry (pre-v3 alerts) degrades to candles + marker, the
/// same policy as the full chart overlay.  Painted setups are memoised
/// per `alert_id`, so scrolling away and back costs nothing.
library;

import 'dart:collection';

import 'package:flutter/material.dart';

import '../../data/klines_thumbnail_service.dart';
import '../../data/market_alert.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/shimmer.dart';
import '../charts/models/alert_overlay.dart';
import '../charts/models/candle.dart';

/// Paint-space setup resolved from an alert + its candles.  Pure and
/// synchronous so tests can pin the mapping without widgets.
class ThumbData {
  const ThumbData({
    required this.candles,
    required this.firedIndex,
    required this.bias,
    this.zoneFromIndex,
    this.zoneLow,
    this.zoneHigh,
    this.levelPrice,
    this.divergence,
  });

  /// Trimmed, time-ascending candles actually painted.
  final List<Candle> candles;

  /// Index of the candle the alert fired on (falls back to the last bar).
  final int firedIndex;

  final String bias;

  /// S/R zone: starts at this index and runs to the right edge.
  final int? zoneFromIndex;
  final double? zoneLow;
  final double? zoneHigh;
  final double? levelPrice;

  /// Divergence trend line: (index, price) → (index, price).
  final (int, double, int, double)? divergence;

  /// How many painted candles a thumbnail targets.
  static const int targetBars = 60;

  /// Headroom kept to the left of the zone start so the box visibly
  /// begins on-screen instead of at the exact edge.
  static const int _zoneHeadroomBars = 6;

  static double? _metric(MarketAlert a, String key) {
    final v = a.metrics[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  factory ThumbData.build(MarketAlert alert, List<Candle> raw) {
    // Resolve the fired candle on the FULL series first, then trim so the
    // marker survives trimming; keep the zone start visible.
    final barTime = AlertChartOverlay.alertBarTime(alert);
    var fired = raw.length - 1;
    for (var i = raw.length - 1; i >= 0; i--) {
      if (raw[i].time == barTime) {
        fired = i;
        break;
      }
      if (raw[i].time < barTime) break;
    }

    var keepBars = targetBars;
    final firstTouch = _metric(alert, 'first_touch_bars_ago')?.toInt();
    if (firstTouch != null) {
      keepBars = keepBars < firstTouch + _zoneHeadroomBars
          ? firstTouch + _zoneHeadroomBars
          : keepBars;
    }
    final start = raw.length > keepBars ? raw.length - keepBars : 0;
    final candles = raw.sublist(start);
    final firedIndex = (fired - start)
        .clamp(0, candles.isEmpty ? 0 : candles.length - 1)
        .toInt();

    int? zoneFromIndex;
    double? zoneLow;
    double? zoneHigh;
    double? levelPrice;
    (int, double, int, double)? divergence;

    switch (alert.alertType) {
      case 'NEAR_SUPPORT':
      case 'NEAR_RESISTANCE':
        levelPrice = _metric(alert, 'level_price');
        final low = _metric(alert, 'zone_low');
        final high = _metric(alert, 'zone_high');
        if (low != null && high != null && high > low) {
          zoneLow = low;
          zoneHigh = high;
          zoneFromIndex = firstTouch != null
              ? (firedIndex - firstTouch).clamp(0, firedIndex).toInt()
              : 0;
        }
        break;
      case 'RSI_BULLISH_DIVERGENCE':
      case 'RSI_BEARISH_DIVERGENCE':
        final aBars = _metric(alert, 'pivot_a_bars_ago')?.toInt();
        final bBars = _metric(alert, 'pivot_b_bars_ago')?.toInt();
        final aPrice = _metric(alert, 'pivot_a_price');
        final bPrice = _metric(alert, 'pivot_b_price');
        if (aBars != null && bBars != null && aPrice != null && bPrice != null) {
          divergence = (
            (firedIndex - aBars).clamp(0, firedIndex).toInt(),
            aPrice,
            (firedIndex - bBars).clamp(0, firedIndex).toInt(),
            bPrice,
          );
        }
        break;
    }

    return ThumbData(
      candles: candles,
      firedIndex: firedIndex,
      bias: alert.bias,
      zoneFromIndex: zoneFromIndex,
      zoneLow: zoneLow,
      zoneHigh: zoneHigh,
      levelPrice: levelPrice,
      divergence: divergence,
    );
  }
}

class AlertThumbnail extends StatefulWidget {
  const AlertThumbnail({super.key, required this.alert, this.service});

  final MarketAlert alert;

  /// Test seam — production uses [KlinesThumbnailService.instance].
  final KlinesThumbnailService? service;

  static const double height = 110;

  @override
  State<AlertThumbnail> createState() => _AlertThumbnailState();
}

class _AlertThumbnailState extends State<AlertThumbnail> {
  /// Resolved setups by alert_id — scroll away/back repaints synchronously
  /// with zero refetch/recompute.  Small LRU: ~150 alerts ≈ a full feed.
  static final LinkedHashMap<String, ThumbData> _memo = LinkedHashMap();
  static const int _memoCap = 150;

  ThumbData? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final hit = _memo[widget.alert.alertId];
    if (hit != null) {
      _memo.remove(widget.alert.alertId);
      _memo[widget.alert.alertId] = hit; // refresh LRU position
      _data = hit;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final service = widget.service ?? KlinesThumbnailService.instance;
      final candles =
          await service.get(widget.alert.symbol, widget.alert.timeframe);
      if (!mounted) return;
      if (candles.isEmpty) {
        setState(() => _failed = true);
        return;
      }
      final data = ThumbData.build(widget.alert, candles);
      _memo[widget.alert.alertId] = data;
      while (_memo.length > _memoCap) {
        _memo.remove(_memo.keys.first);
      }
      setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(LuminRadii.sm),
      child: Container(
        height: AlertThumbnail.height,
        width: double.infinity,
        color: LuminColors.bgElevated,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    final data = _data;
    if (data != null) {
      return CustomPaint(
        painter: AlertThumbnailPainter(data),
        size: const Size(double.infinity, AlertThumbnail.height),
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

class AlertThumbnailPainter extends CustomPainter {
  AlertThumbnailPainter(this.data);
  final ThumbData data;

  static const _up = Color(0xFF26A69A);
  static const _down = Color(0xFFEF5350);
  static const _neutral = Color(0xFFF6C85F);

  Color get _biasColor {
    switch (data.bias) {
      case 'BULLISH':
        return _up;
      case 'BEARISH':
        return _down;
      default:
        return _neutral;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final candles = data.candles;
    if (candles.isEmpty || size.width <= 0 || size.height <= 0) return;

    // y-range over everything painted, with 8% breathing room.
    var minP = double.infinity;
    var maxP = -double.infinity;
    for (final c in candles) {
      if (c.low < minP) minP = c.low;
      if (c.high > maxP) maxP = c.high;
    }
    for (final v in [
      data.zoneLow,
      data.zoneHigh,
      data.levelPrice,
      data.divergence?.$2,
      data.divergence?.$4,
    ]) {
      if (v == null) continue;
      if (v < minP) minP = v;
      if (v > maxP) maxP = v;
    }
    if (!minP.isFinite || !maxP.isFinite) return;
    final pad = (maxP - minP) == 0 ? maxP * 0.01 + 1e-9 : (maxP - minP) * 0.08;
    minP -= pad;
    maxP += pad;

    // x: index-linear with a right gutter so the zone visibly "runs on".
    final gutter = size.width * 0.10;
    final plotW = size.width - gutter;
    final xStep = plotW / candles.length;
    double xAt(int i) => (i + 0.5) * xStep;
    double yAt(double p) =>
        size.height - ((p - minP) / (maxP - minP)) * size.height;

    // 1. Zone fill + borders (bottom layer, like the chart primitive).
    if (data.zoneFromIndex != null &&
        data.zoneLow != null &&
        data.zoneHigh != null) {
      final x1 = xAt(data.zoneFromIndex!) - xStep * 0.5;
      final y1 = yAt(data.zoneHigh!);
      final y2 = yAt(data.zoneLow!);
      final rect = Rect.fromLTRB(x1, y1, size.width, y2);
      canvas.drawRect(rect, Paint()..color = _biasColor.withOpacity(0.12));
      final border = Paint()
        ..color = _biasColor.withOpacity(0.55)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x1, y1), Offset(size.width, y1), border);
      canvas.drawLine(Offset(x1, y2), Offset(size.width, y2), border);
    }

    // 2. Level line.
    if (data.levelPrice != null) {
      final y = yAt(data.levelPrice!);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = _biasColor.withOpacity(0.9)
          ..strokeWidth = 1,
      );
    }

    // 3. Candles.
    final bodyW = (xStep * 0.6).clamp(1.0, 6.0);
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final x = xAt(i);
      final color = c.close >= c.open ? _up : _down;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, yAt(c.high)), Offset(x, yAt(c.low)), paint);
      final top = yAt(c.open >= c.close ? c.open : c.close);
      final bottom = yAt(c.open >= c.close ? c.close : c.open);
      canvas.drawRect(
        Rect.fromLTRB(
          x - bodyW / 2,
          top,
          x + bodyW / 2,
          bottom - top < 1 ? top + 1 : bottom, // dojis stay visible
        ),
        paint,
      );
    }

    // 4. Divergence trend line.
    final div = data.divergence;
    if (div != null) {
      canvas.drawLine(
        Offset(xAt(div.$1), yAt(div.$2)),
        Offset(xAt(div.$3), yAt(div.$4)),
        Paint()
          ..color = _biasColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // 5. Marker triangle on the fired candle.
    if (data.firedIndex >= 0 && data.firedIndex < candles.length) {
      final c = candles[data.firedIndex];
      final x = xAt(data.firedIndex);
      final above = data.bias == 'BEARISH';
      final tipY = above ? yAt(c.high) - 4 : yAt(c.low) + 4;
      final baseY = above ? tipY - 5 : tipY + 5;
      final path = Path()
        ..moveTo(x, tipY)
        ..lineTo(x - 4, baseY)
        ..lineTo(x + 4, baseY)
        ..close();
      canvas.drawPath(path, Paint()..color = _biasColor);
    }
  }

  @override
  bool shouldRepaint(AlertThumbnailPainter oldDelegate) =>
      !identical(oldDelegate.data, data);
}

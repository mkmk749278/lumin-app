/// 24h sparklines for the Markets list.
///
/// One `klines(1h, limit 24)` call per pair — Binance weight 1, from the
/// user's own device, so the engine sees none of it. Loaded only for rows the
/// list actually builds (i.e. on screen), at most [_maxInFlight] at once, and
/// cached for [_ttl]: scrolling the ~600-pair board does not fire 600
/// requests, and coming back to the tab does not refetch what is fresh.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/binance_market_data.dart';
import '../../shared/tokens.dart';

class SparklineCache {
  SparklineCache(this._md);

  final BinanceMarketData _md;
  static const Duration _ttl = Duration(minutes: 5);
  static const int _maxInFlight = 4;

  final Map<String, ValueNotifier<List<double>?>> _series = {};
  final Map<String, DateTime> _fetchedAt = {};
  final Queue<String> _queue = Queue<String>();
  final Set<String> _queued = {};
  int _inFlight = 0;
  bool _closed = false;

  /// Closes for [symbol] (null until loaded); requests a load if stale.
  ValueListenable<List<double>?> watch(String symbol) {
    final n = _series.putIfAbsent(symbol, () => ValueNotifier<List<double>?>(null));
    final at = _fetchedAt[symbol];
    if ((at == null || DateTime.now().difference(at) > _ttl) && !_queued.contains(symbol)) {
      _queued.add(symbol);
      _queue.addFirst(symbol); // newest request first: that row is on screen now
      _pump();
    }
    return n;
  }

  void _pump() {
    while (!_closed && _inFlight < _maxInFlight && _queue.isNotEmpty) {
      final s = _queue.removeFirst();
      _inFlight++;
      unawaited(_load(s).whenComplete(() {
        _inFlight--;
        _queued.remove(s);
        _pump();
      }));
    }
  }

  Future<void> _load(String symbol) async {
    try {
      final candles = await _md.klines(symbol: symbol, interval: '1h', limit: 24);
      if (_closed) return;
      _fetchedAt[symbol] = DateTime.now();
      _series[symbol]?.value = [for (final c in candles) c.close];
    } catch (_) {
      // Leave it blank; the row still has price and change. Mark it fetched
      // so a failing symbol is not retried on every rebuild.
      _fetchedAt[symbol] = DateTime.now();
    }
  }

  void close() {
    _closed = true;
    for (final n in _series.values) {
      n.dispose();
    }
    _series.clear();
  }
}

/// A 24h line, coloured by direction, with a soft fill under it.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.points, this.width = 64, this.height = 28});

  final List<double>? points;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = points;
    if (p == null || p.length < 2) {
      return SizedBox(width: width, height: height);
    }
    final up = p.last >= p.first;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: SparklinePainter(p, up ? LuminColors.success : LuminColors.loss),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  SparklinePainter(this.points, this.color);
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = points.first, hi = points.first;
    for (final v in points) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = (hi - lo) == 0 ? 1.0 : hi - lo;
    final dx = size.width / (points.length - 1);
    Offset at(int i) => Offset(i * dx, size.height - 2 - (points[i] - lo) / span * (size.height - 4));
    final line = Path()..moveTo(0, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter old) => old.points != points || old.color != color;
}

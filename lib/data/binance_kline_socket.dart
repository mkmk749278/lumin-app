/// Live Binance Futures kline WebSocket — public mainnet, no API key.
///
/// Streams the in-progress candle for one `<symbol>@kline_<interval>` topic so
/// the chart's last bar updates in real time. Connection is per-device,
/// straight to Binance (`wss://fstream.binance.com`), so there is no fan-out or
/// cost on the Lumin engine. One socket per visible chart; switching symbol or
/// timeframe disposes the old one and opens a new one.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../features/charts/models/candle.dart';

class BinanceKlineSocket {
  BinanceKlineSocket({required this.symbol, required this.interval});

  final String symbol;

  /// Binance interval code, e.g. `15m` / `1h`.
  final String interval;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  StreamController<Candle>? _out;
  Timer? _retry;
  int _attempt = 0;
  bool _closed = false;

  Uri get _uri => Uri.parse(
        'wss://fstream.binance.com/ws/${symbol.toLowerCase()}@kline_$interval',
      );

  /// Live candle updates (the current, possibly-unclosed bar). Each event is a
  /// [Candle] for the latest kline; the chart upserts it by `time`.
  Stream<Candle> stream() {
    _out ??= StreamController<Candle>.broadcast(
      onListen: _connect,
      onCancel: dispose,
    );
    return _out!.stream;
  }

  void _connect() {
    if (_closed) return;
    try {
      final ch = WebSocketChannel.connect(_uri);
      _channel = ch;
      _sub = ch.stream.listen(
        _onFrame,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: false,
      );
      _attempt = 0;
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) {
        final k = j['k'];
        if (k is Map<String, dynamic>) {
          _out?.add(Candle.fromWsKline(k));
        }
      }
    } catch (_) {/* ignore malformed frame */}
  }

  void _scheduleReconnect() {
    if (_closed || _out == null || !_out!.hasListener) return;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _attempt = (_attempt + 1).clamp(1, 6).toInt();
    // Exponential backoff, capped at 16s (1,2,4,8,16,16…).
    final int delaySec = (1 << (_attempt - 1)).clamp(1, 16).toInt();
    _retry?.cancel();
    _retry = Timer(Duration(seconds: delaySec), _connect);
  }

  void dispose() {
    _closed = true;
    _retry?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
    _out?.close();
    _out = null;
  }
}

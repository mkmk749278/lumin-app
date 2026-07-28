/// Market chart screen — candles for one symbol with optional Lumin overlay.
///
/// Reached from (1) the Charts tab pair list (overlay when the pair has a
/// live signal) and (2) a signal detail sheet's "Open chart" (overlay = that
/// signal's entry/SL/TP/BE). History from Binance public klines; the live
/// last bar is kept current by a short REST poll of the latest klines
/// (reliable — reuses the same proven `klines()` path that loads history, so
/// it can't silently freeze the way a background WebSocket can). All
/// app→Binance direct. Rendered by the vendored Lightweight Charts WebView.
///
/// On top of the v1 shell this screen owns:
/// - the candle list (Dart side), merged on every live tick — the source for
///   indicator math and older-history pagination;
/// - toggleable indicators (EMA 21/50, the SMA 7/25/99 mover stack, RSI 14,
///   Parabolic SAR 0.02/0.2), computed in Dart (`indicators.dart`), persisted
///   across sessions;
/// - price-axis precision derived from the symbol's price magnitude (the
///   Lightweight Charts default of 2 decimals flattens sub-dollar alts);
/// - lazy-load of older history when the user pans to the left edge;
/// - a live overlay refresh (SWR signals stream) so the BE shift / status
///   changes move the drawn lines while the chart is open;
/// - lifecycle pause: the poll stops when the app backgrounds.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_config.dart';
import '../../data/binance_market_data.dart';
import '../../data/market_alert.dart';
import '../../data/mock_data.dart';
import '../../data/repository.dart';
import '../../shared/tokens.dart';
import '../pulse/manual_trade_sheet.dart';
import 'chart_stats.dart';
import 'chart_webview.dart';
import 'indicators.dart';
import 'models/alert_overlay.dart';
import 'models/candle.dart';
import 'models/chart_overlay.dart';
import 'sar_disclosure.dart';

class ChartPage extends StatefulWidget {
  const ChartPage({super.key, required this.symbol, this.signal, this.alert});

  final String symbol;

  /// When opened from a signal, draw its entry/SL/TP/BE overlay.
  final MockSignal? signal;

  /// When opened from a market alert: open on the ALERT's timeframe with
  /// the alert's own indicators active and its setup drawn — no manual
  /// effort.  Also shows the alert context bar with the Take-trade action.
  final MarketAlert? alert;

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> with WidgetsBindingObserver {
  final BinanceMarketData _md = BinanceMarketData();
  ChartBridge? _bridge;
  Timer? _poll;
  Timer? _overlayTimer;
  bool _ticking = false; // guards against overlapping poll fetches
  LuminRepository? _repo;

  /// Full candle history currently on the chart (time-ascending). Owned in
  /// Dart so indicators recompute on live ticks and pagination can prepend.
  List<Candle> _candles = const [];

  /// Bumped on every TF switch / reload; async completions from a previous
  /// generation are discarded so a fast TF double-tap can't interleave.
  int _loadGen = 0;

  bool _paginating = false;
  bool _oldestExhausted = false;

  /// Range events are suppressed briefly after every full data load —
  /// `fitContent()` fires one with `from == firstBar`, which would otherwise
  /// trigger a pagination fetch nobody asked for.
  DateTime _suppressRangeUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Live copy of the signal driving the overlay (refreshed from the
  /// repository while the chart is open, so BE-shift / status changes move
  /// the drawn lines). Starts as the signal we were opened with.
  MockSignal? _signal;
  String _lastOverlayJson = '';

  String _tf = '15m';
  bool _loading = true;
  String? _error;
  int _precision = 2;

  // Indicator toggles (persisted).
  bool _showEma = false;
  bool _showMaStack = false;
  bool _showRsi = false;

  /// Parabolic SAR, drawn with the engine's study parameters (see
  /// `indicators.dart`). A *chart study only*: Lumin's exits run on the
  /// signal's SL/TP, never on a SAR flip, and the caption under the chip row
  /// says so — the engine's SAR exit arm is a dark measurement that has not
  /// been adopted, so nothing the user sees here may imply otherwise.
  bool _showSar = false;
  late final Future<void> _prefsLoaded = _loadPrefs();

  /// Signal-levels overlay visibility (session-scoped, default on) —
  /// the "Levels" chip lets the user clear the entry/SL/TP lines to
  /// read raw price action, then bring them back.
  bool _showLevels = true;

  /// 24h ticker for the header (true 24h % — the candle window on
  /// small TFs doesn't span 24h, so it can't be derived from candles).
  MarketTicker? _ticker;
  Timer? _tickerTimer;

  /// Latest traded price for the header — last candle close, updated by
  /// the existing 2s poll; falls back to the ticker's lastPrice.
  double? get _lastPrice =>
      _candles.isNotEmpty ? _candles.last.close : _ticker?.lastPrice;

  Future<void> _refreshTicker() async {
    try {
      final t = await _md.symbolTicker24h(widget.symbol);
      if (mounted) setState(() => _ticker = t);
    } catch (_) {
      /* transient — header keeps its last value */
    }
  }

  /// How often the live last bar is refreshed from REST while the chart is open.
  static const Duration _pollInterval = Duration(seconds: 2);

  /// How often the signal overlay is re-read from the repository (SWR-cached
  /// server-side list — dedups with the Signals tab's own polling).
  static const Duration _overlayRefreshInterval = Duration(seconds: 30);

  /// History cap: 6 pages of 500. Lightweight Charts handles far more, but
  /// the JSON bridge payload and indicator math stay comfortably bounded.
  static const int _maxBars = 3000;

  static const List<String> _tfs = ['1m', '5m', '15m', '1h', '4h', '1D'];

  static const Map<String, int> _tfSeconds = {
    '1m': 60,
    '5m': 300,
    '15m': 900,
    '1h': 3600,
    '4h': 14400,
    '1D': 86400,
  };

  @override
  void initState() {
    super.initState();
    _signal = widget.signal;
    WidgetsBinding.instance.addObserver(this);
    _refreshTicker();
    _tickerTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshTicker(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo ??= AppConfigScope.maybeOf(context)?.repo;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _overlayTimer?.cancel();
    _tickerTimer?.cancel();
    _md.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_bridge != null && _candles.isNotEmpty) {
        _tick(); // catch up bars missed while backgrounded
        _startPoll();
        _startOverlayTimer();
      }
      _refreshTicker();
      _tickerTimer ??= Timer.periodic(
        const Duration(seconds: 60),
        (_) => _refreshTicker(),
      );
    } else {
      // paused / inactive / hidden / detached — no polling off-screen.
      _poll?.cancel();
      _overlayTimer?.cancel();
      _tickerTimer?.cancel();
      _tickerTimer = null;
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      _tf = _tfs.contains(p.getString('charts.tf')) ? p.getString('charts.tf')! : _tf;
      _showEma = p.getBool('charts.ind.ema') ?? false;
      _showMaStack = p.getBool('charts.ind.ma') ?? false;
      _showRsi = p.getBool('charts.ind.rsi') ?? false;
      _showSar = p.getBool('charts.ind.sar') ?? false;
    } catch (_) {/* prefs unavailable — defaults are fine */}
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('charts.tf', _tf);
      await p.setBool('charts.ind.ema', _showEma);
      await p.setBool('charts.ind.ma', _showMaStack);
      await p.setBool('charts.ind.rsi', _showRsi);
      await p.setBool('charts.ind.sar', _showSar);
    } catch (_) {/* best-effort */}
  }

  Future<void> _onReady(ChartBridge bridge) async {
    _bridge = bridge;
    await _prefsLoaded; // restore last TF + indicator toggles before first draw
    _applyAlertContext();
    if (mounted) setState(() {});
    await _loadAndStream();
  }

  /// Opened from an alert card: mirror the alert's context exactly — its
  /// timeframe and the indicator it observed — without touching the
  /// user's saved chart preferences (session-only overrides).
  void _applyAlertContext() {
    final a = widget.alert;
    if (a == null) return;
    if (_tfs.contains(a.timeframe)) _tf = a.timeframe;
    if (a.alertType.startsWith('RSI')) _showRsi = true;
  }

  Future<void> _loadAndStream() async {
    final bridge = _bridge;
    if (bridge == null) return;
    final gen = ++_loadGen;
    _poll?.cancel();
    _oldestExhausted = false;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final candles = await _md.klines(
        symbol: widget.symbol,
        interval: BinanceMarketData.intervals[_tf] ?? '15m',
        limit: 500,
      );
      if (gen != _loadGen || !mounted) return;
      _candles = candles;
      _precision = _derivePrecision(candles);
      _suppressRangeUntil = DateTime.now().add(const Duration(milliseconds: 1500));
      await bridge.setCandles(
        _tf,
        candles,
        precision: _precision,
        minMove: minMoveForPrecision(_precision),
      );
      await _pushIndicators();
      await _pushOverlay(force: true);
      await _pushAlertOverlay();
      _startPoll();
      _startOverlayTimer();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (gen != _loadGen) return;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load chart: $e';
        });
      }
    }
  }

  /// Precision from the smallest price on screen — the magnitude that needs
  /// the most decimals to resolve.
  static int _derivePrecision(List<Candle> candles) {
    var minLow = double.infinity;
    for (final c in candles) {
      if (c.low > 0 && c.low < minLow) minLow = c.low;
    }
    return chartPrecisionFor(minLow.isFinite ? minLow : 0);
  }

  /// Keep the latest bar(s) live with a short REST poll. We re-fetch the last
  /// two klines so both the in-progress bar and the just-closed bar finalise.
  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _tick());
  }

  void _startOverlayTimer() {
    _overlayTimer?.cancel();
    if (_signal == null || _repo == null) return;
    _overlayTimer =
        Timer.periodic(_overlayRefreshInterval, (_) => _refreshOverlay());
  }

  Future<void> _tick() async {
    final bridge = _bridge;
    if (bridge == null || _ticking) return;
    _ticking = true;
    final gen = _loadGen;
    try {
      final latest = await _md.klines(
        symbol: widget.symbol,
        interval: BinanceMarketData.intervals[_tf] ?? '15m',
        limit: 2,
      );
      if (gen != _loadGen || !mounted) return;
      _candles = upsertCandles(_candles, latest);
      for (final c in latest) {
        await bridge.updateCandle(c);
      }
      await _pushIndicatorTails();
      // Header price tracks the freshest close.
      if (mounted) setState(() {});
    } catch (_) {
      /* transient — next tick retries; history already on screen */
    } finally {
      _ticking = false;
    }
  }

  // ---------------------------------------------------------------------
  // Indicators
  // ---------------------------------------------------------------------

  static const _emaSpecs = [
    (id: 'ema21', title: 'EMA 21', color: '#f6c85f', period: 21),
    (id: 'ema50', title: 'EMA 50', color: '#5d8bf4', period: 50),
  ];
  static const _maSpecs = [
    (id: 'sma7', title: 'MA 7', color: '#4dd0e1', period: 7),
    (id: 'sma25', title: 'MA 25', color: '#f39c6b', period: 25),
    (id: 'sma99', title: 'MA 99', color: '#e57ab1', period: 99),
  ];

  /// Parabolic SAR is the one indicator here that reads highs/lows rather than
  /// closes — the same two arrays the engine's study feeds `parabolic_sar`.
  static const _sarSpec = (id: 'sar', title: 'SAR', color: '#9aa4b2');

  List<double> get _closes => [for (final c in _candles) c.close];
  List<double> get _highs => [for (final c in _candles) c.high];
  List<double> get _lows => [for (final c in _candles) c.low];

  static List<Map<String, dynamic>> _seriesData(
    List<Candle> candles,
    List<double?> values,
  ) {
    return [
      for (var i = 0; i < candles.length; i++)
        if (values[i] != null) {'time': candles[i].time, 'value': values[i]},
    ];
  }

  /// Full recompute + push of every active indicator (load, toggle, prepend).
  Future<void> _pushIndicators() async {
    final bridge = _bridge;
    if (bridge == null || _candles.isEmpty) return;
    final closes = _closes;
    final lines = <IndicatorLine>[
      if (_showEma)
        for (final s in _emaSpecs)
          IndicatorLine(
            id: s.id,
            title: s.title,
            color: s.color,
            data: _seriesData(_candles, ema(closes, s.period)),
          ),
      if (_showMaStack)
        for (final s in _maSpecs)
          IndicatorLine(
            id: s.id,
            title: s.title,
            color: s.color,
            data: _seriesData(_candles, sma(closes, s.period)),
          ),
      if (_showSar)
        IndicatorLine(
          id: _sarSpec.id,
          title: _sarSpec.title,
          color: _sarSpec.color,
          style: IndicatorStyle.dots,
          data: _seriesData(_candles, parabolicSar(_highs, _lows)),
        ),
    ];
    await bridge.setIndicators(
      lines: lines,
      rsiData: _showRsi ? _seriesData(_candles, rsi(closes)) : null,
      showVolume: !_showRsi, // one bottom band on a phone: RSI swaps volume
    );
  }

  /// Cheap per-tick refresh: recompute over the in-memory candles (µs-scale
  /// for ≤3000 doubles) and push only each active line's newest point.
  Future<void> _pushIndicatorTails() async {
    final bridge = _bridge;
    if (bridge == null || _candles.isEmpty) return;
    if (!_showEma && !_showMaStack && !_showRsi && !_showSar) return;
    final closes = _closes;
    final t = _candles.last.time;
    final points = <Map<String, dynamic>>[
      if (_showEma)
        for (final s in _emaSpecs)
          {'id': s.id, 'time': t, 'value': ema(closes, s.period).last},
      if (_showMaStack)
        for (final s in _maSpecs)
          {'id': s.id, 'time': t, 'value': sma(closes, s.period).last},
      // SAR is forward-recursive: an earlier bar's level never changes, so
      // pushing only the newest point stays identical to a full recompute.
      if (_showSar)
        {
          'id': _sarSpec.id,
          'time': t,
          'value': parabolicSar(_highs, _lows).last,
        },
    ];
    final rsiLast = _showRsi ? rsi(closes).last : null;
    await bridge.updateIndicators(
      points: points,
      rsiPoint: rsiLast != null ? {'time': t, 'value': rsiLast} : null,
    );
  }

  /// See `sar_disclosure.dart` — the copy carries the two things the dots
  /// themselves cannot say.
  String get _sarCaption => sarCaption(_tf);

  Future<void> _toggleIndicator(void Function() flip) async {
    setState(flip);
    unawaited(_savePrefs());
    await _pushIndicators();
  }

  // ---------------------------------------------------------------------
  // Older-history pagination
  // ---------------------------------------------------------------------

  void _onVisibleRange(double from, double to) {
    if (_candles.isEmpty || _paginating || _oldestExhausted) return;
    if (_candles.length >= _maxBars) return;
    if (DateTime.now().isBefore(_suppressRangeUntil)) return;
    final barSec = _tfSeconds[_tf] ?? 900;
    // Only fetch when the user has panned within ~30 bars of the oldest data.
    if (from > _candles.first.time + barSec * 30) return;
    unawaited(_loadOlder());
  }

  Future<void> _loadOlder() async {
    final bridge = _bridge;
    if (bridge == null || _paginating) return;
    _paginating = true;
    final gen = _loadGen;
    try {
      final older = await _md.klines(
        symbol: widget.symbol,
        interval: BinanceMarketData.intervals[_tf] ?? '15m',
        limit: 500,
        endTimeMs: _candles.first.time * 1000 - 1,
      );
      if (gen != _loadGen || !mounted) return;
      final cutoff = _candles.first.time;
      final fresh = [
        for (final c in older)
          if (c.time < cutoff) c,
      ];
      if (older.length < 500) _oldestExhausted = true;
      if (fresh.isEmpty) {
        _oldestExhausted = true;
        return;
      }
      _candles = [...fresh, ..._candles];
      _suppressRangeUntil =
          DateTime.now().add(const Duration(milliseconds: 1500));
      await bridge.setCandles(
        _tf,
        _candles,
        precision: _precision,
        minMove: minMoveForPrecision(_precision),
        preserveView: true,
      );
      await _pushIndicators();
    } catch (_) {
      /* transient — the next left-edge pan retries */
    } finally {
      _paginating = false;
    }
  }

  // ---------------------------------------------------------------------
  // Signal overlay (live)
  // ---------------------------------------------------------------------

  Future<void> _pushOverlay({bool force = false}) async {
    final bridge = _bridge;
    final sig = _signal;
    if (bridge == null || sig == null || !_showLevels) return;
    final overlay = ChartOverlay.fromSignal(sig);
    final encoded = jsonEncode(overlay.toJson());
    if (!force && encoded == _lastOverlayJson) return;
    _lastOverlayJson = encoded;
    await bridge.setOverlay(overlay);
  }

  /// "Levels" chip — hide/show the signal's entry/SL/TP lines so the
  /// user can read raw price action.  Uses the existing clearOverlay
  /// bridge call; re-enabling force-pushes the latest overlay.
  Future<void> _toggleLevels() async {
    setState(() => _showLevels = !_showLevels);
    if (_showLevels) {
      await _pushOverlay(force: true);
    } else {
      _lastOverlayJson = '';
      await _bridge?.clearOverlay();
    }
  }

  /// Draw the alert's setup (zone box / level line / divergence segments /
  /// alert marker) and zoom to the setup window — static once drawn; the
  /// setup the alert observed doesn't move the way a signal's BE/SL does.
  Future<void> _pushAlertOverlay() async {
    final bridge = _bridge;
    final a = widget.alert;
    if (bridge == null || a == null) return;
    // The overlay's focus fires a visibleRangeChanged whose `from` can sit
    // near the oldest bar — re-arm suppression so it can't trigger an
    // unwanted history-pagination fetch.
    _suppressRangeUntil = DateTime.now().add(const Duration(milliseconds: 1500));
    await bridge.setAlertOverlay(AlertChartOverlay.fromAlert(a, chartTf: _tf));
  }

  /// Re-read the signal from the repository so the drawn lines track reality
  /// (BE shift moves the stop line to entry; a close updates the status).
  /// Uses the SWR-cached signals list — the same key the Signals tab watches,
  /// so this dedups with its traffic instead of adding engine load.
  Future<void> _refreshOverlay() async {
    final repo = _repo;
    final base = _signal;
    if (repo == null || base == null) return;
    try {
      final items = await repo.watchSignals(status: 'all', limit: 100).last;
      if (!mounted) return;
      for (final s in items) {
        if (s.id == base.id) {
          _signal = s;
          await _pushOverlay();
          break;
        }
      }
    } catch (_) {
      /* transient — next refresh retries; last overlay stays drawn */
    }
  }

  // ---------------------------------------------------------------------

  void _onTf(String tf) {
    if (tf == _tf) return;
    setState(() => _tf = tf);
    unawaited(_savePrefs());
    _loadAndStream();
  }

  @override
  Widget build(BuildContext context) {
    final price = _lastPrice;
    final pct = _ticker?.changePct;
    final pctColor = (pct ?? 0) >= 0 ? LuminColors.success : LuminColors.loss;
    return Scaffold(
      appBar: AppBar(
        // Symbol + live price + true 24h % — the header a trading app is
        // expected to have (2026-07-17 charts polish).
        title: Row(
          children: [
            Text(widget.symbol),
            if (price != null) ...[
              const SizedBox(width: 12),
              Text(
                formatHeaderPrice(price, _precision),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: LuminColors.textPrimary,
                ),
              ),
            ],
            if (pct != null) ...[
              const SizedBox(width: 8),
              Text(
                formatHeaderPct(pct),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: pctColor,
                ),
              ),
            ],
          ],
        ),
      ),
      body: Column(
        children: [
          // Timeframes on their own row — the old single scrolling row
          // pushed half the chips off-screen (owner screenshots).
          SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 12),
                for (final tf in _tfs)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(tf, textAlign: TextAlign.center),
                        ),
                        labelPadding: EdgeInsets.zero,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        visualDensity: VisualDensity.compact,
                        selected: tf == _tf,
                        onSelected: (_) => _onTf(tf),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          // Indicator + overlay toggles on a second row.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('EMA'),
                    visualDensity: VisualDensity.compact,
                    selected: _showEma,
                    onSelected: (_) =>
                        _toggleIndicator(() => _showEma = !_showEma),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('MAs'),
                    visualDensity: VisualDensity.compact,
                    selected: _showMaStack,
                    onSelected: (_) =>
                        _toggleIndicator(() => _showMaStack = !_showMaStack),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('RSI'),
                    visualDensity: VisualDensity.compact,
                    selected: _showRsi,
                    onSelected: (_) =>
                        _toggleIndicator(() => _showRsi = !_showRsi),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('SAR'),
                    visualDensity: VisualDensity.compact,
                    selected: _showSar,
                    onSelected: (_) =>
                        _toggleIndicator(() => _showSar = !_showSar),
                  ),
                ),
                if (_signal != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('Levels'),
                      visualDensity: VisualDensity.compact,
                      selected: _showLevels,
                      onSelected: (_) => _toggleLevels(),
                    ),
                  ),
              ],
            ),
          ),
          if (_showSar)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LuminSpacing.md,
                0,
                LuminSpacing.md,
                LuminSpacing.xs,
              ),
              child: Text(
                _sarCaption,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.3,
                  color: LuminColors.textMuted,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                ChartWebView(
                  onReady: _onReady,
                  onError: _onWebError,
                  onVisibleRange: _onVisibleRange,
                ),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.alert != null) _AlertContextBar(alert: widget.alert!),
        ],
      ),
    );
  }

  void _onWebError(String message) {
    if (mounted) setState(() => _error = 'Chart error: $message');
  }
}

/// Compact bar under the chart when opened from a market alert: shows what
/// the alert observed (the setup drawn above) and the Take-trade action —
/// an entry-only manual trade on the user's own account.
class _AlertContextBar extends StatelessWidget {
  const _AlertContextBar({required this.alert});
  final MarketAlert alert;

  Color _biasColor() {
    switch (alert.bias) {
      case 'BULLISH':
        return LuminColors.success;
      case 'BEARISH':
        return LuminColors.loss;
      default:
        return LuminColors.warn;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _biasColor();
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminSpacing.lg,
          vertical: LuminSpacing.sm,
        ),
        decoration: const BoxDecoration(
          color: LuminColors.bgCard,
          border: Border(top: BorderSide(color: LuminColors.cardBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${alert.title} (${alert.timeframe})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alert.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: LuminColors.textSecondary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: LuminSpacing.md),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LuminColors.accent,
                foregroundColor: LuminColors.bgDeep,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => showManualTradeSheet(
                context,
                symbol: alert.symbol,
                refId: 'alert-${alert.alertId}',
                currentPrice: alert.price,
                bias: alert.bias,
              ),
              child: const Text('Take trade'),
            ),
          ],
        ),
      ),
    );
  }
}

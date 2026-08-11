/// The full track record — what a reader gets when they open the Pulse card.
///
/// **Modelled on Binance's Futures PNL Analysis, deliberately not copied.**
/// Studying that screen (2026-08-11) three mechanics are worth taking, and they
/// are taken here:
///
/// 1. **A view toggle on the daily data** — bars for *how big*, calendar for
///    *which days*. Same numbers, two questions, one section header.
/// 2. **Tap a day, and the section header reads it back.** A chart you can only
///    look at is a picture; a chart that answers a question is a record.
/// 3. **The daily bars and the running total are SEPARATE charts**, each with
///    its own labelled axis. Binance never overlays them, and that is right:
///    an overlay costs both marks their axis, and a number you cannot read off
///    a chart is decoration. (The compact Pulse card still overlays them —
///    that is a summary tile, and it says so by being tappable.)
///
/// And three things are **changed**, because this is a signal book and not an
/// exchange account:
///
/// * Their per-day popover shows *Net Transfer* and *Trading Volume* — account
///   facts we do not have and would have to invent. Ours shows what we do have:
///   the day's signals, its W/L, its distinct moves, and the trades themselves.
/// * **A day on which nothing closed reads `—`, never `0.00`.** For an exchange
///   a zero day is true: you traded nothing, so you made nothing. Here `0.00`
///   would assert that signals closed and netted flat. The calendar exists
///   largely *for* this distinction — the bar chart omits such a day entirely
///   and cannot draw the difference between "quiet" and "no data".
/// * The calendar is a **continuous week grid over the fetched window**, not a
///   month with a stepper. A stepper implies months we have not fetched, and an
///   empty January would read as "no trades" when it means "not loaded".
///
/// Everything the card carries about honesty carries here: RECORDED rather than
/// back-tested, the position size and fee named beside the money, today marked
/// as still running, and trades we could not price disclosed rather than
/// dropped.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import 'track_record_card.dart' show TrackRecordChartScale;

const _windows = <int>[7, 30, 90];

enum _DailyView { bars, calendar }

class TrackRecordPage extends StatefulWidget {
  const TrackRecordPage({super.key, required this.initial, this.repo});

  /// The window the Pulse card was showing, so opening the page continues the
  /// reader's context instead of resetting it.
  final TrackRecord initial;

  /// Data source, defaulting to the app scope's.
  ///
  /// Explicit rather than always reached through `AppConfigScope` so the
  /// widget tests can drive fixed payloads — a page whose data source cannot
  /// be substituted can only be tested against whatever the mock repository
  /// happens to synthesise, which means the branches that matter here (a
  /// truncated list, a day with nothing to open) go unasserted.
  final LuminRepository? repo;

  @override
  State<TrackRecordPage> createState() => _TrackRecordPageState();
}

class _TrackRecordPageState extends State<TrackRecordPage> {
  late TrackRecord _data = widget.initial;
  late int _days = widget.initial.days;
  _DailyView _view = _DailyView.bars;
  bool _loading = false;
  int _seq = 0;

  /// The day the reader has selected, or null for the whole window.
  ///
  /// Drives three things at once — the readout above the chart, the highlight
  /// on the chart, and which signals the list below shows — because those are
  /// one question asked three ways and letting them drift apart is how a page
  /// starts describing two different days at once.
  String? _selected;

  TrackRecordSignals _signals = TrackRecordSignals.empty;
  bool _signalsLoading = false;
  int _signalsSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSignals());
  }

  LuminRepository get _repo =>
      widget.repo ?? AppConfigScope.of(context).repo;

  Future<void> _selectWindow(int days) async {
    if (days == _days) return;
    final seq = ++_seq;
    setState(() {
      _days = days;
      _loading = true;
      // The selected day may not exist in the new window. Clearing it is the
      // honest move: keeping it would leave the list below describing a day
      // the chart above no longer contains.
      _selected = null;
    });
    try {
      final got =
          await _repo.fetchTrackRecord(days: days);
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = got;
        _loading = false;
      });
      _loadSignals();
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() => _loading = false);
    }
  }

  void _selectDay(String? date) {
    setState(() => _selected = _selected == date ? null : date);
    _loadSignals();
  }

  Future<void> _loadSignals() async {
    final seq = ++_signalsSeq;
    setState(() => _signalsLoading = true);
    try {
      final got = await _repo.fetchTrackRecordSignals(
            days: _days,
            date: _selected ?? '',
          );
      if (!mounted || seq != _signalsSeq) return;
      setState(() {
        _signals = got;
        _signalsLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _signalsSeq) return;
      setState(() {
        _signals = TrackRecordSignals.empty;
        _signalsLoading = false;
      });
    }
  }

  TrackRecordDay? get _selectedDay {
    if (_selected == null) return null;
    for (final d in _data.items) {
      if (d.date == _selected) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: LuminColors.bgDeep,
      appBar: AppBar(
        title: const Text(
          'Track record',
          style: TextStyle(
            color: LuminColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: LuminSpacing.lg),
            child: Center(child: _RecordedChip()),
          ),
        ],
      ),
      body: !d.hasBook
          ? const _EmptyState()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: LuminSpacing.md),
              children: [
                _summary(d),
                const SizedBox(height: LuminSpacing.md),
                _dailySection(d),
                const SizedBox(height: LuminSpacing.md),
                _cumulativeSection(d),
                const SizedBox(height: LuminSpacing.md),
                _signalsSection(d),
                const SizedBox(height: LuminSpacing.md),
                _assumptions(d),
                const SizedBox(height: LuminSpacing.xl),
              ],
            ),
    );
  }

  // -------------------------------------------------------------------------
  // Summary
  // -------------------------------------------------------------------------

  Widget _summary(TrackRecord d) {
    final s = d.summary;
    final net = s.netUsd ?? 0.0;
    final color = net >= 0 ? LuminColors.success : LuminColors.loss;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final w in _windows) ...[
                  _Chip(
                    label: '${w}D',
                    selected: w == _days,
                    onTap: () => _selectWindow(w),
                  ),
                  const SizedBox(width: LuminSpacing.sm),
                ],
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: LuminColors.accentMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: LuminSpacing.lg),
            Text(
              formatPnl(net),
              style: TextStyle(
                color: color,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'net, from every signal at ${_usdt(d.amountUsdt)} each',
              style: const TextStyle(
                  color: LuminColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: LuminSpacing.md),
            // Gross and fee beside net, never instead of it. The cost of
            // trading on this book runs several times the edge, so a
            // gross-only figure answers a question nobody asked.
            Row(
              children: [
                _MiniStat(
                  label: 'GROSS',
                  value: s.grossUsd == null ? '—' : formatPnl(s.grossUsd!),
                  color: LuminColors.textSecondary,
                ),
                _MiniStat(
                  label: 'FEES',
                  value: s.feeUsd == null ? '—' : '-\$${s.feeUsd!.toStringAsFixed(2)}',
                  color: LuminColors.textSecondary,
                ),
                _MiniStat(
                  label: 'NET',
                  value: formatPnl(net),
                  color: color,
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            const Divider(height: 1, color: LuminColors.cardBorder),
            const SizedBox(height: LuminSpacing.md),
            Row(
              children: [
                _MiniStat(
                  label: 'SIGNALS',
                  value: '${s.trades}',
                  sub: s.moves == s.trades ? null : '${s.moves} moves',
                ),
                _MiniStat(
                  label: 'WIN RATE',
                  value: s.winRate == null
                      ? '—'
                      : '${(s.winRate! * 100).round()}%',
                  sub: '${s.wins}W / ${s.losses}L',
                ),
                _MiniStat(
                  label: 'BEST / WORST',
                  value: s.bestPnlPct == null
                      ? '—'
                      : formatPct(s.bestPnlPct!, decimals: 1),
                  sub: s.worstPnlPct == null
                      ? null
                      : formatPct(s.worstPnlPct!, decimals: 1),
                ),
              ],
            ),
            if (s.tradesPriced != s.trades) ...[
              const SizedBox(height: LuminSpacing.sm),
              Text(
                '${s.trades - s.tradesPriced} of ${s.trades} could not be '
                'priced and are left out of every figure above.',
                style: const TextStyle(
                    color: LuminColors.textMuted, fontSize: 10.5, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Daily — bars OR calendar
  // -------------------------------------------------------------------------

  Widget _dailySection(TrackRecord d) {
    final sel = _selectedDay;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'DAILY RESULT',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _ViewToggle(
                  view: _view,
                  onChanged: (v) => setState(() => _view = v),
                ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            // The readout. This is the half that turns a picture into a
            // record: tap a day and the header says what that day was.
            _DayReadout(day: sel, amountUsdt: d.amountUsdt),
            const SizedBox(height: LuminSpacing.md),
            if (_view == _DailyView.bars)
              _BarsView(record: d, selected: _selected, onTap: _selectDay)
            else
              _CalendarView(record: d, selected: _selected, onTap: _selectDay),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Running total — its own chart, its own axis
  // -------------------------------------------------------------------------

  Widget _cumulativeSection(TrackRecord d) {
    final last = d.items.isEmpty ? 0.0 : d.items.last.cumNetUsd;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RUNNING TOTAL',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatPnl(last),
              style: TextStyle(
                color: last >= 0 ? LuminColors.success : LuminColors.loss,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'since ${_shortDate(d.rangeStart)} · UTC',
              style:
                  const TextStyle(color: LuminColors.textMuted, fontSize: 10.5),
            ),
            const SizedBox(height: LuminSpacing.md),
            _AxisChart(
              record: d,
              selected: _selected,
              cumulative: true,
              onTap: _selectDay,
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Signals
  // -------------------------------------------------------------------------

  Widget _signalsSection(TrackRecord d) {
    final scoped = _selected != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    scoped
                        ? 'SIGNALS ON ${_shortDate(_selected!).toUpperCase()}'
                        : 'SIGNALS IN THIS WINDOW',
                    style: const TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_signalsLoading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: LuminColors.accentMuted,
                    ),
                  )
                else if (scoped)
                  GestureDetector(
                    onTap: () => _selectDay(null),
                    child: const Text(
                      'Show all',
                      style: TextStyle(
                          color: LuminColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            if (_signals.items.isEmpty && !_signalsLoading)
              const Text(
                'No signals closed here.',
                style:
                    TextStyle(color: LuminColors.textMuted, fontSize: 12),
              )
            else
              for (final sig in _signals.items) _SignalRow(signal: sig),
            if (_signals.truncated) ...[
              const SizedBox(height: LuminSpacing.sm),
              Text(
                // Say when the cap bit, and against what. A truncated list
                // that does not say so is a smaller book pretending to be the
                // whole one.
                'Showing the newest ${_signals.items.length} of '
                '${_signals.matched}.',
                style: const TextStyle(
                    color: LuminColors.textMuted, fontSize: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _assumptions(TrackRecord d) {
    final fee = d.feePct == d.feePct.roundToDouble()
        ? d.feePct.toStringAsFixed(0)
        : d.feePct.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: Text(
        'Every signal here was delivered and tracked in real time — recorded as '
        'each trade happened, not a back-test. Each is counted at '
        '${_usdt(d.amountUsdt)}, the same size every time and no compounding, '
        'with a $fee% round-trip fee charged. A day showing — is a day on which '
        'nothing closed, not a flat day. All dates are UTC. Your own results '
        'will differ: what you receive depends on your settings and your fills. '
        'Past signal performance does not guarantee future results.',
        style: const TextStyle(
          color: LuminColors.textMuted,
          fontSize: 10.5,
          height: 1.5,
        ),
      ),
    );
  }

  static String _usdt(double a) =>
      '${a == a.roundToDouble() ? a.toStringAsFixed(0) : a.toStringAsFixed(2)} USDT';
}

// ---------------------------------------------------------------------------
// Shared date helper
// ---------------------------------------------------------------------------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `2026-07-12` -> `12 Jul`. Returns the input unchanged when it is not a date
/// this understands — a raw ISO string is ugly but true, and inventing a date
/// would not be.
String _shortDate(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (m == null || d == null || m < 1 || m > 12) return iso;
  return '$d ${_months[m - 1]}';
}

// ---------------------------------------------------------------------------
// The day readout — what makes the charts answer rather than decorate
// ---------------------------------------------------------------------------

class _DayReadout extends StatelessWidget {
  const _DayReadout({required this.day, required this.amountUsdt});

  final TrackRecordDay? day;
  final double amountUsdt;

  @override
  Widget build(BuildContext context) {
    final d = day;
    if (d == null) {
      return const Text(
        'Tap a day to see what closed on it',
        style: TextStyle(color: LuminColors.textMuted, fontSize: 12),
      );
    }
    final net = d.netUsd;
    final color = net == null
        ? LuminColors.textMuted
        : (net >= 0 ? LuminColors.success : LuminColors.loss);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Wrap, not a Row: with "still running" present this line overflows a
        // 430px phone by 27px, and an overflow is content the reader cannot
        // see. Wrapping degrades to two lines instead of clipping the badge
        // that says today is not finished — which is the one part of this line
        // that must never be the part that disappears.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            Text(
              net == null ? '—' : formatPnl(net),
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Text(
              '${_shortDate(d.date)} UTC',
              style: const TextStyle(
                  color: LuminColors.textSecondary, fontSize: 12),
            ),
            // Today is partial by construction. Letting it read as a
            // finished day is how a part-period reads as a whole one.
            if (d.inProgress)
              const Text(
                'still running',
                style: TextStyle(
                  color: LuminColors.warn,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${d.trades} signal${d.trades == 1 ? '' : 's'} · '
          '${d.wins}W / ${d.losses}L'
          '${d.moves == d.trades ? '' : ' · ${d.moves} moves'}',
          style: const TextStyle(color: LuminColors.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bars view
// ---------------------------------------------------------------------------

class _BarsView extends StatelessWidget {
  const _BarsView({
    required this.record,
    required this.selected,
    required this.onTap,
  });

  final TrackRecord record;
  final String? selected;
  final ValueChanged<String?> onTap;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _AxisChart(
            record: record,
            selected: selected,
            cumulative: false,
            onTap: onTap,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_shortDate(record.rangeStart),
                  style: const TextStyle(
                      color: LuminColors.textMuted, fontSize: 10)),
              Text(
                  record.items.isEmpty
                      ? ''
                      : _shortDate(record.items.last.date),
                  style: const TextStyle(
                      color: LuminColors.textMuted, fontSize: 10)),
            ],
          ),
        ],
      );
}

/// A chart with a real, labelled y-axis — bars or the running-total line.
///
/// The axis is the point. Binance's PNL Analysis gives its daily chart and its
/// cumulative chart one each and never overlays them, because an overlaid pair
/// costs both marks their axis and a number you cannot read off a chart is
/// decoration. This widget is that separation: one series, one scale, one set
/// of labels.
class _AxisChart extends StatelessWidget {
  const _AxisChart({
    required this.record,
    required this.selected,
    required this.cumulative,
    required this.onTap,
  });

  final TrackRecord record;
  final String? selected;
  final bool cumulative;
  final ValueChanged<String?> onTap;

  static const _height = 132.0;
  static const _axisWidth = 42.0;

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final i in record.items)
        cumulative ? i.cumNetUsd : (i.netUsd ?? 0.0)
    ];
    if (values.isEmpty) return const SizedBox(height: _height);
    final scale = TrackRecordChartScale.of(_height, [values]);

    return SizedBox(
      height: _height,
      child: Row(
        children: [
          SizedBox(
            width: _axisWidth,
            child: _AxisLabels(values: values, scale: scale, height: _height),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (e) =>
                    onTap(_dateAt(e.localPosition.dx, box.maxWidth)),
                child: CustomPaint(
                  size: Size(box.maxWidth, _height),
                  painter: _SeriesPainter(
                    record: record,
                    values: values,
                    scale: scale,
                    cumulative: cumulative,
                    selected: selected,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The date nearest the tapped x, so a fat finger lands on a bar rather than
  /// between two.
  String? _dateAt(double dx, double width) {
    final start = DateTime.tryParse('${record.rangeStart}T00:00:00Z');
    if (start == null || record.items.isEmpty) return null;
    final last = DateTime.tryParse('${record.items.last.date}T00:00:00Z');
    if (last == null) return null;
    final span = math.max(1, last.difference(start).inDays);
    String? best;
    var bestDx = double.infinity;
    for (final it in record.items) {
      final d = DateTime.tryParse('${it.date}T00:00:00Z');
      if (d == null) continue;
      final x = (d.difference(start).inDays / span) * (width - 8) + 4;
      final gap = (x - dx).abs();
      if (gap < bestDx) {
        bestDx = gap;
        best = it.date;
      }
    }
    return best;
  }
}

class _AxisLabels extends StatelessWidget {
  const _AxisLabels({
    required this.values,
    required this.scale,
    required this.height,
  });

  final List<double> values;
  final TrackRecordChartScale scale;
  final double height;

  @override
  Widget build(BuildContext context) {
    final hi = values.fold<double>(0.0, math.max);
    final lo = values.fold<double>(0.0, math.min);
    // Three labels: the top, zero, the bottom. Enough to read a magnitude off
    // the chart without turning the axis into a wall of numbers on a phone.
    final marks = <double>{hi, 0.0, lo}.toList()..sort((a, b) => b.compareTo(a));
    return Stack(
      children: [
        for (final v in marks)
          Positioned(
            right: 6,
            top: (scale.y(v, values) - 6).clamp(0.0, height - 12),
            child: Text(
              _short(v),
              style:
                  const TextStyle(color: LuminColors.textMuted, fontSize: 9),
            ),
          ),
      ],
    );
  }

  static String _short(double v) {
    if (v == 0) return '0';
    final a = v.abs();
    final s = a >= 100 ? a.toStringAsFixed(0) : a.toStringAsFixed(1);
    return '${v < 0 ? '-' : ''}\$$s';
  }
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({
    required this.record,
    required this.values,
    required this.scale,
    required this.cumulative,
    required this.selected,
  });

  final TrackRecord record;
  final List<double> values;
  final TrackRecordChartScale scale;
  final bool cumulative;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final items = record.items;
    final start = DateTime.tryParse('${record.rangeStart}T00:00:00Z');
    final dates = [
      for (final it in items) DateTime.tryParse('${it.date}T00:00:00Z')
    ];
    if (start == null || items.isEmpty || dates.any((d) => d == null)) return;

    final span = math.max(1, dates.last!.difference(start).inDays);
    // Positioned by DATE, never by index: the engine omits days on which
    // nothing closed, so an index-positioned chart would close the gaps and
    // draw a book that traded every single day.
    double xFor(DateTime d) =>
        (d.difference(start).inDays / span) * (size.width - 8) + 4;

    final zeroY = scale.zeroY;
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = LuminColors.textMuted.withOpacity(0.25)
        ..strokeWidth = 1,
    );

    // Selection marker, drawn under the data so it never obscures it.
    if (selected != null) {
      final d = DateTime.tryParse('${selected!}T00:00:00Z');
      if (d != null) {
        final x = xFor(d);
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = LuminColors.accent.withOpacity(0.35)
            ..strokeWidth = 1,
        );
      }
    }

    if (cumulative) {
      final path = Path();
      for (var i = 0; i < items.length; i++) {
        final x = xFor(dates[i]!);
        final y = scale.y(values[i], values);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = LuminColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        Offset(xFor(dates.last!), scale.y(values.last, values)),
        2.6,
        Paint()..color = LuminColors.accent,
      );
      return;
    }

    final barW =
        math.max(2.0, math.min(10.0, (size.width - 8) / span * 0.72));
    for (var i = 0; i < items.length; i++) {
      final v = items[i].netUsd;
      if (v == null) continue;
      final x = xFor(dates[i]!);
      final y = scale.y(v, values);
      final up = v >= 0;
      final base = up ? LuminColors.success : LuminColors.loss;
      final isSel = items[i].date == selected;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - barW / 2,
            up ? y : zeroY,
            barW,
            math.max(1.0, (y - zeroY).abs()),
          ),
          const Radius.circular(1.5),
        ),
        Paint()
          ..color = base.withOpacity(
            // Today is faint because it is still running, not because it is
            // unimportant — the engine says which day that is.
            items[i].inProgress && !isSel ? 0.35 : (isSel ? 1.0 : 0.85),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_SeriesPainter old) =>
      old.record != record ||
      old.selected != selected ||
      old.cumulative != cumulative;
}

// ---------------------------------------------------------------------------
// Calendar view
// ---------------------------------------------------------------------------

/// A continuous week grid over the fetched window.
///
/// **Not a month with a stepper**, which is what Binance uses. A stepper
/// implies months we have not fetched, and an empty January would read as "no
/// trades" when it means "not loaded" — a blank needs a cause before it gets a
/// caption. The grid covers exactly the window the summary above describes.
///
/// A day on which nothing closed shows `—`, never `0.00`. That distinction is
/// most of why this view exists: the bar chart omits such a day entirely and
/// cannot draw the difference between a quiet day and a missing one.
class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.record,
    required this.selected,
    required this.onTap,
  });

  final TrackRecord record;
  final String? selected;
  final ValueChanged<String?> onTap;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse('${record.rangeStart}T00:00:00Z');
    if (start == null || record.items.isEmpty) return const SizedBox.shrink();
    final last = DateTime.tryParse('${record.items.last.date}T00:00:00Z');
    if (last == null) return const SizedBox.shrink();

    final byDate = {for (final i in record.items) i.date: i};
    // Pad back to the Monday on or before the window's first day so the
    // columns line up under their weekday headers.
    final gridStart = start.subtract(Duration(days: start.weekday - 1));
    final totalDays = last.difference(gridStart).inDays + 1;
    final weeks = (totalDays / 7).ceil();

    return Column(
      key: const ValueKey('track-record-calendar'),
      children: [
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: const TextStyle(
                        color: LuminColors.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              children: [
                for (var dow = 0; dow < 7; dow++)
                  Expanded(
                    child: _cell(
                      gridStart.add(Duration(days: w * 7 + dow)),
                      start,
                      last,
                      byDate,
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          '— nothing closed that day',
          style: TextStyle(color: LuminColors.textMuted, fontSize: 9.5),
        ),
      ],
    );
  }

  Widget _cell(
    DateTime day,
    DateTime windowStart,
    DateTime windowEnd,
    Map<String, TrackRecordDay> byDate,
  ) {
    final iso = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final outside = day.isBefore(windowStart) || day.isAfter(windowEnd);
    if (outside) return const SizedBox(height: 40);

    final entry = byDate[iso];
    final net = entry?.netUsd;
    final isSel = iso == selected;
    final tint = net == null
        ? Colors.transparent
        : (net >= 0 ? LuminColors.success : LuminColors.loss)
            .withOpacity(isSel ? 0.30 : 0.14);

    return GestureDetector(
      onTap: entry == null ? null : () => onTap(iso),
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(LuminRadii.sm),
          border: Border.all(
            color: isSel
                ? LuminColors.accent.withOpacity(0.7)
                : LuminColors.cardBorder,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: entry == null
                    ? LuminColors.textMuted
                    : LuminColors.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              // `—`, never `0.00`. For an exchange a zero day is true; here it
              // would assert that signals closed and netted flat.
              net == null
                  ? '—'
                  : (net >= 0 ? '+' : '-') + net.abs().toStringAsFixed(1),
              style: TextStyle(
                color: net == null
                    ? LuminColors.textMuted
                    : (net >= 0 ? LuminColors.success : LuminColors.loss),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Signal row
// ---------------------------------------------------------------------------

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.signal});

  final TrackRecordSignal signal;

  @override
  Widget build(BuildContext context) {
    final net = signal.netUsd;
    final color = net == null
        ? LuminColors.textMuted
        : (net >= 0 ? LuminColors.success : LuminColors.loss);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: signal.isLong ? LuminColors.success : LuminColors.loss,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: LuminSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        signal.symbol,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LuminColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      signal.direction,
                      style: TextStyle(
                        color: signal.isLong
                            ? LuminColors.success
                            : LuminColors.loss,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Text(
                  [
                    if (signal.outcome.isNotEmpty) signal.outcome,
                    _prettySetup(signal.setup),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: LuminColors.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: LuminSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                net == null ? '—' : formatPnl(net),
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              Text(
                // Gross beside the money, so the fee is visible per row and
                // not only in the total.
                signal.pnlPct == null ? '' : formatPct(signal.pnlPct!),
                style: const TextStyle(
                    color: LuminColors.textMuted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// `MOVER_TREND_PULLBACK` -> `Mover trend pullback`. The setup class is an
  /// engine identifier; a subscriber should not have to read SCREAMING_SNAKE.
  static String _prettySetup(String raw) {
    if (raw.isEmpty) return '';
    final words = raw.toLowerCase().replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }
}

// ---------------------------------------------------------------------------
// Bits
// ---------------------------------------------------------------------------

class _RecordedChip extends StatelessWidget {
  const _RecordedChip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: LuminColors.success.withOpacity(0.12),
          borderRadius: BorderRadius.circular(LuminRadii.pill),
          border: Border.all(color: LuminColors.success.withOpacity(0.35)),
        ),
        child: const Text(
          'RECORDED',
          style: TextStyle(
            color: LuminColors.success,
            fontSize: 9,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(LuminSpacing.xl),
          child: Text(
            'The track record is not available right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: LuminColors.textMuted, fontSize: 13),
          ),
        ),
      );
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _DailyView view;
  final ValueChanged<_DailyView> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LuminRadii.sm),
          border: Border.all(color: LuminColors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(Icons.bar_chart_rounded, _DailyView.bars, 'Bars'),
            _button(
                Icons.calendar_month_outlined, _DailyView.calendar, 'Calendar'),
          ],
        ),
      );

  Widget _button(IconData icon, _DailyView target, String tooltip) {
    final on = view == target;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => onChanged(target),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          color: on ? LuminColors.accent.withOpacity(0.14) : Colors.transparent,
          child: Icon(
            icon,
            size: 15,
            color: on ? LuminColors.accent : LuminColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(LuminRadii.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(LuminRadii.pill),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? LuminColors.accent.withOpacity(0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(LuminRadii.pill),
              border: Border.all(
                color: selected
                    ? LuminColors.accent.withOpacity(0.5)
                    : LuminColors.cardBorder,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color:
                    selected ? LuminColors.accent : LuminColors.textSecondary,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.sub,
    this.color,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: LuminColors.textMuted,
                fontSize: 9,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                color: color ?? LuminColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (sub != null)
              Text(
                sub!,
                style: const TextStyle(
                    color: LuminColors.textMuted, fontSize: 10),
              ),
          ],
        ),
      );
}

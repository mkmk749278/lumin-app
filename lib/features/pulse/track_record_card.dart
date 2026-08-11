/// Pulse — the recorded track record of every signal we delivered.
///
/// **Why this card exists.** A per-user paper book starts empty at enrolment,
/// so until this shipped (2026-08-11) a brand-new subscriber's Pulse tab could
/// say nothing at all about whether the signals work: a regime bar, an upsell,
/// "Trading not enabled yet", three recent signals. The engine has recorded
/// every closed signal since it was built and the owner's ops dashboard has
/// reduced that record since 2026-07-28; this puts the same book in front of
/// the person deciding whether to subscribe.
///
/// **It is not a Binance PnL screen and must not become one.** An exchange
/// shows you *your account*: money you actually made, on trades you actually
/// took. This is the *signal book* — pooled across every subscriber, at one
/// fixed notional, recorded as each trade happened. Two consequences the layout
/// is built around:
///
/// * **It is readable on day one with zero trades**, which is the whole point
///   and the thing no exchange screen can do.
/// * **It states its own assumptions on screen** — the size every dollar
///   figure uses, the fee charged, that today is still running, and that the
///   reader's own results will differ. An exchange never has to say any of
///   that because it is showing you your own fills. We do.
///
/// **The headline is money at a stated size, deliberately not a percentage.**
/// The engine sizes at a fixed notional, so summing per-trade percentages is
/// arithmetically fine and reads as something it is not: "+51.85%" over a month
/// looks like an account return, and it is not one — the same book needed ~400
/// USDT to hold its peak concurrent positions, so the return on capital was
/// about a quarter of that number. A reader cannot be expected to make that
/// correction, and a figure that flatters us when they fail to is the one we
/// must not print. Money at a size the card names has no such reading.
///
/// **Every figure here is UTC**, because the engine is UTC end to end and the
/// day boundaries are the engine's. The card says so rather than letting a
/// device-local reader assume otherwise, and it never derives "today" from the
/// device clock — the engine stamps which day is still running.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import 'track_record_page.dart';

/// Windows the card offers. Kept short on purpose: each one is a round trip,
/// and a fourth option buys less than the clutter costs on a phone.
const _windows = <int>[7, 30, 90];

class TrackRecordCard extends StatefulWidget {
  const TrackRecordCard({super.key, required this.initial});

  /// The 30-day book that arrived with the Pulse bundle, so the card paints on
  /// first frame instead of spinning. A different window refetches.
  final TrackRecord initial;

  @override
  State<TrackRecordCard> createState() => _TrackRecordCardState();
}

class _TrackRecordCardState extends State<TrackRecordCard> {
  late TrackRecord _data = widget.initial;
  late int _days = widget.initial.days;
  bool _loading = false;

  /// Guards against a slow 7d response landing after a fast 90d one and
  /// repainting the card with a window the user has already moved off.
  int _requestSeq = 0;

  @override
  void didUpdateWidget(TrackRecordCard old) {
    super.didUpdateWidget(old);
    // A pull-to-refresh re-fetches the bundle's 30-day book. Adopt it only if
    // the user is still on that window — otherwise their selection would snap
    // back under them on every refresh.
    if (widget.initial != old.initial && _days == widget.initial.days) {
      setState(() => _data = widget.initial);
    }
  }

  Future<void> _select(int days) async {
    if (days == _days && !_loading) return;
    final seq = ++_requestSeq;
    setState(() {
      _days = days;
      _loading = true;
    });
    try {
      final got =
          await AppConfigScope.of(context).repo.fetchTrackRecord(days: days);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _data = got;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      // Keep the previous window on screen rather than blanking the card: a
      // failed fetch is not evidence that the book is empty, and an empty
      // chart would say exactly that.
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (!d.hasBook) return const SizedBox.shrink();

    final s = d.summary;
    final net = s.netUsd ?? 0.0;
    final positive = net >= 0;
    final color = positive ? LuminColors.success : LuminColors.loss;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        // The card is a summary tile; the full record — bars vs calendar, the
        // running total on its own axis, and the signals behind each day —
        // lives on its own page. A dashboard tile should not hold a calendar,
        // and a headline nobody can open is a claim rather than a record.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrackRecordPage(initial: _data),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: LuminSpacing.md),
            _windowChips(),
            const SizedBox(height: LuminSpacing.lg),
            _headline(net, color),
            const SizedBox(height: LuminSpacing.lg),
            _chart(d, color),
            const SizedBox(height: LuminSpacing.sm),
            _axisLabels(d),
            const SizedBox(height: LuminSpacing.lg),
            _stats(s),
            const SizedBox(height: LuminSpacing.md),
            const Divider(height: 1, color: LuminColors.cardBorder),
            const SizedBox(height: LuminSpacing.md),
            _assumptions(d),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------

  Widget _header() => Row(
        children: [
          const Icon(Icons.verified_outlined,
              size: 16, color: LuminColors.accent),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'SIGNAL TRACK RECORD',
              style: TextStyle(
                color: LuminColors.textMuted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // "RECORDED" is the load-bearing word on this card. It separates it
          // from every back-test and what-if surface we run internally, and
          // from the counterfactuals that measure ~0.38R optimistic. A reader
          // must be able to tell at a glance that these trades happened.
          Container(
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
          ),
          const SizedBox(width: 4),
          // The affordance for the page below. The footer already promises
          // "tap for every day and every signal"; a promise with no visible
          // control is how a reader learns the card does nothing.
          const Icon(Icons.chevron_right,
              size: 16, color: LuminColors.textMuted),
        ],
      );

  Widget _windowChips() => Row(
        children: [
          for (final w in _windows) ...[
            _Chip(
              label: '${w}D',
              selected: w == _days,
              onTap: () => _select(w),
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
      );

  Widget _headline(double net, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatPnl(net),
            style: TextStyle(
              color: color,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            // The size is named in the same breath as the number, always.
            // A dollar figure whose position size the reader cannot see is an
            // assumption wearing a measurement's clothes.
            'from every signal, at ${_usdt(_data.amountUsdt)} each · fees paid',
            style: const TextStyle(
              color: LuminColors.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      );

  Widget _chart(TrackRecord d, Color color) => SizedBox(
        height: 96,
        child: CustomPaint(
          size: Size.infinite,
          painter: _TrackRecordPainter(record: d),
        ),
      );

  Widget _axisLabels(TrackRecord d) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _shortDate(d.rangeStart),
            style: const TextStyle(color: LuminColors.textMuted, fontSize: 10),
          ),
          const Text(
            'daily result · running total · UTC',
            style: TextStyle(color: LuminColors.textMuted, fontSize: 10),
          ),
          Text(
            d.items.isEmpty ? '' : _shortDate(d.items.last.date),
            style: const TextStyle(color: LuminColors.textMuted, fontSize: 10),
          ),
        ],
      );

  Widget _stats(TrackRecordSummary s) {
    final winPct = s.winRate == null ? null : s.winRate! * 100.0;
    return Column(
      children: [
        Row(
          children: [
            _Stat(
              label: 'SIGNALS',
              value: '${s.trades}',
              // Overlapping entries into one price move exit at the same price
              // and are not independent evidence. Disclosed rather than
              // de-duplicated: collapsing them is the reader's judgement to
              // make, and doing it silently is what this guards against.
              sub: s.moves == s.trades ? null : '${s.moves} distinct moves',
            ),
            _Stat(
              label: 'WIN RATE',
              value: winPct == null ? '—' : '${winPct.round()}%',
              sub: '${s.wins}W / ${s.losses}L',
            ),
            _Stat(
              label: 'AVG / SIGNAL',
              // Net of the round trip, matching the headline. Showing a gross
              // average beside a net total would be two books in one row.
              value: s.avgNetPct == null ? '—' : formatPct(s.avgNetPct!),
              sub: 'after fees',
            ),
          ],
        ),
        if (s.tradesPriced != s.trades) ...[
          const SizedBox(height: LuminSpacing.sm),
          Text(
            // The two denominators differ. Say so rather than quietly
            // describing a smaller book than the count above claims.
            '${s.trades - s.tradesPriced} of ${s.trades} could not be priced '
            'and are left out of every figure above.',
            style: const TextStyle(
                color: LuminColors.textMuted, fontSize: 10.5, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _assumptions(TrackRecord d) {
    final fee = d.feePct == d.feePct.roundToDouble()
        ? d.feePct.toStringAsFixed(0)
        : d.feePct.toString();
    return Text(
      'Recorded as each trade happened — not a back-test. Every delivered '
      'signal taken at ${_usdt(d.amountUsdt)}, the same size each time, with a '
      '$fee% round-trip fee charged. Your own results will differ: what you '
      'receive depends on your settings and your fills. Past signal '
      'performance does not guarantee future results. Tap for every day and '
      'every signal behind these numbers.',
      style: const TextStyle(
        color: LuminColors.textMuted,
        fontSize: 10.5,
        height: 1.45,
      ),
    );
  }

  static String _usdt(double amount) =>
      '${amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)} USDT';

  /// `2026-07-12` -> `12 Jul`. Returns the input unchanged if it is not a date
  /// this understands — a raw ISO string is ugly but true, and inventing a
  /// date would not be.
  static String _shortDate(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (m == null || d == null || m < 1 || m > 12) return iso;
    return '$d ${months[m - 1]}';
  }
}

// ---------------------------------------------------------------------------
// Chart
// ---------------------------------------------------------------------------

/// Daily results as bars, with the running total as a line over them.
///
/// One chart rather than two tabs, because the two answer halves of one
/// question — *what happened each day* and *where does the book stand* — and a
/// reader on a phone should not have to hold one in their head while looking at
/// the other.
///
/// **Bars are positioned by DATE, never by index.** The engine omits days on
/// which nothing closed, so an index-positioned chart would silently close the
/// gaps and draw a book that traded every single day. Spacing by date is what
/// makes a quiet stretch look quiet.
/// Where zero sits, and how far a value is drawn from it.
///
/// Public (and named for its card) only so `track_record_card_test.dart` can
/// drive the symmetry property directly. Measuring it through a rendered
/// CustomPaint would mean asserting pixels, and a test nobody can read is not
/// a guard against a defect nobody can see.
///
/// Exists as its own object because the property it guarantees is the one a
/// glance at the chart cannot verify and a reader would never question:
///
/// > **A dollar above zero and a dollar below it are the same number of
/// > pixels.**
///
/// The first cut gave the two sides independent room — the zero line was placed
/// by the running total's range, and each series then filled whatever space was
/// left on its own side. On the owner's real 30-day book that put zero at 65%
/// of the height, so a **-$22.85 day rendered about a third as tall as a
/// +$26.18 day**. Every number behind it was right and the chart said the
/// losses were small. On a performance surface that is the one direction an
/// error must never point, and it is invisible without measuring pixels.
///
/// Each series keeps its **own full-scale** — a day's result and a month's
/// running total differ by an order of magnitude, and one magnitude scale would
/// flatten the bars into the axis. What they share is the zero line and the
/// symmetry about it, which is what [of] computes across all of them at once.
class TrackRecordChartScale {
  const TrackRecordChartScale._(this.zeroY, this._pxPerUnit);

  /// Pixels from the top to the zero line.
  final double zeroY;

  /// Pixels per **normalised** unit — a value divided by its own series' peak,
  /// so each series spans at most [-1, 1]. Identical in both directions, which
  /// is the whole point.
  final double _pxPerUnit;

  /// Build a scale that fits every series and is symmetric about zero.
  ///
  /// Zero is not pinned to the middle: a book that never lost should not spend
  /// half the chart on empty space below the axis. It is placed where the
  /// normalised extremes put it, which keeps the pixels-per-unit equal on both
  /// sides for free — that equality is exactly what pinning or clamping it
  /// would break, so neither is done.
  factory TrackRecordChartScale.of(double height, List<List<double>> series) {
    var hi = 0.0;
    var lo = 0.0;
    for (final s in series) {
      final peak = s.fold<double>(0.0, (a, v) => math.max(a, v.abs()));
      if (peak <= 0) continue;
      for (final v in s) {
        final n = v / peak;
        hi = math.max(hi, n);
        lo = math.min(lo, n);
      }
    }
    final span = hi - lo;
    if (span <= 0) return TrackRecordChartScale._(height / 2, 0);
    // Inset so a full-scale value has a pixel of air rather than sitting on
    // the frame — applied to the span, so it cannot break the symmetry.
    final usable = height - 4;
    return TrackRecordChartScale._(2 + usable * (hi / span), usable / span);
  }

  /// The y for [value], normalised against its own [series]' peak.
  double y(double value, List<double> series) {
    final peak = series.fold<double>(0.0, (a, v) => math.max(a, v.abs()));
    if (peak <= 0 || _pxPerUnit <= 0) return zeroY;
    return zeroY - (value / peak) * _pxPerUnit;
  }
}

class _TrackRecordPainter extends CustomPainter {
  _TrackRecordPainter({required this.record});

  final TrackRecord record;

  @override
  void paint(Canvas canvas, Size size) {
    final items = record.items;
    if (items.isEmpty) return;

    final start = DateTime.tryParse('${record.rangeStart}T00:00:00Z');
    final dates = <DateTime?>[
      for (final it in items) DateTime.tryParse('${it.date}T00:00:00Z'),
    ];
    if (start == null || dates.any((d) => d == null)) return;

    // Span the whole requested window, not just the days that traded, so a
    // window whose first week was quiet renders as a quiet first week.
    final lastDate = dates.last!;
    final spanDays = math.max(1, lastDate.difference(start).inDays);
    double xFor(DateTime d) =>
        (d.difference(start).inDays / spanDays) * (size.width - 8) + 4;

    // --- vertical scale ---------------------------------------------------
    // Bars and the line each get their OWN full-scale, because one day's
    // result and a month's running total differ by an order of magnitude and a
    // shared magnitude scale would flatten the bars into the axis. Two scales
    // on one zero line is readable as long as the line is visibly a different
    // mark, which is why it is a stroked path over filled bars.
    //
    // What they must share is that **a unit above zero and a unit below it are
    // the same number of pixels** — see [TrackRecordChartScale]. The first cut gave the
    // two sides independent room, so on the owner's real 30-day book a -$22.85
    // day rendered about a third as tall as a +$26.18 day. Nothing was wrong
    // with any number and the chart said the losses were small: exactly the
    // direction a performance surface must never be wrong in.
    final bars = [for (final i in items) i.netUsd ?? 0.0];
    final cums = [for (final i in items) i.cumNetUsd];
    final scale = TrackRecordChartScale.of(size.height, [bars, cums]);
    final zeroY = scale.zeroY;

    // --- zero line --------------------------------------------------------
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = LuminColors.textMuted.withOpacity(0.25)
        ..strokeWidth = 1,
    );

    // --- bars -------------------------------------------------------------
    final barW = math.max(
      2.0,
      math.min(8.0, (size.width - 8) / math.max(1, spanDays) * 0.7),
    );
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final v = it.netUsd;
      if (v == null) continue;
      final x = xFor(dates[i]!);
      final y = scale.y(v, bars);
      final h = (y - zeroY).abs();
      final up = v >= 0;
      final base = up ? LuminColors.success : LuminColors.loss;
      final rect = Rect.fromLTWH(
        x - barW / 2,
        up ? zeroY - h : zeroY,
        barW,
        math.max(1.0, h),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()
          // Today is still running, so its bar is drawn faint. It is not a
          // finished day and must not read as one — the engine stamps which
          // day that is; this never asks the device clock, which can be in a
          // different timezone from every figure on the card.
          ..color = base.withOpacity(it.inProgress ? 0.35 : 0.85),
      );
    }

    // --- running total ----------------------------------------------------
    final path = Path();
    for (var i = 0; i < items.length; i++) {
      final x = xFor(dates[i]!);
      final y = scale.y(cums[i], cums);
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

    // End dot, so the eye lands on where the book actually stands.
    canvas.drawCircle(
      Offset(xFor(dates.last!), scale.y(cums.last, cums)),
      2.6,
      Paint()..color = LuminColors.accent,
    );
  }

  @override
  bool shouldRepaint(_TrackRecordPainter old) => old.record != record;
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

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
              style: const TextStyle(
                color: LuminColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (sub != null)
              Text(
                sub!,
                style: const TextStyle(
                  color: LuminColors.textMuted,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      );
}

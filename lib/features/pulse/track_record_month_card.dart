/// Pulse — the delivered-signal book as a calendar month.
///
/// Added 2026-08-11 on the owner's direction: *"keep that month card in main
/// pulse page"*. It shipped **beside** a rolling 7/30/90-day summary card, and
/// on 2026-08-12 that card was removed and this one kept: *"we don't need two
/// track cards there, keep that signal book by day"*. Two cards over one book
/// on two different periods made the reader reconcile two headlines before
/// reading either — and the calendar is the half that answers *what happened*,
/// which is the question a day-by-day book is for.
///
/// **What had to come with it.** The removed card carried the RECORDED badge
/// and the sentences that make a performance figure honest — that these trades
/// happened rather than being replayed, the size and fee every dollar assumes,
/// that the reader's own results will differ, and that past performance
/// guarantees nothing. Those are not decoration on the other card; they are
/// the conditions under which *any* of these numbers may be shown at all. They
/// moved here with the grid. A performance surface that loses its disclosure
/// in a layout change is the one regression this card must never ship.
///
/// The rolling window is not gone — it is the first thing on the page this
/// card opens, along with per-day signal detail.
import 'package:flutter/material.dart';

import '../../data/app_config.dart';
import '../../data/repository.dart';
import '../../data/track_record_prefs.dart';
import '../../shared/format.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/lumin_card.dart';
import 'month_calendar.dart';
import 'track_record_page.dart';

class TrackRecordMonthCard extends StatefulWidget {
  const TrackRecordMonthCard({
    super.key,
    required this.window,
    this.repo,
    this.today,
  });

  /// The rolling-window book from the Pulse bundle. Used only to decide
  /// whether there is a record worth showing at all, and to hand the page a
  /// starting window — never for the calendar's own numbers, which come from
  /// a month fetch.
  final TrackRecord window;

  final LuminRepository? repo;

  /// The clock, injectable for tests — mirrors [MonthCalendar.today], which
  /// has carried the same seam since it shipped and which this card was
  /// simply not forwarding.
  ///
  /// It is load-bearing because the month this card opens on is derived from
  /// the clock, and `MonthCalendar` draws NO figure on a day that has not
  /// happened yet ("a day that has not happened is not a quiet day"). A test
  /// whose fixture puts data on the 4th of the current month therefore
  /// asserts a cell that does not exist on the 1st, 2nd or 3rd — green for
  /// three weeks in four, red on the rest, and it went red on the first CI
  /// run that happened to land on a 1st (2026-09-01). Same class as the
  /// engine's calendar-lucky assertion two days earlier: pin the date rather
  /// than wait out the month.
  final DateTime? today;

  @override
  State<TrackRecordMonthCard> createState() => _TrackRecordMonthCardState();
}

class _TrackRecordMonthCardState extends State<TrackRecordMonthCard> {
  late String _month = monthOf(widget.today ?? DateTime.now().toUtc());
  TrackRecord _data = TrackRecord.empty;
  bool _loading = true;
  int _seq = 0;

  LuminRepository get _repo => widget.repo ?? AppConfigScope.of(context).repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    TrackRecordPrefs.instance.amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    TrackRecordPrefs.instance.amount.removeListener(_onAmountChanged);
    super.dispose();
  }

  /// The size is one app-wide number, so changing it on the page must move
  /// this card too — a size that meant different things on two screens would
  /// be worse than no control at all.
  void _onAmountChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final got = await _repo.fetchTrackRecord(
        month: _month,
        amount: TrackRecordPrefs.instance.amountOrNull,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = got;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      // Keep whatever is on screen rather than blanking: a failed fetch is not
      // evidence the month was quiet, and an empty grid says exactly that.
      setState(() => _loading = false);
    }
  }

  void _step(String month) {
    setState(() => _month = month);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // Gated on the WINDOW's book, not this month's: a month that happens to be
    // quiet is a real answer worth showing, while no record at all is not.
    if (!widget.window.hasBook) return const SizedBox.shrink();

    final net = _data.month == _month ? _data.summary.netUsd : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg),
      child: LuminCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrackRecordPage(initial: widget.window),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined,
                    size: 15, color: LuminColors.accent),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'SIGNAL BOOK BY DAY',
                    style: TextStyle(
                      color: LuminColors.textMuted,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // "RECORDED" is the load-bearing word, inherited from the card
                // removed on 2026-08-12. It separates this book from every
                // back-test and what-if surface we run internally, and from
                // the counterfactuals that measure ~0.38R optimistic. A reader
                // must be able to tell at a glance that these trades happened.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: LuminColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(LuminRadii.pill),
                    border:
                        Border.all(color: LuminColors.success.withOpacity(0.35)),
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
                if (_loading)
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: LuminColors.accentMuted,
                    ),
                  )
                else if (net != null)
                  Text(
                    formatPnl(net),
                    style: TextStyle(
                      color:
                          net >= 0 ? LuminColors.success : LuminColors.loss,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 16, color: LuminColors.textMuted),
              ],
            ),
            const SizedBox(height: LuminSpacing.md),
            MonthCalendar(
              month: _month,
              record: _data,
              loading: _loading,
              onStep: _step,
              today: widget.today,
              earliestDate: _data.earliestDate.isNotEmpty
                  ? _data.earliestDate
                  : widget.window.earliestDate,
              compact: true,
            ),
            const SizedBox(height: LuminSpacing.sm),
            // The assumptions, inherited whole from the card removed on
            // 2026-08-12. Every one of them is a condition on reading the grid
            // above: the size each cell assumes, the fee already charged, that
            // these are our delivered signals and not the reader's own fills,
            // and that none of it predicts the next month. A grid of dollar
            // figures whose size the reader cannot see is an assumption
            // wearing a measurement's clothes, on every one of its cells.
            Text(
              'Each day: every signal we delivered that closed, recorded as it '
              'happened — not a back-test. Taken at ${_usdt(_shown.amountUsdt)} '
              'each, the same size every time, with a ${_fee(_shown.feePct)}% '
              'round-trip fee charged. UTC. Your own results will differ: what '
              'you receive depends on your settings and your fills. Past '
              'signal performance does not guarantee future results. Tap for '
              'every day and every signal behind these numbers.',
              style: const TextStyle(
                  color: LuminColors.textMuted, fontSize: 10, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  /// The record whose assumptions are actually on screen.
  ///
  /// While a month is in flight `_data` still holds the *previous* month, so
  /// naming its size beside this month's heading would state an assumption
  /// that is not the one the cells were priced with. The window book carries
  /// the same engine-supplied size and fee and is the honest stand-in until
  /// the month lands.
  TrackRecord get _shown => _data.month == _month ? _data : widget.window;

  static String _fee(double f) =>
      f == f.roundToDouble() ? f.toStringAsFixed(0) : f.toString();

  static String _usdt(double a) =>
      '${a == a.roundToDouble() ? a.toStringAsFixed(0) : a.toStringAsFixed(2)} USDT';
}

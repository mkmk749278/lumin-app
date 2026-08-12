/// Pulse — the delivered-signal book as a calendar month.
///
/// Added 2026-08-11 on the owner's direction: *"keep that month card in main
/// pulse page"*. It sits beside the summary card rather than inside it,
/// because the two answer different questions over **different periods** — the
/// summary card is a rolling 7/30/90-day window, this is one calendar month —
/// and folding them into one card with a toggle would put two periods behind
/// one control, which is the confusion the month mode exists to remove.
///
/// Read-only here. Tapping opens the full track record, where a day can be
/// selected and its individual signals read.
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
  const TrackRecordMonthCard({super.key, required this.window, this.repo});

  /// The rolling-window book from the Pulse bundle. Used only to decide
  /// whether there is a record worth showing at all, and to hand the page a
  /// starting window — never for the calendar's own numbers, which come from
  /// a month fetch.
  final TrackRecord window;

  final LuminRepository? repo;

  @override
  State<TrackRecordMonthCard> createState() => _TrackRecordMonthCardState();
}

class _TrackRecordMonthCardState extends State<TrackRecordMonthCard> {
  late String _month = monthOf(DateTime.now().toUtc());
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
              earliestDate: _data.earliestDate.isNotEmpty
                  ? _data.earliestDate
                  : widget.window.earliestDate,
              compact: true,
            ),
            const SizedBox(height: LuminSpacing.sm),
            Text(
              // The size is named here too. A grid of dollar figures whose
              // size the reader cannot see is an assumption wearing a
              // measurement's clothes, on every one of its cells.
              'Each day: every signal that closed, at '
              '${_usdt(_data.month == _month ? _data.amountUsdt : widget.window.amountUsdt)} '
              'each with fees charged. UTC.',
              style: const TextStyle(
                  color: LuminColors.textMuted, fontSize: 10, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  static String _usdt(double a) =>
      '${a == a.roundToDouble() ? a.toStringAsFixed(0) : a.toStringAsFixed(2)} USDT';
}

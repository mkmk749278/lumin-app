/// A real calendar month of the delivered-signal book.
///
/// **A month, not thirty days** (owner, 2026-08-11: *"keep original month as
/// month, week as week"*). The first cut of this grid rolled over whatever the
/// period chips had selected — 12 Jul → 11 Aug, straddling two months and
/// starting mid-week — which made one control answer two questions and meant a
/// "month" on screen was never the month a reader means by the word.
///
/// The month is fetched as a month, and that buys something beyond tidiness.
/// Every day of it was asked for, so a day missing from the answer means
/// **nothing closed** rather than **outside the window we happened to fetch**.
/// Those are different facts, and only now can the grid honestly draw the
/// first: a `—` in a cell. Under the rolling grid that character would have
/// been a guess.
///
/// Which is also why it reads `—` and never `0.00`. For an exchange a zero day
/// is true — you traded nothing, so you made nothing. Here `0.00` would assert
/// that signals closed and netted flat, and the bar chart beside it cannot draw
/// the distinction at all: it simply omits the day.
///
/// The stepper is bounded by the engine's `earliest_date`. Paging past the
/// beginning of the record would show empty months a reader cannot tell from
/// "we never traded then" — a blank with no cause, at a control.
import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../shared/tokens.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// `2026-08` → `August 2026`. Returns the input unchanged when it is not a
/// month this understands — a raw string is ugly but true.
String monthLabel(String ym) {
  final p = ym.split('-');
  if (p.length != 2) return ym;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (y == null || m == null || m < 1 || m > 12) return ym;
  return '${_monthNames[m - 1]} $y';
}

/// `2026-08` → `2026-07` (or forward). Returns the input on a bad key.
String shiftMonth(String ym, int by) {
  final p = ym.split('-');
  if (p.length != 2) return ym;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (y == null || m == null || m < 1 || m > 12) return ym;
  final zero = y * 12 + (m - 1) + by;
  return '${(zero ~/ 12).toString().padLeft(4, '0')}-'
      '${(zero % 12 + 1).toString().padLeft(2, '0')}';
}

String monthOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// A month grid over one [TrackRecord] fetched with `month=`.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.record,
    required this.loading,
    this.selected,
    this.onSelectDay,
    this.onStep,
    this.earliestDate = '',
    this.compact = false,
    this.today,
  });

  /// `YYYY-MM` the grid is drawing.
  final String month;

  /// The book for that month. May be for a *different* month while a step is
  /// in flight — the grid keys its cells off [month], never off the payload,
  /// so a slow fetch cannot paint August's numbers under July's heading.
  final TrackRecord record;

  final bool loading;
  final String? selected;
  final ValueChanged<String>? onSelectDay;
  final ValueChanged<String>? onStep;

  /// Oldest close in the whole record, from the engine. Bounds the stepper.
  final String earliestDate;

  /// Pulse renders a tighter grid than the full page.
  final bool compact;

  /// "Now", in UTC. Defaults to the clock.
  ///
  /// A parameter because a calendar that cannot be told what day it is cannot
  /// be tested at a month boundary — which is exactly where calendars break:
  /// the lead-in offset, the future-day cells, and whether the forward stepper
  /// is at its stop all turn on it.
  final DateTime? today;

  bool get _canStepBack {
    if (earliestDate.length < 7) return true;
    return shiftMonth(month, -1).compareTo(earliestDate.substring(0, 7)) >= 0;
  }

  DateTime get _now => today ?? DateTime.now().toUtc();

  bool get _canStepForward => month.compareTo(monthOf(_now)) < 0;

  @override
  Widget build(BuildContext context) {
    final parts = month.split('-');
    final year = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final mon = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (year == null || mon == null || mon < 1 || mon > 12) {
      return const SizedBox.shrink();
    }

    // The payload is only trusted to fill cells it agrees about. A step in
    // flight leaves last month's rows in hand, and painting them under this
    // heading is the "two surfaces, one name" defect at the speed of a tap.
    final stale = record.month.isNotEmpty && record.month != month;
    final byDate = stale
        ? const <String, TrackRecordDay>{}
        : {for (final i in record.items) i.date: i};

    final first = DateTime.utc(year, mon, 1);
    final next = DateTime.utc(mon == 12 ? year + 1 : year, mon == 12 ? 1 : mon + 1, 1);
    final daysInMonth = next.difference(first).inDays;
    // Monday-aligned, so a week on screen is a calendar week.
    final lead = first.weekday - 1;
    final weeks = ((lead + daysInMonth) / 7).ceil();
    final today = _now;
    final cellHeight = compact ? 34.0 : 42.0;

    return Column(
      key: const ValueKey('month-calendar'),
      children: [
        _header(),
        const SizedBox(height: LuminSpacing.sm),
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
                      fontWeight: FontWeight.w600,
                    ),
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
                      dayNumber: w * 7 + dow - lead + 1,
                      year: year,
                      month: mon,
                      daysInMonth: daysInMonth,
                      byDate: byDate,
                      today: today,
                      height: cellHeight,
                      stale: stale || loading,
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

  Widget _header() => Row(
        children: [
          _StepButton(
            icon: Icons.chevron_left,
            enabled: _canStepBack && onStep != null,
            onTap: () => onStep?.call(shiftMonth(month, -1)),
            // Named so the reason a control is dead is readable rather than
            // guessed at.
            tooltip: _canStepBack
                ? 'Previous month'
                : 'The record starts here',
          ),
          Expanded(
            child: Center(
              child: Text(
                monthLabel(month),
                style: const TextStyle(
                  color: LuminColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.chevron_right,
            enabled: _canStepForward && onStep != null,
            onTap: () => onStep?.call(shiftMonth(month, 1)),
            tooltip: _canStepForward ? 'Next month' : 'This is the current month',
          ),
        ],
      );

  Widget _cell({
    required int dayNumber,
    required int year,
    required int month,
    required int daysInMonth,
    required Map<String, TrackRecordDay> byDate,
    required DateTime today,
    required double height,
    required bool stale,
  }) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return SizedBox(height: height);
    }
    final day = DateTime.utc(year, month, dayNumber);
    final iso = '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${dayNumber.toString().padLeft(2, '0')}';
    // A day that has not happened yet is not a quiet day. It gets no card at
    // all, exactly as an exchange's calendar leaves the rest of the month bare.
    final future = day.isAfter(DateTime.utc(today.year, today.month, today.day));
    if (future) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            '$dayNumber',
            style: const TextStyle(
                color: LuminColors.textMuted, fontSize: 10),
          ),
        ),
      );
    }

    final entry = byDate[iso];
    final net = entry?.netUsd;
    final isSel = iso == selected;
    final tint = (net == null || stale)
        ? Colors.transparent
        : (net >= 0 ? LuminColors.success : LuminColors.loss)
            .withOpacity(isSel ? 0.30 : 0.14);

    return GestureDetector(
      onTap: (entry == null || onSelectDay == null || stale)
          ? null
          : () => onSelectDay!(iso),
      child: Container(
        height: height,
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
              '$dayNumber',
              style: TextStyle(
                color: entry == null
                    ? LuminColors.textMuted
                    : LuminColors.textPrimary,
                fontSize: compact ? 9.5 : 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              // While a step is in flight the cells hold no claim at all —
              // neither this month's numbers nor last month's.
              stale
                  ? '·'
                  : net == null
                      ? '—'
                      : (net >= 0 ? '+' : '-') + net.abs().toStringAsFixed(1),
              style: TextStyle(
                color: (net == null || stale)
                    ? LuminColors.textMuted
                    : (net >= 0 ? LuminColors.success : LuminColors.loss),
                fontSize: compact ? 8.5 : 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Icon(
              icon,
              size: 18,
              color: enabled
                  ? LuminColors.textSecondary
                  // Dimmed rather than hidden: a control that vanishes at the
                  // edge of the record leaves the reader wondering whether it
                  // was ever there.
                  : LuminColors.textMuted.withOpacity(0.3),
            ),
          ),
        ),
      );
}

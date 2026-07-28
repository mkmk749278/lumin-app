/// The caption shown under the chart's SAR chip — deliberately its own module.
///
/// Added 2026-07-28 with the Parabolic SAR chart study. This string is not
/// decoration, it is the boundary between what the chart draws and what the
/// engine actually does, and it exists because two claims would otherwise be
/// easy for a user to infer and both are false:
///
/// 1. **"Lumin exits on a SAR flip."** It does not. The engine's SAR exit arm
///    (`@SARBASE` / `@SAREXIT`, `src/sar_exit_shadow.py` in `360-v2`) is a dark
///    shadow measurement — it stamps counterfactuals and has never governed a
///    live position. Live exits run on the signal's SL/TP and the FSM. A user
///    who sees SAR flip against an open Lumin signal must not sit waiting for
///    an exit that is not coming.
/// 2. **"SAR agreeing with a signal means it's a better signal."** The measured
///    answer as of 2026-07-28 is that it does not: over 270 resolved rows the
///    "SAR agreed at entry" cohort netted **+0.007%/trade** against +0.437% for
///    the opposed cohort (`ACTIVE_CONTEXT.md`, Session 88 — and even that split
///    is confounded by re-detection, #816). There is no version of an
///    "SAR agrees ✓" badge on a signal that the data supports today, so the app
///    ships the indicator and no verdict.
///
/// The timeframe half of the caption is the *alignment* the study needs: the
/// chart draws SAR on whatever timeframe is on screen (as an indicator must),
/// while the engine's study fixes 15m. On any other timeframe the dots are a
/// different series from the one the research measured, and the caption says so
/// rather than letting the user assume they are looking at the engine's view.
library;

import 'indicators.dart';

/// Caption for the SAR chip, given the timeframe currently on screen.
String sarCaption(String tf) {
  final tfPart = tf == kSarStudyTf
      ? '$kSarStudyTf — the timeframe our signal research uses'
      : 'drawn on $tf; our signal research runs on $kSarStudyTf, '
          'so flips here will not match it';
  return 'Parabolic SAR $kSarStep/$kSarMaxStep · $tfPart. '
      "Chart study only — Lumin exits still run on the signal's SL/TP.";
}

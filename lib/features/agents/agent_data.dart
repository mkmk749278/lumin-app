import 'package:flutter/material.dart';

class Agent {
  const Agent({required this.id, required this.name, required this.tagline, required this.specialty, required this.icon});
  final String id;
  final String name;
  final String tagline;
  final String specialty;
  final IconData icon;
}

const List<Agent> kAgents = [
  Agent(id: 'SR_FLIP_RETEST', name: 'The Architect', tagline: 'Structural levels & flip retests',
    specialty: 'Watches support / resistance levels that flip and retest cleanly. Enters on the retest with structural confluence — the highest-quality setup family in the engine. Currently the top emitter.',
    icon: Icons.architecture_outlined),
  Agent(id: 'LIQUIDITY_SWEEP_REVERSAL', name: 'The Counter-Puncher', tagline: 'Reversal hunter after liquidity grabs',
    specialty: 'Fades the move when price sweeps liquidity (stop-runs above swing highs / below swing lows) and reverses. Counter-trend by design — thrives on traps set against the obvious move.',
    icon: Icons.swap_horiz_outlined),
  Agent(id: 'FAILED_AUCTION_RECLAIM', name: 'The Reclaimer', tagline: 'Trapped traders → reversal',
    specialty: 'Spots failed auction attempts (price breaks a level, fails to follow through, reclaims back). Trapped breakout traders fuel the reversal — clean R:R when the pattern triggers.',
    icon: Icons.replay_outlined),
  Agent(id: 'QUIET_COMPRESSION_BREAK', name: 'The Coil Hunter', tagline: 'Pre-volatility expansion',
    specialty: 'Identifies tight Bollinger-band compression in QUIET regime, then enters on the first directional break. The market\'s spring releasing — high R:R, low fire rate.',
    icon: Icons.compress_outlined),
  Agent(id: 'VOLUME_SURGE_BREAKOUT', name: 'The Tracker', tagline: 'Momentum-confirmed breakouts',
    specialty: 'Catches breakouts validated by a strong volume spike. Filters out fakeouts that lack participation. Built for trending markets where breakout follow-through matters.',
    icon: Icons.trending_up_outlined),
  Agent(id: 'BREAKDOWN_SHORT', name: 'The Crusher', tagline: 'Bearish twin of breakout',
    specialty: 'The short-side mirror of The Tracker. Hunts breakdowns through support with volume confirmation. Rare in current markets but high-conviction when it fires.',
    icon: Icons.trending_down_outlined),
  Agent(id: 'FUNDING_EXTREME_SIGNAL', name: 'The Contrarian', tagline: 'Funding-rate squeeze plays',
    specialty: 'Reads perpetual funding rates. When one side gets crowded (extreme funding), takes the other side — squeezing trapped longs / shorts. Pure order-flow contrarian.',
    icon: Icons.percent_outlined),
  Agent(id: 'WHALE_MOMENTUM', name: 'The Whale Hunter', tagline: 'Large-order chaser',
    specialty: 'Detects whale-sized order flow imbalances and rides the momentum until the impulse exhausts. Tape-driven — direction comes from real-time tick data, not technicals.',
    icon: Icons.waves_outlined),
  Agent(id: 'LIQUIDATION_REVERSAL', name: 'The Cascade Catcher', tagline: 'Post-liquidation reversal',
    specialty: 'Waits for liquidation cascades to finish, then enters the snapback. Forced selling exhaustion creates clean reversals — but cascades are rare, so this agent is patient.',
    icon: Icons.bolt_outlined),
  Agent(id: 'CONTINUATION_LIQUIDITY_SWEEP', name: 'The Continuation Specialist', tagline: 'Trend-resume after pullback sweep',
    specialty: 'Finds liquidity sweeps that occur DURING a trend (mid-trend stop runs that reset positioning). Enters on the trend resumption — cleaner than fresh-trend entries.',
    icon: Icons.timeline_outlined),
  Agent(id: 'DIVERGENCE_CONTINUATION', name: 'The Divergence Reader', tagline: 'CVD / price divergence plays',
    specialty: 'Reads cumulative volume delta against price action. When CVD diverges from price during a continuation, signals a high-prob move in the direction of the underlying flow.',
    icon: Icons.show_chart_outlined),
  Agent(id: 'TREND_PULLBACK_EMA', name: 'The Pullback Sniper', tagline: 'Pullback entries to EMAs in trend',
    specialty: 'Waits for clean pullbacks to the EMA stack during a confirmed trend, then enters on the reclaim. Classic trend-following with tight invalidation if the EMA fails.',
    icon: Icons.timeline),
  Agent(id: 'POST_DISPLACEMENT_CONTINUATION', name: 'The Aftermath Trader', tagline: 'Post-impulse continuation',
    specialty: 'After a strong directional displacement, waits for consolidation and enters on re-acceleration. Captures the back half of institutional moves.',
    icon: Icons.airline_seat_recline_normal_outlined),
  Agent(id: 'OPENING_RANGE_BREAKOUT', name: 'The Range Breaker', tagline: 'Session open-range breakouts',
    specialty: 'Tracks the opening range of major sessions and enters on the directional break with volume confirmation. Currently disabled pending session-anchored range logic rebuild.',
    icon: Icons.start_outlined),
  Agent(id: 'MA_CROSS_TREND_SHIFT', name: 'The Trend Shifter', tagline: 'EMA50 / EMA200 crossover regime change',
    specialty: 'Watches the slow EMA stack for golden / death crosses on 4h. When EMA50 crosses EMA200 with confirming volume and structure, signals a regime shift — rare but high-conviction. The 15th evaluator, added 2026-05-06.',
    icon: Icons.swap_calls_outlined),
];

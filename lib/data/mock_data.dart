/// Mock data — sample engine state, signals, and positions.
///
/// Replaced by repository implementations once the FastAPI backend
/// lands.  Until then the UI consumes these constants so users get a
/// real-looking app instead of "Coming soon" placeholders.  Each tab's
/// page passes ``isPreview: true`` to the preview banner so the data
/// is clearly marked as sample.
import 'package:flutter/material.dart';

class MockEngineSnapshot {
  const MockEngineSnapshot({
    required this.status,
    required this.regime,
    required this.regimePctTrending,
    required this.todayPnlUsd,
    required this.todayPnlPct,
    required this.dailyLossBudgetUsd,
    required this.dailyLossUsedUsd,
    required this.openPositions,
    required this.signalsToday,
    required this.uptime,
  });

  final String status;
  final String regime;
  final double regimePctTrending;
  final double todayPnlUsd;
  final double todayPnlPct;
  final double dailyLossBudgetUsd;
  final double dailyLossUsedUsd;
  final int openPositions;
  final int signalsToday;
  final String uptime;
}

const mockEngine = MockEngineSnapshot(
  status: 'Healthy',
  regime: 'TRENDING_UP',
  regimePctTrending: 54.4,
  todayPnlUsd: 12.84,
  todayPnlPct: 1.28,
  dailyLossBudgetUsd: 30.00,
  dailyLossUsedUsd: 0.00,
  openPositions: 1,
  signalsToday: 3,
  uptime: '2d 14h',
);

class MockSignal {
  const MockSignal({
    required this.id,
    required this.symbol,
    required this.direction,
    required this.setupName,
    required this.agentName,
    required this.entry,
    required this.sl,
    required this.tp1,
    required this.tp2,
    required this.tp3,
    required this.confidence,
    required this.tier,
    required this.status,
    required this.pnlPct,
    required this.minutesAgo,
    this.preTpTriggerPrice = 0.0,
    this.preTpThresholdPct = 0.0,
    this.preTpHit = false,
  });

  final String id;
  final String symbol;
  final String direction; // LONG / SHORT
  final String setupName;
  final String agentName;
  final double entry;
  final double sl;
  final double tp1;
  final double tp2;
  final double tp3;
  final double confidence;
  final String tier; // A+ / B
  final String status; // ACTIVE / TP1_HIT / TP2_HIT / TP3_HIT / SL_HIT / INVALIDATED
  final double pnlPct;
  final int minutesAgo;
  // Pre-TP grab — Phase A target price + threshold % stamped at dispatch.
  // Centerpiece of the scalp signal display: clears trigger → SL ratchets to
  // breakeven, full TP ladder still open.  Doctrine update 2026-05-07:
  // TP3 dropped from dispatch display, Pre-TP promoted in its place.
  final double preTpTriggerPrice;
  final double preTpThresholdPct;
  final bool preTpHit;
}

const List<MockSignal> mockSignals = [
  MockSignal(
    id: 'SIG-2841',
    symbol: 'ETHUSDT',
    direction: 'LONG',
    setupName: 'SR FLIP RETEST',
    agentName: 'The Architect',
    entry: 2329.0,
    sl: 2310.0,
    tp1: 2351.0,
    tp2: 2360.0,
    tp3: 2394.0,
    confidence: 83.5,
    tier: 'A+',
    status: 'ACTIVE',
    pnlPct: 0.42,
    minutesAgo: 18,
  ),
  MockSignal(
    id: 'SIG-2840',
    symbol: 'BTCUSDT',
    direction: 'SHORT',
    setupName: 'LIQUIDITY SWEEP REVERSAL',
    agentName: 'The Counter-Puncher',
    entry: 78240.0,
    sl: 78850.0,
    tp1: 77800.0,
    tp2: 77400.0,
    tp3: 76900.0,
    confidence: 71.2,
    tier: 'B',
    status: 'TP1_HIT',
    pnlPct: 0.56,
    minutesAgo: 142,
  ),
  MockSignal(
    id: 'SIG-2839',
    symbol: 'SOLUSDT',
    direction: 'LONG',
    setupName: 'FAILED AUCTION RECLAIM',
    agentName: 'The Reclaimer',
    entry: 142.85,
    sl: 141.20,
    tp1: 144.50,
    tp2: 145.80,
    tp3: 148.00,
    confidence: 68.4,
    tier: 'B',
    status: 'INVALIDATED',
    pnlPct: -0.04,
    minutesAgo: 421,
  ),
  MockSignal(
    id: 'SIG-2838',
    symbol: 'BNBUSDT',
    direction: 'LONG',
    setupName: 'QUIET COMPRESSION BREAK',
    agentName: 'The Coil Hunter',
    entry: 612.40,
    sl: 607.50,
    tp1: 618.20,
    tp2: 622.10,
    tp3: 628.50,
    confidence: 82.5,
    tier: 'A+',
    status: 'TP3_HIT',
    pnlPct: 2.78,
    minutesAgo: 880,
  ),
];

class MockPosition {
  const MockPosition({
    required this.symbol,
    required this.direction,
    required this.entry,
    required this.currentPrice,
    required this.qty,
    required this.pnlPct,
    required this.pnlUsd,
    required this.minutesOpen,
  });

  final String symbol;
  final String direction;
  final double entry;
  final double currentPrice;
  final double qty;
  final double pnlPct;
  final double pnlUsd;
  final int minutesOpen;
}

const List<MockPosition> mockPositions = [
  MockPosition(
    symbol: 'ETHUSDT',
    direction: 'LONG',
    entry: 2329.0,
    currentPrice: 2338.80,
    qty: 0.0429,
    pnlPct: 0.42,
    pnlUsd: 0.42,
    minutesOpen: 18,
  ),
];

class MockActivityEvent {
  const MockActivityEvent({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.minutesAgo,
    required this.color,
  });

  final String kind;
  final String title;
  final String subtitle;
  final int minutesAgo;
  final Color color;
}

const mockActivity = <MockActivityEvent>[
  MockActivityEvent(
    kind: 'OPEN',
    title: 'ETHUSDT LONG opened',
    subtitle: 'qty 0.0429 @ 2,329.00 — The Architect',
    minutesAgo: 18,
    color: Color(0xFF7BD3F7),
  ),
  MockActivityEvent(
    kind: 'TP1',
    title: 'BTCUSDT SHORT — TP1 hit',
    subtitle: '+0.56% on 33% partial — SL → breakeven',
    minutesAgo: 96,
    color: Color(0xFF4ADE80),
  ),
  MockActivityEvent(
    kind: 'OPEN',
    title: 'BTCUSDT SHORT opened',
    subtitle: 'qty 0.0009 @ 78,240.00 — The Counter-Puncher',
    minutesAgo: 142,
    color: Color(0xFF7BD3F7),
  ),
  MockActivityEvent(
    kind: 'INVAL',
    title: 'SOLUSDT LONG invalidated',
    subtitle: 'momentum_loss — closed at 142.79 (-0.04%)',
    minutesAgo: 421,
    color: Color(0xFF94A3B8),
  ),
  MockActivityEvent(
    kind: 'TP3',
    title: 'BNBUSDT LONG — TP3 hit',
    subtitle: '+2.78% — full close, signal lifecycle complete',
    minutesAgo: 880,
    color: Color(0xFF4ADE80),
  ),
];

# Market Charts tab — design note

**Status:** v1 shipped (#108–#111); Phase-2 + v1 gap-closure shipped 2026-07-02
(price-axis precision fix, live-signal badges/overlay on the tab, EMA/MA/RSI
indicators, older-history pagination, live overlay refresh, lifecycle pause,
crosshair OHLC legend — see §16)
**Branch (impl):** `feat/market-charts-tab`
**Companion (engine):** none required for v1 — overlay data already flows to the app
**Owner directive:** the Agents tab isn't earning its slot; repurpose it for live market charts.

**Owner decisions (2026-06-29):**
- Agents → demoted to a new **INSIGHTS** Menu section (kept, not deleted).
- Charts tab = **the full Binance futures pair list** (every listed perp), searchable; tap a pair → chart. (Not a curated movers/live-signal list — show everything.)
- **Two entry points into the chart screen:** (1) Charts tab pair list → market chart; (2) Signals tab → tap a signal → detail sheet → **"Open chart"** → same chart with our signal set (entry/SL/TP/BE) overlaid on the full chart.

---

## 1. Goal

Replace the **Agents** bottom-nav tab with a **Charts** tab: a markets browser →
live candlestick chart with **our own signal levels drawn on it** (entry / SL /
TP1·2·3 / break-even + a fired/closed marker). The differentiator vs any generic
charting app is that a subscriber sees *Lumin's* trade plan on a real, live chart
and watches it play out — the single biggest "this is legit" moment for a signals
product.

Honest framing: this is a **trust / retention** feature, not a signal-quality one.
It does not make signals more profitable; it makes subscribers believe and stay
(the retention→revenue link in the chain).

## 2. Scope

**In (v1):**
- Charts tab replacing Agents (nav index 2); Agents demoted to a Menu row (INSIGHTS).
- **Full Binance futures pair list** (all listed perps from `exchangeInfo`),
  searchable; tap → chart. Live-signal pairs badged + floated to top, but every
  pair is present.
- Shared **chart screen** `ChartPage(symbol, {signal})` reached from two places:
  the pair list (no overlay) and the **signal detail sheet → "Open chart"** (with
  that signal's overlay).
- Candlestick + volume via **TradingView Lightweight Charts™** in a WebView.
- History from Binance public `/fapi/v1/klines`; live from Binance kline WS.
- Timeframe chips: 1m / 5m / 15m / 1h / 4h.
- Overlay (when a signal is passed in, or the pair has a live Lumin signal): entry /
  SL / TP1·2·3 / BE price lines + entry/closed markers.

**Out (later phases):**
- Client-side indicators (EMA stack, RSI, MACD) — Phase 2.
- Sparkline thumbnails in the Signals list — Phase 2.
- User drawing tools (trendlines, fib) — **Phase 3 only if demanded**; requires
  TradingView *Advanced Charts*, which is **not free behind a paywall** (commercial
  licence ~$1.5–3k/mo). Explicitly deferred.

## 3. Navigation change

`lib/app/nav_shell.dart`:
- `_destinations[2]`: icon `Icons.candlestick_chart_outlined` / `Icons.candlestick_chart`, label **"Charts"**.
- `_tabAt(2)`: return `ChartsPage(key: _tabKeys[2])`.
- Keep the existing lazy-mount (`_visited`) + `ForegroundRefreshable` plumbing —
  `ChartsPage` implements `refreshFromForeground()` (re-pull klines, reopen WS).

`lib/features/settings/settings_page.dart`:
- New **INSIGHTS** section with row "AI agents" → `_push(context, const AgentsPage())`.
  Agents code is **kept**, just demoted — the 713 LOC of per-agent stats stays
  accessible, off the prime tab.

`lib/features/signals/signals_page.dart` (`_SignalDetailSheet`, already exists):
- Add an **"Open chart"** action → `Navigator.push` to `ChartPage(symbol: sig.symbol,
  signal: sig)`. The sheet already has the full signal; the overlay is built from it.

## 4. Architecture (data path)

```
Binance public REST  /fapi/v1/klines?symbol=&interval=&limit=1000   → history   ($0, no key)
Binance public WS    wss://fstream.binance.com/ws/<sym>@kline_<tf>  → live bar   ($0, no key)
        │   app → Binance directly (same pattern as binance_client.dart today)
        ▼
   WebView (assets/chart/index.html) running Lightweight Charts
        ▲
        │   overlay payload from the app's existing Lumin signal data
        └─ entry / sl / tp1 / tp2 / tp3 / be price lines + markers
```

No data is served by our engine. Binance public klines/WS need no API key and
flow device→Binance, so there is **no egress/compute cost on our infra** and **no
per-user fan-out** — each device opens its own single WS for the visible chart.

## 5. Charting tech + licensing

**TradingView Lightweight Charts™** (vendored JS, ~50 KB) in `webview_flutter`.
- Licence: **Apache-2.0** — free, commercial use OK *including behind our paywall*.
  Obligation: a visible attribution ("Charts by TradingView", link to tradingview.com)
  rendered in the chart footer. We will include it.
- Not chosen: *Advanced Charts* (drawing tools / full indicators) — free only for
  **public, non-paywalled** use; our paid app would require a commercial licence.
  Deferred to Phase 3 pending real demand.
- Not chosen: native Flutter libs (`fl_chart` weak candles; `syncfusion` community
  licence is revenue/seat-gated; `k_chart` variable upkeep) — none give the genuine
  TradingView look, and WebView keeps us on TradingView's own renderer.

## 6. Dependencies to add

- `webview_flutter: ^4.x` (+ platform setup already covered by Flutter).
- Vendored asset: `assets/chart/lightweight-charts.standalone.production.js`
  (pinned version, checked into the repo — no CDN at runtime, works offline-first
  for the chart shell) + `assets/chart/index.html` + a tiny `chart_bridge.js`.
- `pubspec.yaml`: register the `assets/chart/` directory.

## 7. File layout

```
lib/features/charts/
  charts_page.dart          # tab root: pair selector + chart host + TF chips
  chart_controller.dart     # owns klines fetch, WS lifecycle, overlay state
  chart_webview.dart        # WebView host + JS bridge (Dart side)
  pair_picker.dart          # searchable list (live-signal pairs + movers)
  models/
    candle.dart             # OHLCV
    chart_overlay.dart      # the overlay payload model (see §9)
lib/data/
  binance_client.dart       # EXTEND: klines() REST + klineSocket() WS
assets/chart/
  index.html  chart_bridge.js  lightweight-charts.standalone.production.js
```

## 8. WebView ↔ Flutter bridge contract

One Flutter→JS direction via `controller.runJavaScript(...)`, one JS→Flutter via a
single `JavaScriptChannel('LuminChart')`. All payloads are JSON strings.

**Flutter → JS (commands):**

| Command | Payload | Effect |
|---|---|---|
| `setCandles` | `{tf, candles:[{t,o,h,l,c,v}]}` | seed/replace the series (history load or TF switch) |
| `updateCandle` | `{t,o,h,l,c,v}` | upsert the latest live bar (from WS) |
| `setOverlay` | `ChartOverlay` (§9) | draw/replace our signal price-lines + markers |
| `clearOverlay` | `{}` | remove overlay (pair has no live signal) |
| `setTheme` | `{dark:bool}` | match app theme |

**JS → Flutter (events on `LuminChart` channel):**

| Event | Payload | Use |
|---|---|---|
| `ready` | `{}` | chart initialised → Dart sends first `setCandles` |
| `visibleRangeChanged` | `{from,to}` | (Phase 2) lazy-load older history |
| `error` | `{message}` | surface a graceful fallback state |

Lifecycle: `chart_controller` opens the WS only while the Charts tab is foreground
and visible; `refreshFromForeground()` + tab-deselect/dispose close it. WS
reconnect with backoff; on failure the chart still shows REST history (degraded,
not blank).

## 9. Overlay data contract (`ChartOverlay`)

Built entirely from the **Lumin signal object the app already receives** (no new
engine endpoint). One overlay = one signal on this symbol.

```jsonc
{
  "signal_id": "MVRTP-…",
  "side": "LONG" | "SHORT",
  "entry": 0.10799,
  "sl": 0.11122,          // current stop (moves to entry once BE@+1% arms — reflects live state)
  "be_armed": true,        // whether the +1% break-even shift has fired
  "tp1": 0.10428,
  "tp2": 0.10143,          // may be null under TP1-full default
  "tp3": 0.09830,          // may be null
  "opened_at_ms": 1719640000000,
  "status": "ACTIVE" | "TP1_HIT" | "SL_HIT" | "CLOSED" | "INVALIDATED",
  "markers": [             // optional lifecycle markers
    {"t": 1719640000, "kind": "entry"},
    {"t": 1719641800, "kind": "tp1"}
  ]
}
```

Rendering: horizontal price lines (entry = neutral, SL = red, TP = green, BE =
amber when armed); markers at their candle time. Lines update live via `setOverlay`
when the signal's stop moves (BE shift) or status changes.

## 10. Pair list (Charts tab)

- **Full universe:** every listed USDT-M perp from `binance_client.exchangeInfo`
  (already available) — the tab shows *all* pairs, searchable.
- **24h context per row:** `/fapi/v1/ticker/24hr` (one batched call, free, no key)
  for last price + %change, so each row reads like a market list.
- **Live-signal pairs** (from the app's existing signals data) are badged and
  floated to the top, but the list is the whole board, not a curated subset.
- Tap a row → `ChartPage(symbol)` (no overlay unless that symbol has a live signal).

## 11. Performance / limits

- Lightweight Charts handles 100k+ points on-canvas; we load ≤1000 bars/TF.
- One WebView, one chart, one WS at a time → low memory/battery. No charts in
  scrolling lists (Phase 2 sparklines will be native, not WebView).
- Binance klines REST ≤1500 bars/req; pagination deferred to Phase 2.
- Pause WS on background (battery + mobile data).

## 12. Cost

- Lightweight Charts: **$0** (Apache-2.0) + attribution link.
- Binance klines/WS: **$0**, no key, no egress on us.
- Net cost = engineering time + maintaining the vendored JS pin. No recurring fees.

## 13. Testing

- Dart unit: `binance_client` klines parse + WS frame→candle mapping; `ChartOverlay`
  build-from-signal mapping; controller WS lifecycle (open on foreground, close on
  background/dispose).
- Widget: `ChartsPage` renders pair picker + WebView host; TF chip switches series.
- Manual on-device: history loads, live bar ticks, overlay lines match the signal,
  theme + attribution visible, backgrounding closes the WS.

## 14. Risks / open questions

- **WebView bridge robustness** — main implementation risk; mitigated by the small,
  explicit message contract (§8) and REST-only degraded mode.
- **Binance WS rate limits on aggressive pair-switching** — debounce pair/TF changes
  before (re)subscribing.
- **Attribution placement** — must stay visible to satisfy the Apache-2.0/TradingView
  terms; a chart-footer "Charts by TradingView" line.
- ~~Default pair~~ — resolved: Charts tab is a full list, the user picks; no default.
- ~~Agents Menu placement~~ — resolved: new **INSIGHTS** section.

## 15. Phasing

1. **v1 (this design):** Charts tab, pair selector, live candlestick + our overlay,
   Agents → Menu. **Shipped** (#108–#111; live bar via 2s REST poll, not WS — #111).
2. **v2:** client-side indicators (MA stack / RSI / volume) that *explain* a signal;
   native sparklines in the Signals list; older-history pagination. **Shipped
   2026-07-02 except sparklines** (deferred — they change the owner-approved
   signal-card layout, an owner design call; and each visible row costs a
   device→Binance kline fetch that wants its own caching design).
3. **v3 (only on demand):** Advanced Charts + user drawing tools — re-evaluate the
   commercial-licence cost at that point.

## 16. Phase-2 + gap-closure changelog (2026-07-02)

Audit of the shipped v1 found four real gaps; all fixed, plus the Phase-2
features, in one change set:

**Fixes (v1 gaps):**
- **Price-axis precision** — Lightweight Charts defaults to 2 decimals, which
  flattened every sub-dollar perp (a 0.107 alt rendered in 0.01 ≈ 9% steps and
  the overlay's entry/SL/TP axis labels collapsed together). Precision is now
  derived from the symbol's price magnitude (`chartPrecisionFor`, ~5 sig figs,
  clamped [2,8]) and applied via `setCandles`.
- **Live-signal pairs on the Charts tab (§10)** — was never wired. The tab now
  watches the SWR-cached open-signals stream (dedups with the Signals tab's own
  traffic), badges live-signal pairs (LONG/SHORT pill), floats them to the top,
  and opens their chart **with** the signal overlay.
- **Poll didn't pause on background (§11)** — the 2s kline poll now stops on
  app pause/inactive and resumes (with an immediate catch-up tick) on resume
  via `WidgetsBindingObserver`.
- **Static overlay** — the overlay was drawn once at load; §9 promised live
  updates. The signal is now re-read every 30s from the same SWR signals list,
  so the BE shift moves the stop line to entry and status changes propagate.
  Redraws only fire when the overlay payload actually changed.
- **TF-switch race** — a load-generation counter discards stale async
  completions; the poll is cancelled during a reload so a wrong-TF bar can't
  merge into the new series.

**Phase-2 features:**
- **Indicators**, computed Dart-side (`indicators.dart`, unit-tested) and
  rendered as line series: **EMA 21/50** (the engine's canonical
  pullback/trend EMAs), **SMA 7/25/99** (the owner's mover-chart MA stack),
  **RSI 14** (bottom band; swaps with the volume histogram — one bottom band
  on a phone). Toggles persist across sessions (`shared_preferences`). Live
  ticks push only each line's newest point over the bridge.
- **Older-history pagination** — panning within ~30 bars of the oldest data
  lazy-loads another 500 bars (`endTime` paging, ≤3000 bars) with the
  viewport preserved across the data replace.
- **Crosshair OHLC legend** — top-left readout of the hovered bar's
  O/H/L/C, intrabar %change, and volume, at the derived precision.
- **Volume colouring** — histogram bars now follow candle direction.

Sparklines in the Signals list remain deferred (see §15 point 2).

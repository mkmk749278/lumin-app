# Lumin 2.0 — implementation plan

Source: the owner's handoff *"Lumin 2.0 — Institutional Redesign"* (2026-11-25),
checked against the three repos and the analyst ledger before anything was
planned. This file is the plan of record; each phase ships as its own PR
pair (engine + app) and updates the status table at the bottom.

## 1. Decisions (owner, 2026-11-25)

| Question | Answer |
|---|---|
| Where 2.0 lives | This repo, **same package id** (`org.luminapp.lumin`). Tested first, then uploaded to Play as an update of the existing listing. Not uploaded until tested. |
| Who sees analyst content | Any signed-in user of the 2.0 build. |
| Desk forecast | **Measured + stated**: the analyst's own `p_target`, labelled as its estimate, beside what its past setups actually did. No invented numbers. |
| Live execution on analyst setups | **Yes, dark-first**: built behind a default-OFF engine flag, shadow-measured, switched on only with owner sign-off. |

## 2. How 2.0 ships without touching the live app

The live app ships from `main` three ways: a sideload release the in-app
updater installs, the PWA at `app.luminapp.org`, and the AAB the owner
uploads to Play. A 2.0 screen merged to `main` naively would reach all three.

So 2.0 is a **compile-time edition**, the same mechanism as the distribution
channel (`lib/app/distribution.dart`):

```
--dart-define=LUMIN_EDITION=next     # 2.0 shell
(default)            legacy          # today's app, byte-for-byte the same screens
```

* `main` keeps building `legacy` for the release, the PWA and the AAB.
* CI also builds **`lumin-next-<run>.apk`** (same package id, same signing key)
  as a workflow artifact only — never attached to the release, never
  deployed to the web. A tester installs it over the live app; the updater is
  inert in that build so it cannot "update" itself back to legacy.
* **Launch** = one PR flipping the default to `next`, after the owner signs off
  on the test build. Then the owner uploads the AAB.
* Shared code (repository, auth, billing, execution) is not forked. 2.0 adds
  new pages and a new theme; the legacy pages stay until launch, then are
  deleted in a cleanup PR.

## 3. What the handoff assumed vs what exists

Verified 2026-11-25. These change what gets built.

| Handoff says | Reality | Plan |
|---|---|---|
| Hourly Desk Brief with regime, BTC structure, breadth, summary | The analyst submits a plan per run: `bias` (`risk_on`/`risk_off`/`neutral`/`stand_aside`) + `notes`. The engine's `analyst_snapshot.market_context` computes BTC state, 24h/7d change and **altcoin breadth vs BTC 7d**. | Brief = latest plan's bias + notes + the engine's market context. A brief older than 2h says it is old; it is never shown as "this hour". |
| `GET /v1/desk/brief` | API is `/api/...`; analyst state lives in the engine container. | `GET /api/desk` served from a Redis snapshot the engine publishes every 60s (`pair_context` pattern). No Firestore reads. |
| Thesis / invalidation / pre-mortem per setup | Ledger has `scenario`, `invalidation`, `archetype`, tranches (0.4/0.6), stop, 1–3 targets, `p_target`. **No pre-mortem field.** | Show what exists. Pre-mortem is added to the analyst's plan schema (additive, optional) in Phase 3, rendered only when present. |
| 3-outcome forecast `Target 36% · Time 34% · Stop 30%` | Only `p_target`. Calibration on the ledger: says ~41%, filled setups hit ~18% (n small). | Stated `p_target` labelled "analyst's estimate" + measured split from the walk (`filled_by_exit`, fill rate) with n on screen. |
| Post-trade review: fill, hold time, MFE/MAE, net PnL, exit | Walk records entry/exit price+time, exit reason, gross/net, MFE/MAE, `unfilled`. | Rendered as is. `not_filled` is never shown as a fill — its PnL is the market's, not the setup's. |
| Setup archetypes `Breakout Retest`, `Sweep & Reclaim`… | Analyst archetypes: `level_reclaim`, `breakout_retest`, `range_fade`, `trend_pullback`, `sweep_reversal`. Engine signals carry bot names (`The Crusher`…). | One label map; bot names removed from 2.0 surfaces. |
| "Verified net-of-fees performance" | Track record is recorded engine signals (net of 0.07%). Analyst outcomes are a **dark walk** (forward-measured, no real fills). | Two records, never pooled. The analyst's is labelled "forward-measured, not executed" until live execution exists. |
| Notification permission on splash | True: `notification_service.dart` requests it at init. | Fixed in Phase 1 (both editions). |
| Paywall `SIGNALS`/`ASSIST` wrap, "Signals stay free" contradiction, Binance-only onboarding copy, 19 specialists | All present in code. | Phase 1 (copy/layout bugs, both editions) and Phase 4 (methodology screen, 2.0). |

## 4. Rules every phase follows

* **The engine is the source of truth.** Every analyst number the app shows
  comes from the engine; the app derives nothing about outcomes.
* **Analyst setups and engine signals are two populations**, labelled
  everywhere and never summed into one figure.
* **Unknown is not a value.** An unreadable brief, stale plan or missing
  walk renders as that state, never as "no setups" or "stand aside".
* **Numbers use tabular figures**; percentages say gross or net.
* **Cost:** no new Firestore read on any path; new engine work runs on the
  snapshot writer's 60s timer, not per request.
* Legacy edition behaviour is unchanged unless the change is a bug fix that
  should reach live users too (Phase 1b), and the PR says which.

## 5. Phases

### Phase 1 — foundation (engine + app)

**1a. Engine — the desk read model** (off money path; ships normally)
* `src/desk.py`: `build(engine)` → `{brief, setups, record}`:
  * `brief`: latest plan (`bias`, `notes`, `submitted_at`, accepted count,
    setups named), `market_context` (BTC price, state, 24h/7d, breadth), and
    `freshness` (`current` ≤ 2h / `stale` / `none`).
  * `setups`: `analyst_walk.feed` rows trimmed to what the app renders.
  * `record`: per-arm summary, `analyst_split`, calibration, with n.
* Snapshot writer publishes `snapshot:desk` every 60s (TTL 300s); facade reads it.
* `GET /api/desk` and `GET /api/desk/setups/{setup_id}` for signed-in users;
  three states (`ok` / `not_reported` / `no_ledger`).
* Kill switch: runtime tunable `DESK_API_ENABLED` (default ON — display-only,
  no money path), and `read.desk` on the diag catalog so ops sees what the app sees.
* Tests: builder on a real ledger fixture, route states, a contract test
  pinning every key the app reads.

**1b. App — bug fixes for both editions** (handoff P0 list)
* Defer the notification permission until after login, with a soft prompt.
* Paywall column heads: `maxLines: 1` + `FittedBox`.
* Play Billing: timeout + retry instead of endless shimmer.
* One entitlement sentence used by Signals, Trade and Subscription.
* Onboarding names the user's exchange (Binance or CoinDCX), not Binance only.
* `AutoModeStatus.readable` (OPEN item in engine `ACTIVE_CONTEXT.md`).
* Flutter SDK installed in the session so `flutter test` + `flutter analyze` run before every push.

**1c. App — 2.0 skeleton** (`next` edition only)
* `lib/app/edition.dart` (compile-time, legacy default).
* `lib/theme/lumin_theme.dart`: obsidian tokens (`#090B10` / `#11151E` /
  `#171C28` / `#222938`), Inter + JetBrains Mono **bundled as assets** (no
  runtime font download), tabular figures, 12% tinted status pills.
* `NextNavShell` with five tabs — Desk, Setups, Markets, Execution, Account.
  Markets/Execution/Account host today's pages under the new theme until their phases.
* Repository: `fetchDesk()` / `fetchDeskSetup(id)` on both `HttpRepository` and `MockRepository`.
* CI: `next` test APK artifact.

### Phase 2 — Desk tab
* Desk Brief hero: bias pill, BTC price + state, breadth, "updated Xm ago", notes; drawer with per-timeframe state, 24h/7d, macro status (`unknown`, never "no events"), setups this plan.
* Stand-aside plans render as a brief, not an empty screen.
* Active & pending strip from the analyst feed (pending shows entry and expiry).
* Track record + signal-book heatmap reused under the new theme.
* Stale-while-revalidate cache of the last desk payload (SharedPreferences) so cold start renders instantly with an "as of" stamp.

### Phase 3 — Setups, Dossier, Markets
* Setups tab: `Active | Pending | Closed | Desk log` (desk log = every plan incl. stand-aside).
* Card: symbol · side · archetype · TF, price ladder bar (SL ← entry zone → TP1 → TP2) with live marker, one-line summary, R:R, state.
* Dossier: chart with entry tranches/SL/TPs, thesis (`scenario`), execution plan (tranches + weights), invalidation, pre-mortem (when present), stated vs measured forecast, post-trade review.
* Engine: optional `pre_mortem` in the analyst plan schema (additive).
* Engine signals in 2.0: shown under institutional archetype names, bot names removed (owner to confirm whether they stay in Setups as a second, labelled source).
* Markets: LIVE dot off the symbol line, non-ASCII tickers normalised, chart levels capped at nearest 2R + 2S + POC with an "All levels" toggle, 20px collision culling, right-axis labels; `Lumin read` sheet.

### Phase 4 — Execution and Account
* Paper-first: new accounts default to paper with $1,000.
* Auto-trade toggle never bright when blocked: amber `Paused · <reason>` from the engine's gate fields.
* History split `Executed | Skipped` with grouped skip reasons and the fix button.
* Account: Desk Methodology screen replaces the agents roster; billing screen polish.

### Phase 5 — live execution on analyst setups (dark-first, owner sign-off)
Money path. Ships with the measurement flag ON and the effect flag OFF.
* Engine: analyst-setup executor — two-tranche limit entries, stop placed with the entry (never naked), TP1 50% / runner TP2, expiry cancel; per-user opt-in; blast-radius caps unchanged.
* Shadow first: every would-be order stamped against the walk; ops panel the same day.
* App: `Assist Execute` on the dossier, visible only when the engine reports the effect flag on for that user.
* Activation only after the owner reads the shadow result.

### Phase 6 — pre-launch
* In-app review prompt after real engagement.
* Android Vitals check, `--split-per-abi` test APKs, six 1080×1920 screenshots, disclaimer typo.
* Flip the default edition to `next`; delete legacy pages in a follow-up PR; owner uploads the AAB.

## 6. Status

| Phase | State | PRs |
|---|---|---|
| 1a engine desk read model | planned | |
| 1b app bug fixes (both editions) | planned | |
| 1c 2.0 skeleton | planned | |
| 2 Desk | planned | |
| 3 Setups / Dossier / Markets | planned | |
| 4 Execution / Account | planned | |
| 5 Analyst live execution (dark) | planned | |
| 6 Pre-launch | planned | |

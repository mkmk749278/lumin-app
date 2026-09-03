# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Lumin** — the consumer Android app (Flutter) for the **360 Crypto Eye** scalping signal engine. Lumin is the consumer brand; 360 Crypto Eye is the engine + signal-source brand.

**The app is LIVE on the Google Play production track.** Real users see every signal and can run auto-trade on their own capital. Treat every change with production discipline: the engine repo's dark-flag-first rule applies to anything money-path — the app side of such a change ships together with (and renders truthfully against) the engine's default-OFF flag.

## Companion repos

- **`mkmk749278/360-v2`** — the engine + API this app talks to, and the source of truth for role, doctrine, and roadmap. At session start read **`ARCHITECTURE.md`** there first (the whole system on one map — §1 for repo boundaries, §4.7 for this app's own entry, §5 for where every fact lives), then `OWNER_BRIEF.md` and `ACTIVE_CONTEXT.md`; update `ACTIVE_CONTEXT.md` there at session end. Sessions frequently span both repos (engine endpoint + app UI in one change, shipped as paired PRs) — and a cross-repo field name is a contract, so pin it in a test on the producing side.
- **`mkmk749278/lumin-legal`** — the public privacy / terms / risk documents that Settings → Legal links to (`lib/data/legal_urls.dart`).

Every change ships via PR — never push to `main` directly. A `main` push triggers the full CI build and auto-creates a GitHub Release the in-app updater picks up.

**Wait ~11 minutes before checking a full green here — but a test failure
lands in ~1.5.** Measured 2026-09-03 over the seven most recent successful
runs; this file previously said ~16 minutes, and that number sent a reader to
wait ten times longer than the commonest failure needs.

| Job | Duration | What it is |
|---|---|---|
| `Build signed APK` | **7 – 11.5 min** (n=7) | the long pole, and the whole run's duration |
| ↳ its `Run unit tests` step | **~65s**, ending ~1m35s into the run | `flutter test` — where a red run usually goes red |
| `Build web app (PWA)` | **~2m10s** | build, and on `main` the live deploy of `app.luminapp.org` |

Three things follow, and none of them was in the old paragraph:

- **A green web job says nothing about the run** — that half was right and still is.
- **A red run is usually red at ~1m35s.** Unit tests run inside the APK job and
  everything after them is skipped on failure, so a `flutter test` break is
  readable long before the build would have finished. Waiting the full window to
  discover a test failure is ten minutes spent on nothing.
- **The web job IS the web deploy.** `Copy web build to VPS` / `Activate web
  deploy on VPS (atomic swap)` run on a `main` push and are skipped on a branch,
  so `app.luminapp.org` is live ~2 minutes after a merge — about eight minutes
  before the APK it shipped alongside even exists. That is the surface an agent
  session drives (`docs/AI_AGENT_APP_ACCESS.md`), so its clock is the one to use
  there, not the APK's.

For comparison, measured the same day: `360ce-ops` CI is **6m52s – 10m15s** and
the engine's `test` job **4m54s – 7m31s**, so this repo is no longer "by a wide
margin the longest" — ops has caught up with it.

Polling a check run that cannot have finished yet burns API calls and turns one
wait into six — sleep the known duration first, *then* read the conclusion.
These are expected durations, not deadlines: a job still running at the mark
gets another wait.

**Re-derive rather than trust this table.** It is a constant asserting a
property of a moving system, and it will go stale again:

```bash
gh run list --workflow=build-apk.yml --json startedAt,updatedAt,conclusion --limit 10
gh run view <run-id> --json jobs        # per-job and per-step timings
```

## Commands

```bash
flutter pub get                                  # deps
flutter test                                     # all tests (CI runs this on every push/PR)
flutter test test/data/binance_client_test.dart  # single test file
flutter build apk --release                      # sideload channel (default)
flutter build appbundle --release --dart-define=LUMIN_DISTRIBUTION=play   # Play channel
```

## Build system — there is no `android/` directory

The Android platform scaffolding is **not checked in**. CI (`.github/workflows/build-apk.yml`) regenerates it with `flutter create` on every run, then patches it in-place:

- injects `INTERNET`, `REQUEST_INSTALL_PACKAGES`, `POST_NOTIFICATIONS` into the manifest
- injects `google-services.json` + the release keystore from Actions secrets
- patches `build.gradle.kts` for release signing and full R8 (`isMinifyEnabled` + `isShrinkResources`)
- deletes the `flutter create` stub `test/widget_test.dart` so the real `test/` tree is what runs
- builds obfuscated (`--obfuscate`, symbol maps uploaded as an artifact; de-obfuscate crash traces with `flutter symbolize`)
- verifies the APK is release-signed (fails loudly on silent debug-signing)
- stamps `--build-number` from the GitHub run number

**Native Android config changes are made by editing the workflow's patch steps, not by committing `android/`.** Each patch step is idempotent — keep new ones that way.

## Distribution channels

Two channels, decided at **compile time** via `lib/app/distribution.dart` (`String.fromEnvironment('LUMIN_DISTRIBUTION')` — a tampered runtime config can't flip it):

| Channel | Artifact | Self-updater |
|---|---|---|
| `sideload` (default) | signed APK on GitHub Releases | on (`UpdateBanner` + `UpdateService`) |
| `play` | signed AAB on Google Play | **inert, required** — Play forbids self-updating apps; `REQUEST_INSTALL_PACKAGES` is also stripped from the AAB manifest |

CI builds **both** artifacts on every `main` push and attaches both to the auto-created release. Play submission checklist: `docs/PLAYSTORE_BUILD.md`; release notes block: `docs/PLAY_RELEASE_NOTES.md`.

## Architecture

**Boot** (`lib/main.dart`): edge-to-edge system UI → `Firebase.initializeApp` → one-shot legacy-JWT cleanup → `NotificationService.init` (FCM; never throws — a Play-Services hiccup must not block start) → `AppConfig.load` → `LuminApp`. First-run gate: `WelcomePage` → `WelcomeConsentPage` (18+ / risk / not-advice checkboxes; re-shows on consent-version bump) → Firebase phone-OTP `AuthGate` → `NavShell`.

**NavShell tabs**: Pulse (Dashboard/Alerts), Signals, Charts, Trade (paper trades), Menu (Settings).

**Repository seam** (`lib/data/repository.dart`): `LuminRepository` is the single seam between UI and data. `MockRepository` (offline/preview) vs `HttpRepository` (live engine) is chosen at startup from `AppConfig` (`dataSource: mock|live` + `apiBaseUrl`). Pages never do HTTP directly — new data behaviour means a new repository method on both implementations.

**Auth** (`lib/data/auth_service.dart`): Firebase Authentication. SMS path is Firebase Phone Auth end-to-end; every authorized engine call carries `Authorization: Bearer <Firebase ID token>` (SDK auto-refreshes). Tier / user_id come from the engine, cached in `AppConfigScope`.

**Two distinct Binance execution paths — different key stores, don't conflate:**

- **Client-side** (`binance_client.dart` + `binance_keys_service.dart`): the device signs Binance Futures REST itself (HMAC-SHA256). Keys live per-user in `flutter_secure_storage` (`binance.user.<id>`); the engine never sees them.
- **Server-side** (`server_side_execution_models.dart`): the user connects a key to the engine (KMS-encrypted, IP-whitelisted to the VPS); the engine dispatches orders. Server-side "take" of a signal goes through `POST /api/auto-trade/take`, not device signing.

**Billing** (`play_billing_service.dart`): subscriptions via Google Play Billing; the engine verifies the `purchaseToken` (`POST /api/billing/play/verify`) and **is the entitlement source of truth** — client-side tier gating is UX only.

**Charts** (`lib/features/charts/`): `webview_flutter` hosting the vendored TradingView Lightweight Charts asset (`assets/chart/`). Candles come straight from Binance public Futures REST (history + short last-bar poll) — no key, no engine load.

**Push** (`lib/data/notification_service.dart`): FCM topic subscriptions (`alerts`, `signals`) — no device-token registry; the engine sends via firebase-admin. Foreground pushes surface as SnackBars via the app-level `scaffoldMessengerKey`.

## Driving the app as an agent (no phone, no emulator)

An AI session can sign into Lumin and browse it — via the **web (PWA) channel**,
never the Android build (no emulator, no KVM, no `android/` in the tree). The
deployed site at `app.luminapp.org` can be *loaded* but not *signed into*: web
phone-auth runs reCAPTCHA, which escalates to an image challenge for headless
browsers. Never solve it and never spoof a human fingerprint — build the web
target locally with `--dart-define=LUMIN_E2E=true`, which enables Firebase's
documented `appVerificationDisabledForTesting` and works only with numbers
registered as test numbers in the console.

Full procedure, coordinates, and the traps (the agent proxy's port changes
mid-session; Chrome's post-quantum TLS breaks the MITM proxy; Charts looks
broken because Binance 451s datacenter IPs): **`docs/AI_AGENT_APP_ACCESS.md`**.

That flag is a **local patch, deliberately not in this repo** — auth-weakening
code does not belong in the tree of a live financial app. If you ever find
`LUMIN_E2E` referenced here or in a workflow, that is a defect: remove it.

## Conventions

- **The engine is the source of truth** for anything money-adjacent the UI renders: entitlement tier, signal open/closed (`is_open`), auto-trade armed state and its gates. Render engine state; never derive or optimistically assume it. (A card showing "armed" while dispatch silently skips is a bug class this repo has already paid for.)
- **…and an engine "unknown" is not an engine "no".** `/api/auto-trade/runtime-status` returns `auto_trade_globally_enabled: false` and `binance_key_connected: false` for three different worlds — the flag is honestly off, the Firestore read raised, or the store was never initialised in the api process. **Fixed 2026-09-02**: the engine now publishes `global_flags_readable` and `binance_key_readable` beside them, and `LiveBlockReason.statusUnknown` / `keyStatusUnknown` carry copy that promises no automatic resume and never asks a user to re-add a key we could not check for. Both are **tri-state**: `null` is an engine predating the field and keeps the original wording, because downgrading every older build to "we could not check" is the alarming version of the same error. Any new money-path flag ships with its own readability field or the app must not render a cause for it. The Trade tab renders all three as **"Trading briefly paused for everyone … No action needed — trading resumes automatically"**, and tells a user whose key *is* connected to go and connect one (owner screenshot, 2026-09-02). Two of those three worlds never resume, and none of them is a safety pause. **Where a gate can be false because we could not ask, the copy must not name a cause** — say what we know, say we could not check, and never promise an automatic recovery the app cannot observe. This is the ops repo's "blank needs a cause before it gets a caption" rule with a paying subscriber at the end of it.
- **Reassuring copy is the dangerous direction on a money screen.** A wrong alarming caption sends someone to check something that works; a wrong calming one makes them wait for a resume that is never coming, while their capital sits idle behind a switch nobody has thrown. When a state's cause is unknown, prefer "we can't confirm this right now" over either.
- Never log a Binance key/secret or write it anywhere but `flutter_secure_storage` (mirrors the engine's hard limits).
- Tests mirror the `lib/` structure under `test/`; JSON models get serialization tests with defaults tolerant of older backends (fields default rather than null-crash on pre-upgrade engines).
- Source files carry `///` doc headers explaining the *why* with dated decisions — keep that style when adding modules.
- Dependency pins with a reason get the reason as a `pubspec.yaml` comment (see `share_plus`); keep that discipline when pinning.

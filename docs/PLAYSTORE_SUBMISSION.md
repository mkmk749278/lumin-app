# Google Play production submission — form answers

Paste-ready answers for the Play Console production submission. Every data
claim here is verified against the published Privacy Policy
(`mkmk749278.github.io/lumin-legal/privacy`) so the data-safety form and the
policy agree — Google cross-checks them and rejects on mismatch.

Pairs with `PLAYSTORE_BUILD.md` (how to produce the compliant AAB).

---

## Legal URLs (verified live on GitHub Pages, served from lumin-legal `main`)

| Field | URL |
|---|---|
| Privacy policy | https://mkmk749278.github.io/lumin-legal/privacy |
| Terms of service | https://mkmk749278.github.io/lumin-legal/terms |
| Risk disclosure | https://mkmk749278.github.io/lumin-legal/risk |
| Data deletion | https://mkmk749278.github.io/lumin-legal/delete-account |

The data-deletion page describes both paths (in-app **Settings → Delete
account**, which requires typing `DELETE`, and email). The in-app flow matches
the page step-for-step.

---

## Apply for production — closed-test questions

Honest, concrete answers (adapt specifics to your real experience):

- **Recruiting testers:** invited from the existing Telegram signals community
  and direct outreach to interested crypto-futures traders (12+ opted in).
- **Engagement / feedback:** Telegram group + in-app use over the 14-day
  window; feedback on sign-in, paper-trading clarity, signal display, settings.
- **What changed from feedback:** clarified the paper → evaluate → subscribe
  journey, made the paper-balance reset prominent, removed engine-internal
  jargon from user screens, added reset-to-engine-defaults for per-user
  settings.

---

## Data safety form

- **Collects or shares user data?** Yes
- **Encrypted in transit?** Yes (HTTPS)
- **Way to request deletion?** Yes — in-app + the data-deletion URL above

### Data types

| Type | Collected | Shared | Purpose | Optional/Required |
|---|---|---|---|---|
| Phone number | Yes | No | Account management — OTP sign-in (Firebase Auth) | Required |
| Name | Yes | No | App functionality / personalisation | Optional |
| Other info — country, timezone, currency | Yes | No | App functionality / personalisation | Optional |
| Other IDs — Telegram chat ID *(only if you link Telegram)* | Yes | No | App functionality — signal delivery | Optional |
| Financial info — other *(Binance API key, only if you enable auto-execution)* | Yes | No | App functionality — place your own orders | Optional |
| Crash logs | Yes | No | Analytics / stability (Firebase Crashlytics) | — |
| Diagnostics *(if Crashlytics performance is on)* | Yes | No | Analytics | — |

### Explicitly NOT collected
Location, Contacts, Photos/Videos, Files/Docs, Calendar, SMS, Health/Fitness,
Browsing history, **Advertising ID**, Payment info (no in-app payments).

### "Shared" clarification
Google (Firebase Auth, Crashlytics, Cloud KMS, Firestore) and Binance are
**service providers / processors**, not third parties receiving data for their
own use. Do **not** mark data as "shared" for advertising or data-broker
purposes — none occurs. The Binance key is transmitted to Binance solely to
act on the user's own account.

### Security practices note (optional field)
> Binance API keys are encrypted at rest with Google Cloud KMS envelope
> encryption; plaintext keys never persist to disk, logs, or error traces.
> Keys must have withdrawals disabled — connect-time validation rejects any
> withdraw-enabled key. Lumin never holds or can move user funds.

---

## App content & declarations

| Declaration | Answer |
|---|---|
| Privacy policy URL | (see table above) |
| Ads | No ads |
| Target audience / age | **18 and over** only — financial-risk app; never include children |
| Content rating | Complete the questionnaire truthfully; expect a mature/financial rating. Paper trading is **not** simulated gambling. |
| Data deletion | In-app (Settings → Delete account) + data-deletion URL |
| Government / news / COVID | No |
| Financial features | **Yes** — see framing below |

### Financial-features framing (the section most likely to draw follow-up)
Lead every free-text box with the true, defensible position:

> Lumin is a **non-custodial** crypto-futures **signals + user-authorised
> automation** tool. It never holds, custodies, or can withdraw user funds.
> Trades are placed only on the user's own Binance Futures account via a
> trade-only API key the user provides; keys with withdrawal permission are
> automatically rejected. Availability is restricted by an in-app region gate.

Match the declared availability regions to the in-app region gate's permitted
jurisdictions.

---

## Pre-submission verification (done)

- [x] Self-updater inert on the Play AAB (code via `LUMIN_DISTRIBUTION=play` +
      manifest strip in `build-apk.yml`) — see `PLAYSTORE_BUILD.md`.
- [x] In-app account deletion reachable (Settings → Delete account, type
      `DELETE`).
- [x] Legal pages (privacy / terms / risk / delete-account) live on GitHub
      Pages from lumin-legal `main`.
- [x] Data-safety declarations above reconciled against the published privacy
      policy.
- [ ] Confirm `targetSdk` meets Play's current minimum for new apps (Console
      will tell you on upload if not).

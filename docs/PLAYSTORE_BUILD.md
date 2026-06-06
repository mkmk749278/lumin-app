# Google Play production build & submission checklist

Lumin ships through two channels:

| Channel | Artifact | Updates | Self-updater |
|---|---|---|---|
| **sideload** (default) | signed APK on GitHub Releases | in-app GitHub-Releases updater | **on** |
| **play** | signed AAB on Google Play | Play Store | **off** (required) |

Google Play **forbids** an app updating itself by any mechanism other than
Play. The sideload self-updater (`UpdateBanner` + `UpdateService`, which
downloads an APK and installs it via `REQUEST_INSTALL_PACKAGES`) must be
**absent** from a Play build, both in code and in the manifest.

## Building the Play AAB

```bash
flutter build appbundle --release --dart-define=LUMIN_DISTRIBUTION=play
```

`--dart-define=LUMIN_DISTRIBUTION=play` flips `kSelfUpdateEnabled` to false
(`lib/app/distribution.dart`), which:

- omits the `UpdateBanner` from the nav shell, and
- hard-stops `UpdateService.check()` so the updater is inert even if wired.

The default (no `--dart-define`) stays **sideload**, so the existing
`build-apk.yml` GitHub-Releases pipeline is unchanged.

## Manifest: do NOT inject `REQUEST_INSTALL_PACKAGES`

`build-apk.yml` injects `REQUEST_INSTALL_PACKAGES` for the sideload APK (the
self-installer needs it). A Play build must **not** declare it — Play flags
the permission as a self-update signal and will reject. When you wire the AAB
build (a separate workflow or local build), do **not** run the
`REQUEST_INSTALL_PACKAGES` injection step. `INTERNET` is the only runtime
permission the app actually needs.

After building, confirm the merged manifest in the AAB declares only:

- `android.permission.INTERNET`

and **not** `REQUEST_INSTALL_PACKAGES` (nor any storage/SMS/location/contacts
permission the app doesn't use).

## Pre-submission checklist

- [x] **Self-update disabled** on Play builds — `LUMIN_DISTRIBUTION=play`
      gate (this is enforced in code).
- [x] **Account deletion in-app** — Settings → Delete account
      (`settings_page.dart::_deleteAccount` → `DELETE /api/account`). Play
      requires an in-app deletion path for apps with accounts.
- [x] **18+ / risk disclosure** — welcome screen + consent gate spell out
      crypto-futures loss risk before signin.
- [ ] **Data safety form** — declare what the app collects and why:
      - Phone number (OTP sign-in / account identity).
      - Binance API key + secret (trade-only, non-custodial; used to place
        the user's own orders). State that keys are never used to withdraw
        and that withdraw-enabled keys are rejected.
      - No location, contacts, photos, or advertising ID.
- [ ] **Permissions match the form** — only `INTERNET` in the Play manifest.
- [ ] **Financial-features declaration** — crypto-trading apps require the
      Play Console financial-services declaration; complete it for the
      target regions and confirm region availability matches the in-app
      region gate.
- [ ] **Target API level** — confirm `targetSdk` meets Play's current
      minimum for new submissions.

## Why this matters

Self-update via APK install is one of the most common hard rejections for
apps that were first distributed as sideload APKs. Gating it behind the
distribution flag lets the same codebase serve both channels without a fork.

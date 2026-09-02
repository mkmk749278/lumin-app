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

## The AAB is already built by CI

`build-apk.yml` produces **both** artifacts on every push to `main` (and on
`workflow_dispatch`):

- `lumin-apk-{run}` — the **sideload** APK (keeps the self-updater +
  `REQUEST_INSTALL_PACKAGES`).
- `lumin-aab-{run}` — the **Play** App Bundle. Before this build the workflow:
  - strips `REQUEST_INSTALL_PACKAGES` and the transitive media permissions
    (`READ/WRITE_EXTERNAL_STORAGE`, `READ_MEDIA_*`) from the manifest, and
  - builds with `--dart-define=LUMIN_DISTRIBUTION=play`, which flips
    `kSelfUpdateEnabled` to false (`lib/app/distribution.dart`) so the
    `UpdateBanner` is omitted and `UpdateService.check()` hard-stops to null.

So the Play bundle has the self-updater inert **in code and in the manifest**.
To submit: download the `lumin-aab-{run}` artifact from the workflow run and
upload it in the Play Console.

### Local build (alternative)

```bash
flutter build appbundle --release --dart-define=LUMIN_DISTRIBUTION=play
```

The default (no `--dart-define`) stays **sideload**, so a plain
`flutter build apk` / the existing GitHub-Releases pipeline is unchanged.

### Confirm before submitting

The merged manifest in the AAB should declare only:

- `android.permission.INTERNET`

and **not** `REQUEST_INSTALL_PACKAGES` (nor any storage/media/SMS/location/
contacts permission the app doesn't use).

## Store listing icon

The Play Console's 512x512 listing icon is uploaded by hand — it is not part
of the AAB — and it must match the launcher icon inside it, or the tile a
user taps in the Play app is not the tile that lands on their home screen.

Upload **`assets/brand/play_store_512.png`**. It is generated from the same
geometry as every in-bundle icon by `python3 tool/gen_brand_assets.py`, so a
change to the mark reaches both by regenerating rather than by remembering.

> Until release 282 this listing showed, and the app installed, `flutter
> create`'s stock Flutter chevron. If the Console still displays it, the
> listing icon has not been re-uploaded — the in-bundle icon ships with the
> build, this one does not.

## Pre-submission checklist

- [x] **Self-update disabled** on Play builds — `LUMIN_DISTRIBUTION=play`
      gate enforced in code, and the CI AAB build passes that define +
      strips `REQUEST_INSTALL_PACKAGES`/media permissions from the manifest.
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

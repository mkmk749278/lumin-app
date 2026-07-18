# Web (PWA) channel — app.luminapp.org

*Added 2026-07-18. The iPhone path: Apple's crypto rules (Guideline 3.1.5)
make an App Store listing impossible without an Organization account, so
the iOS product is the installable web app. Zero Apple dependency, one
Flutter codebase, engine reused as-is.*

## What ships

| Capability | Web channel |
|---|---|
| Pulse / Signals / paper trades / Settings | ✅ full (`LuminRepository` is platform-neutral) |
| Push (signals/alerts) | ✅ FCM web push via the engine's `POST /api/push/{subscribe,unsubscribe}` topic proxy |
| Charts | ✅ same TradingView asset, hosted in a same-origin iframe (`chart_webview_web.dart`) |
| Auto-trade | ✅ server-side only (engine-held keys) |
| Client-side Binance keys (device signing) | ❌ excluded on web — no keystore-grade storage in a browser |
| Self-updater | ❌ inert (`LUMIN_DISTRIBUTION=web`) — web deploys ARE the update mechanism |
| Billing | Phase 3 (needs a web payment provider — owner decision, dark-first) |

**iOS reality check:** web push only works after *Share → Add to Home
Screen* (iOS 16.4+). The in-app `InstallBanner` walks users through it and
the permission prompt always follows a user tap (Apple requirement).

## Build & deploy pipeline

CI (`build-apk.yml` → `build-web` job) on every push:

1. Injects the web `FirebaseOptions` block + `firebase-messaging-sw.js`
   placeholders from the `FIREBASE_WEB_CONFIG` secret.
2. `flutter build web --release --no-web-resources-cdn
   --dart-define=LUMIN_DISTRIBUTION=web
   --dart-define=LUMIN_FCM_VAPID_KEY=$FCM_VAPID_KEY`
   (CanvasKit is bundled — the app must not need a third-party CDN to boot;
   the only remaining boot-critical external fetch is the Firebase JS SDK
   from gstatic).
3. Uploads the build as a workflow artifact.
4. On `main` push, ships `build/web` to the VPS docroot
   (`/var/www/app.luminapp.org`) with an atomic swap.

Server side: `tools/setup-vps-webapp.sh` in `360-v2` provisions the nginx
server block + Let's Encrypt cert (deploy-entry documents no-cache; hashed
bundles cache 1h).

## Owner go-live checklist (one-time)

1. **Firebase console** — Project settings → Your apps → *Add app → Web*.
   Add `app.luminapp.org` to Authentication → Settings → Authorized
   domains. Copy the config object into the `FIREBASE_WEB_CONFIG` repo
   secret (JSON: `apiKey`, `appId`, `messagingSenderId`, `projectId`,
   `authDomain`, `storageBucket`).
2. **VAPID key** — Firebase console → Cloud Messaging → Web configuration
   → generate key pair; save the public key as the `FCM_VAPID_KEY` secret.
3. **VPS secrets** — add `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY` to THIS
   repo (same values as `360-v2`'s deploy secrets). Until present, the
   deploy steps skip cleanly and the build only uploads an artifact.
4. **VPS** — `sudo bash tools/setup-vps-webapp.sh --email <owner-email>`
   (in the `360-v2` checkout on the VPS).
5. **Cloudflare** — DNS A record `app.luminapp.org` → VPS IP (same proxy
   posture as `api.luminapp.org`).
6. Merge to `main` → CI deploys → open `https://app.luminapp.org` on an
   iPhone → Add to Home Screen → sign in (reCAPTCHA phone OTP) → enable
   notifications → fire a test push via the engine's existing send path.

## Architecture notes

- `lib/app/distribution.dart`: the `web` token maps explicitly (the
  historical unknown-token→sideload fail-safe would otherwise enable the
  self-updater on web).
- Phone OTP on web = `signInWithPhoneNumber` (invisible reCAPTCHA,
  `ConfirmationResult`); Android keeps `verifyPhoneNumber`. Same OTP page.
- Chart bridge: payload shapes live in `chart_bridge.dart` (pinned by
  `test/features/charts/chart_bridge_test.dart`); hosts differ only in
  transport (WebView `runJavaScript` vs iframe `postMessage` — shim inside
  `assets/chart/index.html`).
- Web push arms **post-auth** (`NavShell.didChangeDependencies` →
  `NotificationService.attachRepository` → `syncWebPush`) because the
  engine's topic proxy requires the Firebase Bearer. Token rotation is
  covered by re-arming on every shell mount.
- The engine keeps its no-token-registry doctrine: the proxy uses the
  token once, never stores it.

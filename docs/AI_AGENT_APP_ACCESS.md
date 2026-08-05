# Driving the Lumin app as an AI agent

How Claude (or any automated agent) signs into Lumin and browses it, without a
phone, an emulator, or a real user's credentials.

Written 2026-08-05, from the first session that actually did it end to end.
Everything below was executed, not theorised — the failures listed under
*Traps* each cost real time.

---

## The short version

Do **not** try to run the Android app. Use the **web (PWA) channel**, which is a
first-class supported target (`lib/app/distribution.dart`, `docs/WEB_PWA_CHANNEL.md`)
and is the live iPhone product at `app.luminapp.org`.

Two modes, and the choice matters:

| Mode | What it is | Can it sign in? |
|---|---|---|
| **Read-only** | Point a browser at `https://app.luminapp.org` | ❌ Blocked at reCAPTCHA |
| **E2E** | Build the web target locally with `LUMIN_E2E=true` | ✅ Test numbers work |

Read-only reaches the sign-in screen and no further. Anything past login needs
the local E2E build.

---

## Why the deployed site cannot be signed into

Firebase Phone Auth on web runs a reCAPTCHA attestation
(`auth_service.startSmsSignIn`, `kIsWeb` branch). Google's risk scoring sees a
headless browser on a datacenter IP and escalates from the invisible check to a
full image challenge.

**Do not solve it, and do not spoof a human fingerprint to avoid it.** Both
defeat an anti-automation control. Use the sanctioned path below instead.

Registering a test number is *not* enough on its own — test numbers skip the
SMS, but the web flow still runs reCAPTCHA.

---

## The sanctioned path: `appVerificationDisabledForTesting`

Firebase ships a documented switch for exactly this. It takes effect **only** for
numbers registered under *Authentication → Sign-in method → Phone → Phone numbers
for testing*, so it cannot be pointed at a real account.

**This is a LOCAL patch and is deliberately NOT in the repository.** Auth-weakening
code does not belong in the tree of a live financial app, not even gated — the
gate is one careless build argument away from being wrong, and nothing in the
product needs it. Apply it to your scratch copy only, and never commit it.

In the scratch copy's `lib/main.dart`, immediately after `Firebase.initializeApp`:

```dart
// LOCAL E2E ONLY — never commit. Firebase's documented automated-testing
// switch; takes effect only for numbers registered as test numbers, so it
// cannot be pointed at a real account.
if (const bool.fromEnvironment('LUMIN_E2E')) {
  await FirebaseAuth.instance
      .setSettings(appVerificationDisabledForTesting: true);
}
```

What it does: renders a *mock* reCAPTCHA instead of the real one. A non-test
number still fails, because the backend rejects the mock token — which is why
this cannot be used against a real user.

If you ever find `LUMIN_E2E` referenced in the repo or in a workflow, that is a
defect: remove it.

### Test credentials

Registered in Firebase project `lumin-app-a28a2`:

| Number | Code |
|---|---|
| `+91 99999 99999` | `749278` |
| `+1 666-666-6666` | `749278` |

Signing in with one creates a **real user record** in the production Firebase
project and calls the **live engine API** with that user's ID token. It is
free-tier with no Binance key, so it cannot place orders — but it appears in the
user list and can accumulate paper-book state. Ask the owner before using it.

---

## Build and run

The web target needs the Flutter SDK only — **no Android SDK, no emulator.**

```bash
# 1. Flutter SDK (once)
curl -sL -o flutter.tar.xz "$(curl -s \
  https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
  | python3 -c "import sys,json;d=json.load(sys.stdin);h=d['current_release']['stable'];\
r=[x for x in d['releases'] if x['hash']==h and x['channel']=='stable'][0];\
print(d['base_url']+'/'+r['archive'])")"
tar xf flutter.tar.xz
git config --global --add safe.directory "$PWD/flutter"   # else flutter refuses to run

# 2. Fill the Firebase web config
#    lib/firebase_options.dart ships as a PLACEHOLDER; CI generates the real
#    values from the GOOGLE_SERVICES_JSON secret at build time, so a local
#    build gets <TODO_FILL_FROM_FIREBASE_CONSOLE> and dies at boot.
#    Values are public (they ship in every APK and in the deployed web bundle).

# 3. Build
flutter pub get
flutter build web --release \
  --dart-define=LUMIN_DISTRIBUTION=web \
  --dart-define=LUMIN_E2E=true
```

### Firebase web config

`google-services.json` is Android-only and does **not** contain these. Read them
from the deployed bundle (they are already public):

```bash
curl -s https://app.luminapp.org/main.dart.js | grep -o -E 'AIza[0-9A-Za-z_-]{35}'
curl -s https://app.luminapp.org/firebase-messaging-sw.js | grep -o -E "appId[^,]*|projectId[^,]*"
```

| Field | Value |
|---|---|
| `projectId` | `lumin-app-a28a2` |
| `messagingSenderId` | `469870357197` |
| `authDomain` | `lumin-app-a28a2.firebaseapp.com` |
| `storageBucket` | `lumin-app-a28a2.firebasestorage.app` |
| web `appId` | `1:469870357197:web:bf60cb1dd02f1b91091784` |

---

## Serving it under the right origin

Firebase only accepts auth from an **authorized domain**. `localhost` is
authorized by default; a raw IP is not.

The approach that worked: serve the built files under the real origin using
Playwright request interception, so the page origin stays
`https://app.luminapp.org` and every other host still goes out normally.

```python
ctx.route("https://app.luminapp.org/**", serve_from_build_web)
# CanvasKit is fetched from gstatic; the build ships it locally
ctx.route("https://www.gstatic.com/flutter-canvaskit/**", serve_local_canvaskit)
```

---

## Driving the UI

Flutter web renders to canvas. There is **no DOM to query** — `innerText` is
empty and the semantics tree stays empty unless accessibility is enabled, which
did not reliably populate. Click by **coordinates** at a fixed viewport.

At `430 × 930`, mobile UA, `has_touch=True`:

| Step | Action |
|---|---|
| Onboarding | click `(382, 31)` — Skip |
| Onboarding last page | click `(215, 794)` — Get Started |
| Consent checkboxes | click `(52, 161)`, `(52, 257)`, `(52, 373)` |
| Consent continue | click `(215, 878)` |
| Country picker | click `(79, 225)` |
| Country search | click `(215, 327)`, type `India` |
| First result | click `(215, 386)` |
| Phone field | click `(265, 225)`, type `9999999999` |
| Send via SMS | click `(215, 316)` |
| **Code field** | click `(215, 251)` **first** — it does not autofocus |
| Verify | click `(215, 345)` |
| Tabs | `(43,890)` Pulse · `(129,890)` Signals · `(215,890)` Charts · `(301,890)` Trade · `(387,890)` Menu |

Allow ~18–20s after `goto` for the Flutter engine to boot, and 4–9s after each
navigation. Screenshot after every step — a canvas app gives no other feedback.

**These coordinates are a snapshot of the 2026-08-05 layout and will drift.**
Screenshot first, then click; never assume a coordinate still lands.

---

## Traps

Each of these cost a real debugging cycle.

**The agent proxy port changes mid-session.** `HTTPS_PROXY` moved from `45047`
to `37387` inside one session. `curl` kept working (it reads the env var live)
while every hardcoded Playwright script failed with `ERR_PROXY_CONNECTION_FAILED`.
This produced three confident wrong diagnoses in a row — "route interception
breaks the proxy", "the bypass list breaks it", "gstatic is policy-blocked" —
all of them the same stale port. **Always read the proxy from
`os.environ["HTTPS_PROXY"]` at launch.**

**Never put the proxy's own host in the bypass list.** The proxy listens on
`127.0.0.1`; bypassing `127.0.0.1` makes Chromium unable to reach the proxy at
all, and *every* outbound request fails.

**Chrome's post-quantum TLS breaks the MITM proxy.** Default Chromium sends an
oversized ClientHello the proxy resets. Every navigation fails with
`ERR_CONNECTION_RESET` until you launch with:

```
--disable-features=PostQuantumKyber,X25519Kyber768,EncryptedClientHello,TLS13EarlyData
--ssl-version-max=tls1.2
```

**Playwright's bundled browser version may not match `/opt/pw-browsers`.** Pass
`executable_path` to the installed binary rather than running `playwright install`.

**Charts will look broken and is not.** The Charts tab pulls candles straight
from Binance public REST. Binance returns **451** to datacenter IPs, so it
renders "Could not load pairs." That is the environment, not the app — do not
file it as a bug.

**`flutter` refuses to run without `safe.directory`** when the SDK is owned by
another user, and the error names the fix.

---

## Rules for an agent working this way

1. **Never solve a CAPTCHA, and never fake a human fingerprint to avoid one.**
   Use the vendor's testing mechanism or stop.
2. **Never sign in with a real user's number.** Registered test numbers only.
3. **Ask before completing a sign-in** — it creates a real record in the
   production Firebase project and hits the live engine API.
4. **Build in a scratch copy, and strip its `.git`.** A `cp -r` of this repo
   keeps the remote and branch; a push from it lands your test patches on a real
   branch. Delete `.git` in the copy before doing anything else.
5. **Never commit `LUMIN_E2E` into a build config or workflow.**
6. **Never commit filled `firebase_options.dart`.** The placeholder plus CI
   generation is deliberate; a filled file in the tree invites drift from the
   Actions secret that is the real source.
7. **The engine is the source of truth.** If a screen disagrees with the engine,
   report it — do not "fix" the disagreement in the app.

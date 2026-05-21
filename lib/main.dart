/// Lumin app entry — boots Firebase, the AppConfigScope, and routes
/// the first frame between sign-in and the main shell.
///
/// Post-migration: `Firebase.initializeApp` runs before `runApp` so
/// any subsequent FirebaseAuth call (including the AuthGate stream
/// subscription) finds an initialized app.  The legacy local-JWT
/// secure-storage entry is wiped here too — one-shot cleanup that
/// runs idempotently on every launch.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/nav_shell.dart';
import 'data/app_config.dart';
import 'data/auth_service.dart';
import 'data/consent_storage.dart';
import 'features/auth/pages/phone_signin_page.dart';
import 'features/onboarding/pages/welcome_consent_page.dart';
import 'features/onboarding/pages/welcome_page.dart';
import 'firebase_options.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // One-shot cleanup of any pre-migration JWT entries.  Constructs a
  // bare AuthService with a throwaway base URL — we only need the
  // secure-storage delete; no network call happens here.
  await AuthService(baseUrl: '').cleanupLegacyJwtStorage();
  final cfg = await AppConfig.load();
  runApp(LuminApp(initialConfig: cfg));
}

class LuminApp extends StatelessWidget {
  const LuminApp({super.key, required this.initialConfig});

  final AppConfig initialConfig;

  @override
  Widget build(BuildContext context) {
    return AppConfigScope(
      initial: initialConfig,
      child: MaterialApp(
        title: 'Lumin',
        debugShowCheckedModeBanner: false,
        theme: buildLuminTheme(),
        home: const _FirstRunGate(),
      ),
    );
  }
}

/// First-run gate — orchestrates the three-stage onboarding flow:
///
/// 1. **WelcomePage** — brand intro + value-prop + "Get Started"
///    (shows once per device, persists via ``welcomeSeen`` flag)
/// 2. **WelcomeConsentPage** — 3-checkbox legal acknowledgement
///    (18+ / risk / not-advice; re-shows on consent-version bump)
/// 3. **AuthGate → PhoneSignInPage / NavShell** — Firebase phone-OTP
///    sign-in / sign-up, then the main app
///
/// We use a single gate widget instead of nested widgets because
/// each stage needs to observe a SharedPreferences flag and the
/// caller (LuminApp) doesn't want to know about either flag.
///
/// Lives in front of [_AuthGate] (not behind it) because the welcome
/// + consent disclosures are required BEFORE any data collection —
/// including the Firebase Auth session — per Google's prominent-
/// disclosure guidance
/// (https://support.google.com/googleplay/android-developer/answer/11150561).
class _FirstRunGate extends StatefulWidget {
  const _FirstRunGate();

  @override
  State<_FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<_FirstRunGate> {
  Future<_OnboardingState>? _check;

  @override
  void initState() {
    super.initState();
    _check = _resolve();
  }

  Future<_OnboardingState> _resolve() async {
    final welcomeSeen = await ConsentStorage.welcomeSeen();
    final consentDone = await ConsentStorage.isUpToDate();
    if (!welcomeSeen) return _OnboardingState.welcome;
    if (!consentDone) return _OnboardingState.consent;
    return _OnboardingState.ready;
  }

  void _advance() {
    // Re-evaluate flags so we land on the next required stage.
    setState(() {
      _check = _resolve();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OnboardingState>(
      future: _check,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // Same blank-splash convention as [_AuthGate] to avoid a
          // visible flicker between stages.
          return const Scaffold(
            backgroundColor: Color(0xFF0A0E1A),
            body: SizedBox.shrink(),
          );
        }
        switch (snap.data) {
          case _OnboardingState.welcome:
            return WelcomePage(onContinue: _advance);
          case _OnboardingState.consent:
            return WelcomeConsentPage(onAccepted: _advance);
          case _OnboardingState.ready:
          case null:
            return const _AuthGate();
        }
      },
    );
  }
}

enum _OnboardingState { welcome, consent, ready }

/// First-frame gate that decides between [PhoneSignInPage] and
/// [NavShell].  Mock mode bypasses auth.  Live mode subscribes to
/// `FirebaseAuth.authStateChanges()` so sign-in / sign-out reroute
/// the shell reactively without manual `pushAndRemoveUntil` plumbing.
///
/// **Token-mint guard** (2026-05-21 critical fix): a non-null
/// ``currentUser`` is necessary but NOT sufficient for entering
/// NavShell — every API call needs a working Firebase ID token, and
/// the token mint can fail independently of the cached session
/// existing (Play Integrity rejection, Android Auto Backup restoring a
/// session onto a different keystore, Console-side user deletion,
/// revoked refresh material).  Gate verifies the token mints with
/// ``forceRefresh: true`` before routing to NavShell; on failure it
/// calls signOut to clear the unusable session and the StreamBuilder
/// re-emits null → PhoneSignInPage.  Without this guard, the user
/// landed on a signed-in-looking shell where every tab 401'd with
/// "missing bearer token" and there was no path back to sign-in.
///
/// **Pre-warm hook** (2026-05-21 perf push): the first time the
/// auth-state stream resolves to a signed-in AND token-verified user
/// we fire ``repo.prewarmCaches()`` — populates the SwrCache for the
/// Live + Trade tabs in the background so the first tab-switch after
/// sign-in renders synchronously from cache instead of waiting on a
/// network round-trip.  Reset on sign-out so re-sign-in re-warms.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _prewarmed = false;

  /// uid of the user whose Firebase ID-token mint we've already confirmed
  /// works.  When ``snap.data?.uid != _verifiedUid`` we don't trust the
  /// session yet — we kick off [_verifyToken] and render a blank splash
  /// until it resolves.  Resets on sign-out.
  String? _verifiedUid;

  /// uid currently in flight through [_verifyToken] — guards against
  /// the StreamBuilder rebuilding mid-verification and stacking
  /// duplicate getIdToken round-trips.
  String? _verifyingUid;

  /// Confirms the cached Firebase user can actually mint a usable ID
  /// token.  Defends against the cases where ``FirebaseAuth.currentUser``
  /// is non-null but the token-mint fails — most commonly:
  ///
  ///   * Play Integrity rejects the device (cert SHA not registered,
  ///     emulator without skipPlayIntegrityCheck, rooted device, etc.)
  ///   * Android Auto Backup restored the SharedPreferences-cached
  ///     session onto a device / install where the keystore-backed
  ///     refresh material is no longer valid.
  ///   * Firebase Console-side user deletion / disable.
  ///   * Revoked / expired refresh token.
  ///
  /// Pre-2026-05-21 the gate trusted ``currentUser != null`` and routed
  /// straight into NavShell.  Every API call then 401'd with "missing
  /// bearer token" because [AuthService.currentIdToken] returned null —
  /// no Authorization header attached.  The user was stuck on a
  /// signed-in-looking shell that couldn't load any data, with no path
  /// back to PhoneSignInPage.  Owner-observed on the Closed Testing
  /// install 2026-05-21; this guard is the fix.
  Future<void> _verifyToken(AuthService auth, User user) async {
    if (_verifyingUid == user.uid) return;
    _verifyingUid = user.uid;
    String? token;
    try {
      token = await auth.currentIdToken(forceRefresh: true);
    } catch (_) {
      // Treat any throw (Play Integrity rejection, network error,
      // revoked refresh material) the same as a null token — fall
      // through to signOut + PhoneSignInPage so the user has an
      // actionable path.
      token = null;
    }
    if (!mounted) return;
    if (token == null) {
      // Clear the unusable session so the StreamBuilder re-emits
      // null and routes the user to PhoneSignInPage.  signOut is
      // idempotent and safe even if Firebase already considers
      // the session gone.
      try {
        await auth.signOut();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _verifyingUid = null;
      });
      return;
    }
    setState(() {
      _verifiedUid = user.uid;
      _verifyingUid = null;
    });
  }

  Widget _blankSplash() => const Scaffold(
        backgroundColor: Color(0xFF0A0E1A),
        body: SizedBox.shrink(),
      );

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    // Mock data → never gate.  AuthService is null in this branch.
    if (scope.config.dataSource == DataSource.mock || scope.auth == null) {
      return const NavShell();
    }
    return StreamBuilder<User?>(
      stream: scope.auth!.authStateChanges,
      // Seed the first frame with the synchronous `currentUser` so a
      // logged-in user doesn't see the splash flash on cold-start.
      initialData: scope.auth!.currentUser,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _blankSplash();
        }
        final user = snap.data;
        if (user == null) {
          // User signed out (or never signed in).  Reset all per-
          // session flags so the next sign-in re-runs verification +
          // re-warms the SWR cache (covers the sign-out / sign-in-
          // as-different-user flow).
          _prewarmed = false;
          _verifiedUid = null;
          return const PhoneSignInPage();
        }
        if (_verifiedUid != user.uid) {
          // Cached / restored user that hasn't been confirmed yet.
          // Kick off the verification on the next frame so we don't
          // setState during a build.  Renders a blank splash until
          // [_verifyToken] resolves — typically 100-500ms for the
          // forced-refresh round-trip.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _verifyToken(scope.auth!, user);
          });
          return _blankSplash();
        }
        // One-shot SWR cache pre-warm on the first verified-signed-in
        // observation.  Fire via post-frame callback so we don't call
        // repo methods during a build; the SwrCache's in-flight dedup
        // handles any rare race where the user taps a tab during the
        // prewarm.
        if (!_prewarmed) {
          _prewarmed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Fire-and-forget — prewarmCaches itself returns
            // immediately; the actual fetches run in microtasks.
            scope.repo.prewarmCaches();
          });
        }
        return const NavShell();
      },
    );
  }
}

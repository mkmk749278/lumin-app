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
        home: const _ConsentGate(),
      ),
    );
  }
}

/// First-launch consent gate (Play Store first-run-disclosure
/// requirement — see ``docs/PLAYSTORE_PLAN.md`` in the engine repo).
///
/// Resolves ``ConsentStorage.isUpToDate()`` once on app start; if the
/// user has already accepted the current consent version we route
/// straight to [_AuthGate] with no flicker.  Otherwise we render the
/// [WelcomeConsentPage] and only after the user taps Continue do we
/// promote them to [_AuthGate].
///
/// Lives in front of [_AuthGate] (not behind it) because the
/// disclosure is required BEFORE any data collection — including the
/// Firebase Auth session — per Google's prominent-disclosure guidance
/// (https://support.google.com/googleplay/android-developer/answer/11150561).
class _ConsentGate extends StatefulWidget {
  const _ConsentGate();

  @override
  State<_ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<_ConsentGate> {
  Future<bool>? _check;

  @override
  void initState() {
    super.initState();
    _check = ConsentStorage.isUpToDate();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _check,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // Same blank-splash convention as [_AuthGate] to avoid a
          // visible flicker between consent check and auth check.
          return const Scaffold(
            backgroundColor: Color(0xFF0A0E1A),
            body: SizedBox.shrink(),
          );
        }
        if (snap.data == true) {
          return const _AuthGate();
        }
        return WelcomeConsentPage(
          onAccepted: () => setState(() {
            _check = Future.value(true);
          }),
        );
      },
    );
  }
}

/// First-frame gate that decides between [PhoneSignInPage] and
/// [NavShell].  Mock mode bypasses auth.  Live mode subscribes to
/// `FirebaseAuth.authStateChanges()` so sign-in / sign-out reroute
/// the shell reactively without manual `pushAndRemoveUntil` plumbing.
///
/// **Pre-warm hook** (2026-05-21 perf push): the first time the
/// auth-state stream resolves to a signed-in user we fire
/// ``repo.prewarmCaches()`` — populates the SwrCache for the Live +
/// Trade tabs in the background so the first tab-switch after sign-in
/// renders synchronously from cache instead of waiting on a network
/// round-trip.  Reset on sign-out so re-sign-in re-warms.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _prewarmed = false;

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
          return const Scaffold(
            backgroundColor: Color(0xFF0A0E1A),
            body: SizedBox.shrink(),
          );
        }
        if (snap.data != null) {
          // One-shot SWR cache pre-warm on the first signed-in
          // observation.  Fire via post-frame callback so we don't
          // call repo methods during a build; the SwrCache's
          // in-flight dedup handles any rare race where the user
          // taps a tab during the prewarm.
          if (!_prewarmed) {
            _prewarmed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Fire-and-forget — prewarmCaches itself returns
              // immediately; the actual fetches run in microtasks.
              scope.repo.prewarmCaches();
            });
          }
          return const NavShell();
        }
        // User signed out — reset so next sign-in re-warms the cache
        // (covers the sign-out + sign-in-as-different-user flow).
        _prewarmed = false;
        return const PhoneSignInPage();
      },
    );
  }
}

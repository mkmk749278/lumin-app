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
import 'features/auth/pages/phone_signin_page.dart';
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
        home: const _AuthGate(),
      ),
    );
  }
}

/// First-frame gate that decides between [PhoneSignInPage] and
/// [NavShell].  Mock mode bypasses auth.  Live mode subscribes to
/// `FirebaseAuth.authStateChanges()` so sign-in / sign-out reroute
/// the shell reactively without manual `pushAndRemoveUntil` plumbing.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

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
        if (snap.data != null) return const NavShell();
        return const PhoneSignInPage();
      },
    );
  }
}

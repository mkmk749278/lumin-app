/// Lumin app entry — boots the AppConfigScope before MaterialApp.
///
/// We load the persisted ``AppConfig`` once at startup so the repository
/// is ready before the first page renders.  No splash flicker: the load
/// is a single shared_preferences read, well under the first frame.
///
/// Phase 2: if no JWT is in secure storage we route the first frame to
/// [PhoneSignInPage] instead of [NavShell].  Mock-data mode skips this
/// gate entirely (no auth required).
import 'package:flutter/material.dart';

import 'app/nav_shell.dart';
import 'data/app_config.dart';
import 'features/auth/pages/phone_signin_page.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
/// [NavShell].  Mock mode bypasses auth; live mode checks
/// [AuthService.hasStoredToken] once on boot.  After phone-signin the
/// page itself does ``pushAndRemoveUntil`` to NavShell, so this widget
/// only runs once per launch.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  Future<bool>? _hasToken;

  @override
  Widget build(BuildContext context) {
    final scope = AppConfigScope.of(context);
    // Mock data → never gate.  AuthService is null in this branch.
    if (scope.config.dataSource == DataSource.mock || scope.auth == null) {
      return const NavShell();
    }
    _hasToken ??= scope.auth!.hasStoredToken();
    return FutureBuilder<bool>(
      future: _hasToken,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // shared_preferences + secure-storage read; well under one
          // frame on every device we target.  Showing a tiny spinner
          // keeps the first paint clean if the platform channel is
          // slow on a cold start.
          return const Scaffold(
            backgroundColor: Color(0xFF0A0E1A),
            body: SizedBox.shrink(),
          );
        }
        if (snap.data == true) return const NavShell();
        return const PhoneSignInPage();
      },
    );
  }
}

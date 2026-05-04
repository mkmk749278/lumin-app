/// Lumin app entry — boots the AppConfigScope before MaterialApp.
///
/// We load the persisted ``AppConfig`` once at startup so the repository
/// is ready before the first page renders.  No splash flicker: the load
/// is a single shared_preferences read, well under the first frame.
import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'data/app_config.dart';
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
        home: const AppShell(),
      ),
    );
  }
}

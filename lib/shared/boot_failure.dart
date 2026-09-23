/// What the user sees when the app cannot start, or when one part of a
/// screen fails to build.
///
/// Added 2026-09-23. Before it, a throw during boot meant `runApp` was never
/// called — a blank screen, forever, with nothing to press — and a widget
/// that failed to build in a release build rendered Flutter's bare grey box.
/// Both now say what happened in plain words and, where there is one, offer
/// the one thing the reader can do.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'tokens.dart';

/// Full-screen fallback for a failed boot. Deliberately depends on nothing
/// that boot initialises — no Firebase, no config, no repository.
class BootFailurePage extends StatefulWidget {
  const BootFailurePage({super.key, required this.onRetry});

  /// Re-runs the boot sequence.
  final Future<void> Function() onRetry;

  @override
  State<BootFailurePage> createState() => _BootFailurePageState();
}

class _BootFailurePageState extends State<BootFailurePage> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await widget.onRetry();
    // A successful boot replaces this whole tree via runApp; reaching here
    // means it failed again and a fresh BootFailurePage is already showing.
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLuminTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(LuminSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    color: LuminColors.textSecondary, size: 40),
                const SizedBox(height: LuminSpacing.lg),
                const Text(
                  "Lumin couldn't start",
                  style: TextStyle(
                    color: LuminColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: LuminSpacing.sm),
                // Names no cause: from here the app cannot tell a dropped
                // connection from an outage, and must not guess.
                const Text(
                  'Check your internet connection and try again. Your '
                  'account, settings and any open positions are unaffected.',
                  style: TextStyle(
                    color: LuminColors.textSecondary,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: LuminSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _retrying ? null : _retry,
                    child: Text(_retrying ? 'Starting…' : 'Try again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// In release builds, a widget that throws while building renders a small
/// themed notice instead of Flutter's grey box. Debug builds keep the red
/// error screen, which is what a developer needs to see.
void installReleaseErrorWidget() {
  if (!kReleaseMode) return;
  ErrorWidget.builder = (details) => const Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(LuminSpacing.md),
          child: Text(
            "This part of the screen couldn't be shown. Pull to refresh, "
            'or reopen the page.',
            style: TextStyle(color: LuminColors.textMuted, fontSize: 13),
          ),
        ),
      );
}

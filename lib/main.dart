/// Lumin — AI Crypto Trading
///
/// Bootstrap entry point.
import 'package:flutter/material.dart';

void main() {
  runApp(const LuminApp());
}

class LuminApp extends StatelessWidget {
  const LuminApp({super.key});

  static const Color _bgDeep = Color(0xFF0A0E1A);
  static const Color _bgCard = Color(0xFF0F1729);
  static const Color _accent = Color(0xFF7BD3F7);
  static const Color _textPrimary = Color(0xFFF8FAFC);
  static const Color _textSecondary = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bgDeep,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _accent,
          surface: _bgCard,
          onPrimary: _bgDeep,
          onSecondary: _bgDeep,
          onSurface: _textPrimary,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: _textPrimary, fontWeight: FontWeight.w300),
          displayMedium: TextStyle(color: _textPrimary, fontWeight: FontWeight.w300),
          headlineLarge: TextStyle(color: _textPrimary, fontWeight: FontWeight.w400),
          bodyLarge: TextStyle(color: _textPrimary),
          bodyMedium: TextStyle(color: _textSecondary),
          labelLarge: TextStyle(color: _textPrimary),
        ),
      ),
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.bolt_outlined,
                size: 96,
                color: LuminApp._accent,
              ),
              const SizedBox(height: 24),
              Text(
                'Lumin',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 56,
                      letterSpacing: 4,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI Crypto Trading',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      letterSpacing: 2,
                      color: LuminApp._accent,
                    ),
              ),
              const SizedBox(height: 64),
              Text(
                'Powered by 360 Crypto Eye',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: LuminApp._bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LuminApp._accent.withOpacity(0.2)),
                ),
                child: const Text(
                  'v0.0.1 — bootstrap',
                  style: TextStyle(
                    color: LuminApp._textSecondary,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

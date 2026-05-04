/// Brand tokens — Lumin design system.
import 'package:flutter/material.dart';

class LuminColors {
  LuminColors._();

  static const Color bgDeep = Color(0xFF0A0E1A);
  static const Color bgCard = Color(0xFF0F1729);
  static const Color bgElevated = Color(0xFF131C32);
  static const Color accent = Color(0xFF7BD3F7);
  static const Color accentMuted = Color(0xFF4A8DAA);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color success = Color(0xFF4ADE80);
  static const Color warn = Color(0xFFF59E0B);
  static const Color loss = Color(0xFFF87171);

  static Color cardBorder = const Color(0xFF7BD3F7).withOpacity(0.10);
}

class LuminSpacing {
  LuminSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class LuminRadii {
  LuminRadii._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

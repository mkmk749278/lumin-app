/// Brand tokens — colours, spacing, radii.
import 'package:flutter/material.dart';

class LuminColors {
  LuminColors._();

  // Lumin 2.0 palette (2026-11-26): monochrome obsidian first, one accent,
  // and semantic colour used only for status. Separation comes from three
  // surface steps and a hairline, never from tinted panels.
  static const Color bgDeep = Color(0xFF090B10); // canvas
  static const Color bgCard = Color(0xFF11151E); // surface card
  static const Color bgElevated = Color(0xFF171C28); // sheet / header
  static const Color hairline = Color(0xFF222938); // 1px borders

  /// Sky cyan — primary CTAs, the active tab and chart focus. Nothing else.
  static const Color accent = Color(0xFF38BDF8);
  static const Color accentMuted = Color(0xFF1E7FAD);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  /// Long · profit · healthy.
  static const Color success = Color(0xFF10B981);

  /// Pending · caution · paused.
  static const Color warn = Color(0xFFF59E0B);

  /// Short · stop · risk-off.
  static const Color loss = Color(0xFFEF4444);

  /// Card borders are the hairline, not a tint of the accent.
  static const Color cardBorder = hairline;

  /// The 12% wash behind a status pill — status reads from the text colour,
  /// never from a loud filled block.
  static Color tint(Color c) => c.withValues(alpha: 0.12);
}

/// Type families. Every number a trader compares — price, PnL %, R:R,
/// countdown, timestamp — is set in [mono] with tabular figures so a live
/// tick never shifts its neighbours sideways.
class LuminType {
  LuminType._();

  static const String ui = 'Inter';
  static const String mono = 'JetBrainsMono';

  static TextStyle number({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color color = LuminColors.textPrimary,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// The 11sp uppercase eyebrow above a section or a figure.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: ui,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.66, // 0.06em
    color: LuminColors.textMuted,
  );
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'shared/tokens.dart';

/// The Lumin theme.
///
/// Until 2026-09-02 this file set five things — `colorScheme`, `textTheme`,
/// `navigationBarTheme`, `appBarTheme`, `iconTheme` — and *fifteen* component
/// themes fell through to Material 3's defaults, which are built for a light
/// tonal palette rather than this one.  The cost was measurable: 41 buttons
/// hand-styled at their call sites, 14 hand-built `InputDecoration`s, and —
/// the one users actually saw — **125 `SnackBar`s of which only 19 set a
/// background**, so roughly 106 confirmations rendered on M3's default, which
/// resolves `colorScheme.inverseSurface`.  `ColorScheme.dark()` leaves that at
/// `#E6E1E5`: a near-white pill measuring 14.9:1 against `bgDeep`, i.e. the
/// brightest object on the screen, fired on every settings save, every signal
/// taken, every subscription confirmation and every foreground push.
///
/// A component theme here is worth more than the same properties at a call
/// site, because the call site only fixes the screens that already exist.
ThemeData buildLuminTheme() {
  const accent = LuminColors.accent;
  const bg = LuminColors.bgDeep;
  const surface = LuminColors.bgCard;

  // Buttons, fields, sheets and dialogs all share one corner radius and one
  // touch height so a control reads the same wherever it appears.
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(LuminRadii.md),
  );
  // 48dp is the Material minimum touch target; several hand-styled buttons
  // sat below it.
  const minTouch = Size(0, 48);

  OutlineInputBorder fieldBorder(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(LuminRadii.md),
        borderSide: BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    // M3 tints elevated surfaces with the primary colour by default, which
    // washes every dialog and sheet cyan. Lumin separates depth with the
    // bgCard / bgElevated tokens instead.
    colorScheme: const ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: surface,
      surfaceContainerHighest: LuminColors.bgElevated,
      onPrimary: bg,
      onSecondary: bg,
      onSurface: LuminColors.textPrimary,
      error: LuminColors.loss,
      onError: bg,
      outline: LuminColors.textMuted,
      // Drives the default SnackBar; pinned so even an un-themed one lands
      // in the palette rather than at #E6E1E5.
      inverseSurface: LuminColors.bgElevated,
      onInverseSurface: LuminColors.textPrimary,
      inversePrimary: accent,
    ),

    // ---------------------------------------------------------------
    // Type — consumer register (owner, 2026-09-02).  Body sits at 15/14
    // rather than the 11-13px the app had drifted to, and `labelSmall` is
    // the floor: 11px, never 9 or 10.  Numeric roles carry tabular figures
    // so a live price stops shifting sideways as its digits change.
    // ---------------------------------------------------------------
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: LuminColors.textPrimary, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1),
      displayMedium: TextStyle(color: LuminColors.textPrimary, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineLarge: TextStyle(color: LuminColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineMedium: TextStyle(color: LuminColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleLarge: TextStyle(color: LuminColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: LuminColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: LuminColors.textPrimary, fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(color: LuminColors.textSecondary, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: LuminColors.textSecondary, fontSize: 13, height: 1.4),
      labelLarge: TextStyle(color: LuminColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: TextStyle(color: LuminColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(color: LuminColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.0),
    ),

    // ---------------------------------------------------------------
    // The one users saw most: ~106 near-white pills, now on bgElevated and
    // floating so they clear the bottom navigation bar they used to sit
    // under.  Error call sites still override backgroundColor; that keeps
    // working and is the intended escape hatch.
    // ---------------------------------------------------------------
    snackBarTheme: SnackBarThemeData(
      backgroundColor: LuminColors.bgElevated,
      contentTextStyle: const TextStyle(color: LuminColors.textPrimary, fontSize: 14, height: 1.35),
      actionTextColor: accent,
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(LuminSpacing.md, 0, LuminSpacing.md, LuminSpacing.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuminRadii.md)),
      elevation: 6,
      showCloseIcon: false,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: bg,
        disabledBackgroundColor: LuminColors.bgElevated,
        disabledForegroundColor: LuminColors.textMuted,
        minimumSize: minTouch,
        padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.xl, vertical: LuminSpacing.md),
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: LuminColors.bgElevated,
        foregroundColor: LuminColors.textPrimary,
        elevation: 0,
        minimumSize: minTouch,
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        minimumSize: minTouch,
        side: const BorderSide(color: LuminColors.cardBorder),
        shape: shape,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        minimumSize: minTouch,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LuminColors.bgElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: LuminSpacing.lg, vertical: LuminSpacing.md),
      hintStyle: const TextStyle(color: LuminColors.textMuted, fontSize: 15),
      labelStyle: const TextStyle(color: LuminColors.textSecondary, fontSize: 15),
      floatingLabelStyle: const TextStyle(color: accent, fontSize: 13),
      helperStyle: const TextStyle(color: LuminColors.textMuted, fontSize: 13),
      errorStyle: const TextStyle(color: LuminColors.loss, fontSize: 13),
      border: fieldBorder(LuminColors.cardBorder),
      enabledBorder: fieldBorder(LuminColors.cardBorder),
      focusedBorder: fieldBorder(accent, 1.5),
      errorBorder: fieldBorder(LuminColors.loss),
      focusedErrorBorder: fieldBorder(LuminColors.loss, 1.5),
      disabledBorder: fieldBorder(LuminColors.cardBorder),
    ),

    // No Material `Card` is used today (every card is `LuminCard`); this is
    // here so one added later lands in the palette instead of on M3's.
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LuminRadii.lg),
        side: const BorderSide(color: LuminColors.cardBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LuminRadii.lg),
        side: const BorderSide(color: LuminColors.cardBorder),
      ),
      titleTextStyle: const TextStyle(color: LuminColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
      contentTextStyle: const TextStyle(color: LuminColors.textSecondary, fontSize: 15, height: 1.45),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: surface,
      elevation: 0,
      // Deliberately false. Ten sheets (take-signal, manual-trade, phone
      // sign-in, signup, profile, agents, alerts, paper-trade detail, the
      // signal detail sheet and pulse's) already draw their own 36-40x4
      // handle, so switching the theme's on would stack two. Retiring the
      // hand-drawn ones in favour of this is a follow-up, not a change to
      // make blind.
      showDragHandle: false,
      dragHandleColor: LuminColors.textMuted,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LuminRadii.lg)),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: LuminColors.bgElevated,
      selectedColor: accent.withValues(alpha: 0.16),
      disabledColor: LuminColors.bgCard,
      side: const BorderSide(color: LuminColors.cardBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuminRadii.pill)),
      labelStyle: const TextStyle(color: LuminColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600),
      checkmarkColor: accent,
      padding: const EdgeInsets.symmetric(horizontal: LuminSpacing.md, vertical: 6),
    ),
    dividerTheme: const DividerThemeData(
      color: LuminColors.cardBorder,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? bg : LuminColors.textSecondary),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : LuminColors.bgElevated),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : LuminColors.cardBorder),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : Colors.transparent),
      checkColor: const WidgetStatePropertyAll(bg),
      side: const BorderSide(color: LuminColors.textMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : LuminColors.textMuted),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: accent,
      inactiveTrackColor: LuminColors.bgElevated,
      thumbColor: accent,
      overlayColor: Color(0x1A7BD3F7),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: LuminColors.textSecondary,
      textColor: LuminColors.textPrimary,
      titleTextStyle: TextStyle(color: LuminColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
      subtitleTextStyle: TextStyle(color: LuminColors.textSecondary, fontSize: 13, height: 1.35),
      contentPadding: EdgeInsets.symmetric(horizontal: LuminSpacing.lg, vertical: LuminSpacing.xs),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: LuminColors.bgElevated,
      circularTrackColor: Colors.transparent,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: accent,
      unselectedLabelColor: LuminColors.textMuted,
      indicatorColor: accent,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: LuminColors.cardBorder,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: LuminColors.bgElevated,
        borderRadius: BorderRadius.circular(LuminRadii.sm),
        border: Border.all(color: LuminColors.cardBorder),
      ),
      textStyle: const TextStyle(color: LuminColors.textPrimary, fontSize: 13),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: accent.withValues(alpha: 0.15),
      surfaceTintColor: surface,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w500);
        }
        return const TextStyle(color: LuminColors.textSecondary, fontSize: 12);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: accent, size: 24);
        }
        return const IconThemeData(color: LuminColors.textSecondary, size: 24);
      }),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: LuminColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: LuminColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w300, letterSpacing: 1.5),
      // Edge-to-edge (Android 15 / SDK 35): AppBars re-assert the
      // transparent status bar with light icons — without this a page's
      // AppBar can silently override the app-wide overlay style set in main.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),
    iconTheme: const IconThemeData(color: LuminColors.textPrimary),
  );
}

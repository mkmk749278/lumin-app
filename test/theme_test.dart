/// Guards `buildLuminTheme()` against losing the component themes again.
///
/// Until 2026-09-02 this theme set five things and let fifteen component
/// themes fall through to Material 3's defaults, which are built for a light
/// tonal palette. The visible cost was the SnackBar: 125 constructions, 19
/// of which set a background, so ~106 confirmations rendered on M3's default
/// — `colorScheme.inverseSurface`, which `ColorScheme.dark()` leaves at
/// #E6E1E5. That is a near-white pill at 14.9:1 against bgDeep, i.e. the
/// brightest object on the screen, on every settings save, signal taken,
/// subscription confirmed and foreground push.
///
/// These tests assert the *properties*, not the values, so retuning the
/// palette does not fight them — but deleting a component theme does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/tokens.dart';
import 'package:lumin/theme.dart';

/// Perceived luminance, WCAG 2.1 relative luminance.
double _luminance(Color c) => c.computeLuminance();

void main() {
  final theme = buildLuminTheme();

  group('snack bars', () {
    test('do not render on the Material default near-white', () {
      final bg = theme.snackBarTheme.backgroundColor;
      expect(bg, isNotNull, reason: 'snackBarTheme.backgroundColor is unset');
      // The defect, stated as a property: a toast must not be brighter than
      // the app it interrupts.
      expect(_luminance(bg!), lessThan(_luminance(LuminColors.bgCard) + 0.05),
          reason: 'snack bar is lighter than the card surface — this is the '
              '#E6E1E5 regression');
    });

    test('float, so they clear the bottom navigation bar', () {
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.insetPadding, isNotNull);
    });

    test('their content text is legible on that background', () {
      final bg = theme.snackBarTheme.backgroundColor!;
      final fg = theme.snackBarTheme.contentTextStyle?.color;
      expect(fg, isNotNull);
      final ratio = (_luminance(fg!) + 0.05) / (_luminance(bg) + 0.05);
      expect(ratio, greaterThan(4.5), reason: 'snack bar text fails WCAG AA');
    });

    test('an un-themed snack bar would still land in palette', () {
      // Belt and braces: `inverseSurface` is what SnackBar falls back to if
      // snackBarTheme is ever dropped, and ColorScheme.dark() defaults it to
      // #E6E1E5. Pinning it means the regression costs a shade, not a flash.
      expect(_luminance(theme.colorScheme.inverseSurface),
          lessThan(_luminance(LuminColors.bgCard) + 0.05));
    });
  });

  group('component themes', () {
    // Derived rather than listed one by one: adding a reader here is what a
    // future "simplification" would have to defeat deliberately.
    final required = <String, Object?>{
      'filledButtonTheme': theme.filledButtonTheme.style,
      'elevatedButtonTheme': theme.elevatedButtonTheme.style,
      'outlinedButtonTheme': theme.outlinedButtonTheme.style,
      'textButtonTheme': theme.textButtonTheme.style,
      'inputDecorationTheme': theme.inputDecorationTheme.border,
      'cardTheme': theme.cardTheme.color,
      'dialogTheme': theme.dialogTheme.backgroundColor,
      'bottomSheetTheme': theme.bottomSheetTheme.backgroundColor,
      'snackBarTheme': theme.snackBarTheme.backgroundColor,
      'chipTheme': theme.chipTheme.backgroundColor,
      'dividerTheme': theme.dividerTheme.color,
      'switchTheme': theme.switchTheme.trackColor,
      'listTileTheme': theme.listTileTheme.titleTextStyle,
      'progressIndicatorTheme': theme.progressIndicatorTheme.color,
      'tabBarTheme': theme.tabBarTheme.labelColor,
    };

    for (final MapEntry(key: name, value: probe) in required.entries) {
      test('$name is set, not inherited from Material', () {
        expect(probe, isNotNull, reason: '$name fell back to the M3 default');
      });
    }

    test('nothing is tinted by M3 surface elevation', () {
      // M3 washes elevated surfaces with the primary colour; Lumin separates
      // depth with bgCard / bgElevated instead, and a cyan-tinted dialog was
      // the visible result of leaving it on.
      expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      expect(theme.bottomSheetTheme.surfaceTintColor, Colors.transparent);
    });

    test('the sheet handle stays off, because ten sheets draw their own', () {
      // Switching this on stacks two handles on take-signal, manual-trade,
      // phone sign-in, signup, profile, agents, alerts, paper-trade detail,
      // the signal detail sheet and pulse's.
      expect(theme.bottomSheetTheme.showDragHandle, isFalse);
    });
  });

  group('type scale — consumer register (owner, 2026-09-02)', () {
    test('body text is at consumer sizes, not the 11-13px it had drifted to',
        () {
      expect(theme.textTheme.bodyLarge!.fontSize, greaterThanOrEqualTo(15));
      expect(theme.textTheme.bodyMedium!.fontSize, greaterThanOrEqualTo(14));
    });

    test('labelSmall is the floor and it is 11, never 9 or 10', () {
      final sizes = <double>[
        for (final s in [
          theme.textTheme.bodySmall,
          theme.textTheme.labelSmall,
          theme.textTheme.labelMedium,
          theme.textTheme.labelLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.bodyLarge,
          theme.textTheme.titleMedium,
          theme.textTheme.titleLarge,
        ])
          s!.fontSize!,
      ];
      expect(sizes.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(11));
    });

    test('every role uses a whole-point size', () {
      // 23 distinct sizes including 9.5 / 10.5 / 11.5 / 12.5 / 13.5 is the
      // signature of a scale nobody decided; half-points are local nudges.
      for (final s in [
        theme.textTheme.displayLarge,
        theme.textTheme.displayMedium,
        theme.textTheme.headlineLarge,
        theme.textTheme.headlineMedium,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelMedium,
        theme.textTheme.labelSmall,
      ]) {
        expect(s!.fontSize! % 1, 0, reason: 'half-point size ${s.fontSize}');
      }
    });
  });

  group('touch targets', () {
    test('every button clears the 48dp Material minimum', () {
      for (final style in [
        theme.filledButtonTheme.style,
        theme.elevatedButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.textButtonTheme.style,
      ]) {
        final min = style!.minimumSize?.resolve({});
        expect(min, isNotNull, reason: 'button theme sets no minimumSize');
        expect(min!.height, greaterThanOrEqualTo(48));
      }
    });
  });
}

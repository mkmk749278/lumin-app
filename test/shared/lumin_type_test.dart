import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/tokens.dart';
import 'package:lumin/theme.dart';

/// Lumin 2.0 type (2026-11-26): fonts are bundled, so a family the theme
/// names but pubspec does not ship falls back to the platform face silently.
void main() {
  test('every bundled font file exists and is declared', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final f in Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))) {
      expect(pubspec, contains(f.path.replaceAll('\\', '/')),
          reason: '${f.path} is on disk but not declared');
    }
    expect(pubspec, contains('family: ${LuminType.ui}'));
    expect(pubspec, contains('family: ${LuminType.mono}'));
    expect(File('assets/fonts/OFL-Inter.txt').existsSync(), isTrue);
    expect(File('assets/fonts/OFL-JetBrainsMono.txt').existsSync(), isTrue);
  });

  test('the theme sets Inter; numbers use mono with tabular figures', () {
    expect(buildLuminTheme().textTheme.bodyMedium!.fontFamily, LuminType.ui);
    final n = LuminType.number();
    expect(n.fontFamily, LuminType.mono);
    expect(n.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  test('status pills are a 12% tint, never a solid block', () {
    expect(LuminColors.tint(LuminColors.success).a, closeTo(0.12, 0.005));
  });
}

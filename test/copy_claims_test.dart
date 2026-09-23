import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reassuring copy is the dangerous direction on a money screen
/// (CLAUDE.md). Onboarding promised "No runaway losses" two screens before
/// the live-order review warned that a gap can exceed the stop — fixed
/// 2026-09-23, and swept here across the whole of lib/ so the promise
/// cannot reappear on a screen nobody thought to check.
void main() {
  test('no user-visible string promises a loss cannot happen', () {
    final promise = RegExp(
      // Not "no risk": paper mode genuinely carries none, and says so.
      r"(runaway loss|can'?t lose|cannot lose|risk[- ]free|"
      r'guaranteed (profit|return|win)|never lose)',
      caseSensitive: false,
    );
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (l.startsWith('//')) continue; // doc comments may discuss it
        // Only string literals reach a screen.
        for (final m in RegExp(r"'[^']*'|" r'"[^"]*"').allMatches(l)) {
          if (promise.hasMatch(m.group(0)!)) {
            offenders.add('${f.path}:${i + 1}: ${m.group(0)}');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}

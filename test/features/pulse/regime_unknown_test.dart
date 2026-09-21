import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Pulse regime bar must not answer "Quiet" for a regime it cannot place.
///
/// `_RegimeBar` lights whichever of its five segments matches the engine's
/// regime string. Those five are the whole of the engine's `MarketRegime`
/// enum today (`src/regime.py`), so the `default:` branch is reached only
/// when the engine adds a sixth or reports none — and in both cases **no
/// segment lights up**. Returning 'Quiet' there printed a confident label
/// over an unlit bar: a subscriber is told the market is calm on the
/// strength of a value the app could not read.
///
/// A quiet market and an unreadable one are different facts, and the
/// reassuring one is the dangerous direction on a money screen (CLAUDE.md).
///
/// Source assertions rather than a widget pump: `_RegimeBar` is private and
/// the defect is which STRING the fallback yields, which is fully decided in
/// these two lines.
void main() {
  final page = File('lib/features/pulse/pulse_page.dart').readAsStringSync();
  final repo = File('lib/data/repository.dart').readAsStringSync();

  test('an unplaceable regime is not labelled Quiet', () {
    // The banned shape is the two case labels sharing one return: a
    // `case 'QUIET':` falling straight into `default:`.
    final fallsThrough = RegExp(
      r"case 'QUIET':\s*\n\s*default:",
      multiLine: true,
    );
    expect(
      fallsThrough.hasMatch(page),
      isFalse,
      reason: "'QUIET' and default share a branch, so a regime this build "
          'cannot place renders as a quiet market with no segment lit.',
    );
  });

  test('the fallback renders the engine\'s own word, or Unknown', () {
    expect(
      page.contains("regime.trim().isEmpty ? 'Unknown' : regime.trim()"),
      isTrue,
      reason: 'A new engine regime should arrive named rather than disguised '
          'as one of the five this build happens to know.',
    );
  });

  test('an absent regime is not defaulted to a real market state', () {
    expect(
      repo.contains("j['regime'] as String? ?? 'RANGING'"),
      isFalse,
      reason: 'Defaulting an absent regime to RANGING lights a segment and '
          'states a market condition nothing reported.',
    );
  });
}

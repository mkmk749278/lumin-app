import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The welcome screen must not quote a roster size it cannot check.
///
/// It runs BEFORE auth, so it has no [LuminRepository] and cannot ask the
/// engine anything. Every figure on it is therefore a constant asserting a
/// property of a moving system — the defect class both companion repos
/// record under several names.
///
/// It shipped with "15 AI analysts", twice. That 15 was `kAgents.length`: a
/// DESCRIPTION table, not the roster. Measured 2026-09-21 the engine was
/// running **29** setup classes, so the very first claim a prospective
/// subscriber read understated the product by half — and it would have gone
/// on being wrong by a different amount after every evaluator the engine
/// adds, with nothing in this repo to notice.
///
/// The live count belongs on the Agents page, which walks the engine's own
/// roster (`agent_roster_test.dart` pins that).
void main() {
  final src =
      File('lib/features/onboarding/pages/welcome_page.dart').readAsStringSync();
  final code = src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('no hardcoded analyst count', () {
    expect(
      RegExp(r'\d+\s*AI analysts').hasMatch(code),
      isFalse,
      reason: 'A number here cannot be checked against the engine and will '
          'go stale on the next evaluator. Say "AI analysts" and let the '
          'Agents page carry the count.',
    );
    expect(
      RegExp(r'\d+\s*(AI\s*)?analysts score').hasMatch(code),
      isFalse,
      reason: 'Same claim in the how-it-works step.',
    );
  });

  test('the pair claim is a floor, not an exact figure', () {
    // The scanner promotes movers into its universe for hours at a time, so
    // the live count sits above the core 75 rather than on it. Any bare
    // "N pairs" without a "+" asserts an exactness the app cannot hold.
    final bare = RegExp(r'(?<!\+)(?<!\+ )\b\d+ pairs\b');
    final offenders = bare
        .allMatches(code)
        .map((m) => m.group(0))
        .where((m) => !code.contains('${m!.split(' ').first}+ pairs'))
        .toList();
    expect(
      offenders,
      isEmpty,
      reason: 'Found an exact pair count: $offenders. Use "N+".',
    );
  });

  test('kAgents is not counted anywhere outside the agents feature', () {
    // kAgents is a description table. Anything that renders its length is
    // reporting how much COPY this build carries, not what the engine runs.
    for (final dir in const ['lib/features/onboarding', 'lib/features/pulse']) {
      for (final f in Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final body = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(
          body.contains('kAgents.length'),
          isFalse,
          reason: '${f.path} renders the size of the description table.',
        );
      }
    }
  });
}

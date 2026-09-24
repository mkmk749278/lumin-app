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

  test('the stop-loss claim discloses gap risk and names its scope', () {
    // 2026-09-24 audit: "Every open trade is placed with a stop-loss" was
    // absolute where the product is not — a user's own trade may be
    // entry-only — and never said a fast market can move past a stop.
    expect(code, isNot(contains('Every open trade is placed')));
    expect(code, contains('from a signal carries a stop-loss'));
    expect(code, contains('can be larger than planned'));
    expect(code, contains('yours to protect'));
    expect(RegExp(r'runaway loss', caseSensitive: false).hasMatch(code),
        isFalse);
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

  // The two tests above cover the welcome screen. These two sweep the WHOLE
  // of lib/, because that is where this keeps happening: the first fix
  // handled welcome_page.dart, and the Menu's "The 15 setup specialists"
  // was still on screen an hour later — found by rendering the app, not by
  // the guard that had just shipped. A guard scoped to the file where a
  // defect was noticed is silent by construction on the next file.
  group('no surface quotes a roster size it cannot check', () {
    // kAgents is a DESCRIPTION table. Its length is how much copy this build
    // carries, never what the engine runs. Only the agents feature may name
    // it, and even there only as the offline fallback's own count.
    final offenders = <String>[];
    final counts = <String>[];

    setUpAll(() {
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final body = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (!f.path.startsWith('lib/features/agents/') &&
            body.contains('kAgents.length')) {
          offenders.add(f.path);
        }
        // A literal count immediately in front of a roster noun, anywhere in
        // a user-facing string.
        final m = RegExp(
          r'\b\d{1,3}\s+(?:AI\s+|setup\s+)?'
          r'(?:analysts|agents|specialists|evaluators|strategies|setups)\b',
          caseSensitive: false,
        ).firstMatch(body);
        if (m != null) counts.add('${f.path}: "${m.group(0)}"');
      }
    });

    test('kAgents.length is rendered only inside the agents feature', () {
      expect(offenders, isEmpty,
          reason: 'These render the size of the description table: $offenders');
    });

    test('no literal roster count anywhere in lib/', () {
      expect(counts, isEmpty,
          reason: 'A number here goes stale on the next evaluator the engine '
              'adds, and nothing in this repo will notice: $counts');
    });
  });
}

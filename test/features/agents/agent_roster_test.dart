/// The Agents page must show what the ENGINE runs, not what this app has
/// written descriptions for.
///
/// Measured 2026-09-21: the engine declared 29 `SetupClass` values and
/// `kAgents` described 15. The page iterated `kAgents`, so the other 14 had no
/// card — including `MOVER_TREND_PULLBACK`, which produces most of the signals
/// a subscriber actually receives, and whose stats were therefore unreachable
/// while the page was fetching the full roster and discarding it.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/agents/agent_data.dart';

void main() {
  group('agentForSetup', () {
    test('a described setup keeps its brand, tagline and icon', () {
      final a = agentForSetup('SR_FLIP_RETEST');
      expect(a.name, 'The Architect');
      expect(a.tagline, 'Structural levels & flip retests');
      expect(a.icon, isNot(Icons.insights_outlined));
    });

    test('accepts the spaced form a signal carries', () {
      expect(agentForSetup('SR FLIP RETEST').name, 'The Architect');
      expect(agentForSetup('sr_flip_retest').name, 'The Architect');
    });

    test('an UNDESCRIBED setup still produces a card', () {
      // The whole defect: these used to render nothing at all.
      for (final id in const ['MOVER_TREND_PULLBACK', 'MOVER_AVWAP_SCALP']) {
        final a = agentForSetup(id);
        expect(a.id, id);
        expect(a.name, isNotEmpty);
        expect(a.tagline, isNotEmpty);
      }
    });

    test('prefers the engine\'s own display name when we have no entry', () {
      final a = agentForSetup(
        'SOME_NEW_EVALUATOR',
        engineDisplayName: 'The Newcomer',
      );
      expect(a.name, 'The Newcomer');
    });

    test('falls back to a readable name when the engine sends none', () {
      final a = agentForSetup('MOVER_TREND_PULLBACK');
      expect(a.name, 'Mover trend pullback');
      expect(a.name, isNot(contains('_')));
    });

    test('an empty engine display name does not win over the readable one',
        () {
      // `displayName: ''` is a real shape from a partially-populated stat.
      final a = agentForSetup('MOVER_AVWAP_SCALP', engineDisplayName: '   ');
      expect(a.name, 'Mover avwap scalp');
    });

    test('does NOT invent a description of how an unknown setup trades', () {
      // A plausible-sounding strategy write-up nobody authored is worse than
      // an honest gap on a screen a subscriber reads before risking money.
      final a = agentForSetup('MOVER_TREND_PULLBACK');
      expect(a.specialty, contains('does not carry a written description'));
    });
  });

  group('the page is driven by the engine, not by kAgents', () {
    test('kAgents is no longer what the list length comes from', () {
      final src =
          File('lib/features/agents/agents_page.dart').readAsStringSync();
      // The regression: `itemCount: kAgents.length` and
      // `'${kAgents.length} AI specialists'`.
      expect(
        src.contains('itemCount: kAgents.length'),
        isFalse,
        reason: 'the list is iterating the local description table again',
      );
      expect(
        RegExp(r'\$\{kAgents\.length\} AI specialists').hasMatch(src),
        isFalse,
        reason: 'the header is claiming a count it did not get from the engine',
      );
    });

    test('the roster comes from watchAgents and is dressed per setup', () {
      final src =
          File('lib/features/agents/agents_page.dart').readAsStringSync();
      expect(src, contains('watchAgents()'));
      expect(src, contains('agentForSetup('));
    });

    test('kAgents survives as the offline fallback', () {
      // Losing it entirely would leave an empty page when the engine is
      // unreachable, which is worse than the built-in descriptions.
      final src =
          File('lib/features/agents/agents_page.dart').readAsStringSync();
      expect(src, contains('kAgents'));
      expect(src, contains('built-in descriptions'));
    });
  });

  // Drift detector against the engine's own enum.
  //
  // This is the check that would have caught the original defect. It does NOT
  // require kAgents to describe everything — that is a copywriting backlog,
  // not a correctness bar, and failing CI over a missing paragraph would get
  // the assertion deleted. What it pins is that every setup the engine can
  // emit produces a usable card, which is the property that broke.
  //
  // Skipped when the engine repo is not checked out beside the app — and CI
  // does not check it out either, so this runs on a local side-by-side
  // checkout and nowhere else. That is a real gap, stated rather than implied.
  group('against the engine\'s SetupClass enum', () {
    // $ENGINE_REPO first, then the conventional sibling checkout. Never a
    // hardcoded absolute path: this repo's companion has three tests that
    // pinned one container's layout and therefore skipped silently on every
    // other machine.
    final envRepo = Platform.environment['ENGINE_REPO'];
    final engineRepo = (envRepo != null && envRepo.trim().isNotEmpty)
        ? envRepo.trim()
        : '../360-v2';
    final enumFile = File('$engineRepo/src/signal_quality.py');

    test('every engine setup class resolves to a named, described card', () {
      if (!enumFile.existsSync()) {
        markTestSkipped(
          'no engine repo beside the app (set ENGINE_REPO) — and CI never '
          'checks it out either, so nothing guards this contract there',
        );
        return;
      }
      final src = enumFile.readAsStringSync();
      final start = src.indexOf('class SetupClass(str, Enum):');
      expect(start, greaterThan(-1), reason: 'SetupClass moved');
      final body = src.substring(start, start + 8000);
      final ids = RegExp(r'^\s{4}([A-Z][A-Z0-9_]+) = "', multiLine: true)
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
      expect(ids.length, greaterThan(20), reason: 'parsed too few setups');

      for (final id in ids) {
        final a = agentForSetup(id);
        expect(a.name.trim(), isNotEmpty, reason: '$id has no name');
        expect(a.tagline.trim(), isNotEmpty, reason: '$id has no tagline');
        expect(a.name, isNot(contains('_')),
            reason: '$id renders the raw enum at the reader');
      }
    });
  });
}

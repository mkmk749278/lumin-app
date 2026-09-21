import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/mock_data.dart';

/// The confidence figure and the engine's letter grade are two stamps taken
/// at different points in scoring, and they must never be rendered as one
/// reading.
///
/// The engine writes `quality_tier` **once** — in `scanner/__init__.py`, from
/// the component total at the moment the setup is scored (>=90 A+, >=82 A,
/// >=74 B, else C). It then rewrites `sig.confidence` twelve more times on
/// the way to dispatch (chart-pattern bonus, decay, composite rescore,
/// structural flow, price-action and distance penalties, a x0.85 haircut,
/// transition and confluence boosts) and never regrades the tier against it.
///
/// So the pair is routinely non-monotonic. The live feed carried `65.9 · A`,
/// `81.5 · C` and `90.5 · B` on screen together (2026-09-21) while the card
/// read "CONFIDENCE 73.9 · A" and its sheet said "scored out of 100 and
/// graded A+ to C" — copy asserting an arithmetic the engine does not
/// perform. A subscriber reading that has to conclude one of the two numbers
/// is broken; both are correct and they describe different moments.
///
/// These are source assertions rather than widget pumps because the defect is
/// a STRING SHAPE, not a rendered state: a middot or a parenthesis between
/// the two values is what makes the false claim, and it can be reintroduced
/// anywhere without changing any behaviour a widget test observes.
void main() {
  group('confidence and setup grade are never one reading', () {
    final sources = <String, String>{
      for (final p in const [
        'lib/features/signals/signals_page.dart',
        'lib/features/pulse/pulse_page.dart',
      ])
        p: _withoutComments(File(p).readAsStringSync()),
    };

    test('no surface joins the confidence figure and the tier in one string',
        () {
      // The shapes that make the claim: "73.9 · A", "73.9 (A)", "73.9 / A".
      // Matched on the interpolations rather than on rendered text, because
      // the values are computed and never appear as literals in source.
      final joined = RegExp(
        r'confidence[^\n]{0,40}?\}[^\n]{0,6}?\$\{?[A-Za-z_.]*tier',
        caseSensitive: false,
      );
      for (final entry in sources.entries) {
        expect(
          joined.hasMatch(entry.value),
          isFalse,
          reason:
              '${entry.key} interpolates the confidence figure and the tier '
              'into one string. The letter does not grade the number — give '
              'it its own caption.',
        );
      }
    });

    test('the badge captions the letter as a grade of the SETUP', () {
      final src = sources['lib/features/signals/signals_page.dart']!;
      expect(
        src.contains('SETUP GRADE'),
        isTrue,
        reason: 'The letter needs a caption naming what it grades. Without '
            'one it reads as a grade of the confidence figure beside it.',
      );
    });

    test('the explain sheet no longer says the score is graded A+ to C', () {
      final src = sources['lib/features/signals/signals_page.dart']!;
      expect(
        src.contains('graded A+ to C'),
        isFalse,
        reason: 'That sentence says the letter grades the 0-100 score. It '
            'does not — the tier is stamped before the score is finished.',
      );
    });
  });

  group('an ungraded signal gets no invented letter', () {
    test('MockSignal.fromMap leaves tier empty when the engine sent none',
        () {
      final s = MockSignal.fromMap(const <String, dynamic>{});
      expect(
        s.tier,
        '',
        reason: 'A default letter puts a grade on screen that nothing '
            'produced. Absent and "B" are different facts.',
      );
    });

    test('a reported tier survives untouched', () {
      final s = MockSignal.fromMap(const <String, dynamic>{'tier': 'A+'});
      expect(s.tier, 'A+');
    });
  });
}

/// Strips `//` line comments so the doc headers explaining this rule — which
/// necessarily quote the very shapes being banned — cannot fail the guard.
String _withoutComments(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
    .join('\n');

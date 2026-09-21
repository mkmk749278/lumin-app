import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/mock_data.dart';

/// Both halves of the excursion, and a caption that names what happened.
///
/// The engine publishes `max_favorable_excursion_pct` **and**
/// `max_adverse_excursion_pct` on every signal. This app read only the first
/// — so the outcome card showed a subscriber how far a trade ran their way
/// and never how far it went against them first. That is the flattering half
/// shown alone on a money screen, and the gap between them is exactly the
/// drawdown somebody had to sit through to collect the result beside it.
/// "MFE without MAE bounds nothing" is a rule both companion repos already
/// carry; nothing had applied it here.
///
/// Separately, the peak's caption read "Max profit before SL" for every
/// closed signal, conditional on closed/open alone. A signal that closed at
/// Target 1 never went near its stop, so the caption named an event that did
/// not happen.
void main() {
  group('MAE is plumbed and is not defaulted', () {
    test('an engine that did not report MAE leaves it null', () {
      final s = MockSignal.fromMap(const <String, dynamic>{});
      expect(
        s.maxAdverseExcursionPct,
        isNull,
        reason: 'A 0.0 substitute claims the trade never went against the '
            'entry, which is the one reading nothing supports.',
      );
    });

    test('a reported MAE survives the round trip', () {
      final s = MockSignal.fromMap(
        const <String, dynamic>{'maxAdverseExcursionPct': -1.75},
      );
      expect(s.maxAdverseExcursionPct, -1.75);
      expect(
        MockSignal.fromMap(s.toMap()).maxAdverseExcursionPct,
        -1.75,
        reason: 'toMap/fromMap is a contract; a field added to the model and '
            'dropped by the serializer is invisible at both ends.',
      );
    });

    test('the live repository reads the engine\'s own key', () {
      final repo = File('lib/data/repository.dart').readAsStringSync();
      expect(repo.contains("j['max_adverse_excursion_pct']"), isTrue);
      expect(
        RegExp(r"max_adverse_excursion_pct'\] as num\?\)\?\.toDouble\(\) \?\?")
            .hasMatch(repo),
        isFalse,
        reason: 'A default here turns "the engine did not say" into "it never '
            'drew down".',
      );
    });
  });

  group('the outcome card', () {
    final page =
        File('lib/features/signals/signals_page.dart').readAsStringSync();
    final code = page
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('renders the adverse half', () {
      expect(
        code.contains("'Worst drawdown'") && code.contains("'Worst so far'"),
        isTrue,
        reason: 'The peak renders alone, which is the flattering half of a '
            'two-sided measurement.',
      );
    });

    test('does not caption every close as a stop-out', () {
      expect(
        code.contains('Max profit before SL'),
        isFalse,
        reason: 'A signal that closed at Target 1 never reached its stop, so '
            'this caption names an event that did not happen.',
      );
    });
  });
}

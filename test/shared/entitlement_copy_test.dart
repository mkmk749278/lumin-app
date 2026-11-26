import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/entitlement_copy.dart';

/// Three screens used to state three different entitlement rules
/// (2026-11-26). Live signals need the Signals plan after 3 free days;
/// the sentences that said otherwise must not come back.
void main() {
  test('the shared sentence says live signals are paid after the trial', () {
    expect(EntitlementCopy.summary, contains('Closed signals'));
    expect(EntitlementCopy.summary, contains('Signals plan after 3 free days'));
  });

  test('no screen claims signals are free outright', () {
    final banned = RegExp(
      r'(Signals stay free|Signals, levels & charts are free)',
    );
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // Doc comments may quote the old sentences; only code reaches a screen.
      final code = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (banned.hasMatch(code)) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}

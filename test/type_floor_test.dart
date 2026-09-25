import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The theme sets 11px as the floor (`labelSmall`), and until 2026-09-23 the
/// call sites ignored it: 114 hand-written sizes sat below it — 8.5, 9, 9.5,
/// 10, 10.5 — including the month calendar's day numbers and the regime
/// labels. Swept across the whole of lib/, including both arms of a ternary,
/// so the next hand-styled Text cannot quietly dip under it again.
void main() {
  test('no hand-written fontSize below the 11px floor', () {
    final number = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])');
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        final m = RegExp(r'fontSize:\s*([^,\n]*)').firstMatch(l);
        if (m == null) continue;
        for (final n in number.allMatches(m.group(1)!)) {
          if (double.parse(n.group(1)!) < 11) {
            offenders.add('${f.path}:${i + 1}: ${l.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use 11 or a theme role. Where space is tight, let the text '
            'scale down (FittedBox) or truncate rather than shrinking it for '
            'everyone.');
  });

  // UX review 2026-09-25: 21 sizes sat on half points (11.5 / 12.5 / 13.5)
  // between the scale's whole steps — each one a near-duplicate of its
  // neighbour that made two lines of the same role read as slightly different
  // fonts. The theme's own roles are whole points; so are the call sites now.
  test('no hand-written half-point fontSize', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        if (RegExp(r'fontSize:\s*\d+\.\d').hasMatch(l)) {
          offenders.add('${f.path}:${i + 1}: ${l.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Round to the nearest whole point.');
  });
}

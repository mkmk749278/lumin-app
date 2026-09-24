/// No user-facing string interpolates a raw exception (2026-09-24).
///
/// The 2026-09-23 fix covered the screens that LOAD; the next day's audit
/// still counted 28 action sites rendering `'$e'` — phone sign-in, OTP
/// resend, profile, account deletion, Play-billing verification and the
/// crypto checkout among them — because a fix applied to a list of screens is
/// silent on the next screen.  This derives the requirement from the tree
/// instead: any `$e` / `${e}` / `${e.toString()}` inside a string literal in
/// `lib/` fails, unless the line is a log call or on the allow-list below
/// with its reason.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `path:needle` pairs that are allowed, each with why.
const _allowed = <String, String>{
  // Wrapped into a FirebaseAuthException whose CODE is what the UI maps
  // (friendlyAuthError('web-phone-auth-failed')); the message is not shown.
  "lib/data/auth_service.dart:message: '\$e'": 'mapped by code, not shown',
};

final _raw = RegExp(r"""(['"])[^'"\n]*(\$e\b|\$\{e\}|\$\{e\.toString\(\)\})""");
final _logCall = RegExp(r'(debugPrint|print|log|developer\.log)\(');

void main() {
  test('no user-facing string renders a raw exception', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (!_raw.hasMatch(line) || _logCall.hasMatch(line)) continue;
        final path = f.path.replaceAll('\\', '/');
        final ok = _allowed.keys.any((k) {
          final sep = k.indexOf(':');
          return path.endsWith(k.substring(0, sep)) &&
              line.contains(k.substring(sep + 1));
        });
        if (!ok) offenders.add('$path:${i + 1}: ${line.trim()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use friendlyActionError / friendlyLoadError '
            '(lib/shared/friendly_error.dart):\n${offenders.join('\n')}');
  });
}

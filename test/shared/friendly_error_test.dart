import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumin/data/api_client.dart';
import 'package:lumin/shared/friendly_error.dart';

/// Seven screens rendered `'$e'` / `e.toString()` / the raw engine detail
/// into their error card until 2026-09-23, so a dropped connection read
/// "ClientException: Connection closed before full header was received".
void main() {
  group('friendlyLoadError', () {
    test('never shows an exception type name', () {
      final samples = <Object>[
        http.ClientException('Connection closed before full header'),
        const SocketException('Failed host lookup'),
        TimeoutException('x'),
        StateError('bad state'),
        FormatException('Unexpected character'),
        ApiError(0, 'network'),
        ApiError(500, 'Traceback (most recent call last)'),
        ApiError(418, 'phase=entry code=BINANCE_HTTP_ERROR'),
      ];
      for (final e in samples) {
        final s = friendlyLoadError(e, what: 'your settings');
        expect(s, isNot(contains('Exception')), reason: '$e -> $s');
        expect(s, isNot(contains('Error')), reason: '$e -> $s');
        expect(s, isNot(contains('Traceback')), reason: '$e -> $s');
        expect(s, isNot(contains('phase=')), reason: '$e -> $s');
      }
    });

    test('offline failures say so', () {
      expect(friendlyLoadError(http.ClientException('x')),
          contains('internet connection'));
      expect(friendlyLoadError(ApiError(0, 'x')),
          contains('internet connection'));
    });

    test('server failures name what failed and do not blame the user', () {
      final s = friendlyLoadError(ApiError(503, 'x'), what: 'your settings');
      expect(s, contains('your settings'));
      expect(s, contains('try again'));
    });

    test('an expired session points at sign-in', () {
      expect(friendlyLoadError(ApiError(401, 'x')), contains('Sign in'));
    });
  });

  group('friendlyAuthError', () {
    test('known codes get plain copy', () {
      expect(friendlyAuthError('invalid-phone-number'),
          contains("doesn't look right"));
      expect(friendlyAuthError('too-many-requests'), contains('Too many'));
      expect(friendlyAuthError('network-request-failed'),
          contains('internet connection'));
    });

    test('an unknown code keeps the code for support and nothing else', () {
      final s = friendlyAuthError('some-new-code', action: 'verify the code');
      expect(s, contains('verify the code'));
      expect(s, contains('(some-new-code)'));
    });
  });

  test('no screen renders an exception string as its error copy', () {
    // Derived from the tree: the seven screens fixed here are not a list
    // this test knows about. `'$e'` and `e.toString()` assigned to an
    // error field, or interpolated into one, is the defect shape.
    // The first cut matched only a variable named `e`, and missed the main
    // Signals feed's `error: error.toString()` and two `snap.error` sites —
    // so the shape is any exception-ish identifier, not one spelling.
    final shape = RegExp(
        r"""(error|_error|_loadError|_errorText|message)\s*[:=]\s*"""
        r"""("[^"]*\$\{?(e|err|error)\b|'[^']*\$\{?(e|err|error)\b|"""
        r"""(e|err|error|snap\.error|snapshot\.error)\.toString\(\))""");
    final offenders = <String>[];
    for (final f in Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (shape.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Route errors through friendlyLoadError / friendlyAuthError.');
  });

  group('friendlyActionError', () {
    const action = 'save your settings';

    test('never shows an exception type name', () {
      final samples = <Object>[
        http.ClientException('Connection closed before full header'),
        const SocketException('Failed host lookup'),
        TimeoutException('x'),
        StateError('bad state'),
        FormatException('Unexpected character'),
        ApiError(0, 'network'),
        ApiError(500, 'Traceback (most recent call last)'),
        ApiError(418, 'phase=entry code=BINANCE_HTTP_ERROR'),
      ];
      for (final e in samples) {
        final s = friendlyActionError(e, action: action);
        expect(s, isNot(contains('Exception')), reason: '$e -> $s');
        expect(s, isNot(contains('Error')), reason: '$e -> $s');
        expect(s, isNot(contains('Traceback')), reason: '$e -> $s');
        expect(s, isNot(contains('phase=')), reason: '$e -> $s');
      }
    });

    test('a lost reply is "could not confirm", never "failed"', () {
      // The action may have landed: saying it failed invites a second
      // attempt at something already done.
      for (final e in <Object>[
        TimeoutException('x'),
        http.ClientException('x'),
        const SocketException('x'),
        ApiError(0, 'x'),
        ApiError(408, 'x'),
      ]) {
        final s = friendlyActionError(e, action: action);
        expect(s, contains("couldn't confirm"), reason: '$e -> $s');
        expect(s, contains(action), reason: '$e -> $s');
        expect(s.toLowerCase(), isNot(contains('failed')), reason: '$e -> $s');
      }
    });

    test('names the session, plan and rate-limit cases', () {
      expect(friendlyActionError(ApiError(401, 'x'), action: action),
          contains('session has expired'));
      expect(friendlyActionError(ApiError(403, 'x'), action: action),
          contains('plan'));
      expect(friendlyActionError(ApiError(429, 'x'), action: action),
          contains('Too many requests'));
    });

    test('a server error says whose side it was on', () {
      expect(friendlyActionError(ApiError(503, 'x'), action: action),
          contains("Lumin's servers couldn't $action"));
    });

    test('an unknown error still reads as plain copy', () {
      expect(friendlyActionError(StateError('x'), action: action),
          "Couldn't $action. Please try again.");
    });
  });
}

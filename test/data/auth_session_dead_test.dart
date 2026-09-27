// The auth gate signs a user out only when a failed token refresh means the
// session is DEAD.  Owner, 2026-09-27: cold starts after clearing the app
// from recents were dropping signed-in users back to "Sign up" — the gate
// signed out on any error, a network blip right after launch included.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/auth_service.dart';

void main() {
  test('a dead account signs out', () {
    for (final code in AuthService.deadSessionCodes) {
      expect(AuthService.sessionIsDead(FirebaseAuthException(code: code)), isTrue,
          reason: code);
    }
  });

  test('an unreachable network, a rate limit or an internal error keeps the session',
      () {
    for (final code in [
      'network-request-failed',
      'too-many-requests',
      'internal-error',
      'unknown',
    ]) {
      expect(AuthService.sessionIsDead(FirebaseAuthException(code: code)), isFalse,
          reason: code);
    }
  });

  test('a non-Firebase error never signs anyone out', () {
    expect(AuthService.sessionIsDead(Exception('socket closed')), isFalse);
    expect(AuthService.sessionIsDead(PlatformException(code: 'network')), isFalse);
  });
}

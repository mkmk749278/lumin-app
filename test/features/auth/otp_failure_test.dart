/// The OTP screen must never report a failure over a live session.
///
/// Reported 2026-07-27: the code screen showed "That code expired" and would
/// not move on, but force-quitting and relaunching the app landed the user
/// straight in the shell — they had been signed in the whole time.
///
/// Two things caused it, and this file pins the decision half.
///
/// Android SMS auto-retrieval signs the user in through Firebase's
/// `verificationCompleted` callback, and doing so **consumes the verification
/// session**. A Verify tap that lands afterwards therefore throws
/// `session-expired` against an exchange that had already succeeded. The page
/// branched on `e.code` alone, so it rendered an expiry error to an
/// authenticated account.
///
/// (The other half — the page sitting on a route pushed *above* `_AuthGate`,
/// so a gate re-route rebuilt underneath it and never removed this screen —
/// is structural and covered by the widget tree, not here.)
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/auth/pages/otp_entry_page.dart';

void main() {
  group('classifyOtpFailure', () {
    test('a live session outranks session-expired', () {
      // The exact reported case: auto-retrieval already signed the user in,
      // so the expiry is about a redundant attempt, not about the account.
      expect(
        classifyOtpFailure(code: 'session-expired', signedIn: true),
        OtpFailureAction.completeSignIn,
      );
    });

    test('a live session outranks every other code too', () {
      // None of these codes describe account state — they describe one
      // exchange attempt. If we are signed in, the attempt is moot whatever
      // it says.
      for (final code in const [
        'invalid-verification-code',
        'invalid-verification-id',
        'quota-exceeded',
        'network-request-failed',
        '',
      ]) {
        expect(
          classifyOtpFailure(code: code, signedIn: true),
          OtpFailureAction.completeSignIn,
          reason: '$code must not block an already-authenticated user',
        );
      }
    });

    test('session-expired while signed out asks for a fresh code', () {
      expect(
        classifyOtpFailure(code: 'session-expired', signedIn: false),
        OtpFailureAction.promptResend,
      );
    });

    test('a wrong code while signed out is retryable in place', () {
      // Distinct from promptResend on purpose: the session is still good, so
      // sending a new SMS here would be a pointless round-trip.
      expect(
        classifyOtpFailure(code: 'invalid-verification-code', signedIn: false),
        OtpFailureAction.promptRetryCode,
      );
    });

    test('an unrecognised code falls back to the SDK message', () {
      expect(
        classifyOtpFailure(code: 'too-many-requests', signedIn: false),
        OtpFailureAction.showMessage,
      );
    });
  });
}

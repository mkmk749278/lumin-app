/// Tests for the Play Store in-app account deletion data layer
/// (A4-partial, 2026-05-20).
///
/// What we pin:
///
/// * MockRepository.deleteAccount is a no-op (widget tests + offline
///   dev hit the same code path without a network round-trip).
/// * DeleteAccountException stringifies in a useful debug form.
/// * The exception carries the backend tag verbatim so callers
///   matching on ``tag`` can reliably distinguish failure modes.
///
/// HttpRepository.deleteAccount + the ApiError-to-DeleteAccountException
/// translation is covered in test/data/http_repository_test.dart (the
/// HttpRepository scaffolding this header once declared out of scope
/// shipped 2026-07-17).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

void main() {
  group('MockRepository.deleteAccount', () {
    test('completes without error (no-op)', () async {
      final repo = MockRepository();
      // Should NOT throw — pin the no-op behaviour so future changes
      // to MockRepository don't accidentally introduce a side-effect
      // here that breaks widget tests of the delete flow.
      await repo.deleteAccount();
    });

    test('can be called repeatedly', () async {
      final repo = MockRepository();
      await repo.deleteAccount();
      await repo.deleteAccount();
      await repo.deleteAccount();
      // Idempotent: the real endpoint is idempotent on 204; the mock
      // mirrors that semantics so widget-test retries don't blow up.
    });
  });

  group('DeleteAccountException', () {
    test('preserves the backend tag verbatim', () {
      const e = DeleteAccountException(
        'key_blob_delete_failed',
        'Could not revoke your Binance API key on our server.',
      );
      // Callers that switch on .tag (e.g. analytics, retry policies)
      // need an exact match against the engine's contract — see
      // src/api/account_routes.py for the source of truth on tags.
      expect(e.tag, 'key_blob_delete_failed');
    });

    test('carries the human-readable message', () {
      const e = DeleteAccountException(
        'user_row_delete_failed',
        'Your Binance key was revoked but the account row could not be '
            'removed.',
      );
      expect(e.message, contains('revoked but the account row could not'));
    });

    test('toString includes both tag and message for debug logs', () {
      const e = DeleteAccountException('user_lookup_failed', 'lookup blew up');
      final s = e.toString();
      expect(s, contains('user_lookup_failed'));
      expect(s, contains('lookup blew up'));
    });

    test('is an Exception subtype (catchable by `on Exception`)', () {
      Object? caught;
      try {
        throw const DeleteAccountException('any', 'any');
      } on Exception catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught, isA<DeleteAccountException>());
    });
  });
}

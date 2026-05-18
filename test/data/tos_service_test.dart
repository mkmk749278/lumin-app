/// Tests for ``lib/data/tos_service.dart``.
///
/// SharedPreferences is replaced with an in-memory implementation
/// via ``SharedPreferences.setMockInitialValues`` so the test runs
/// without platform plugins.  What we pin:
///
/// * Fresh install (no stored acceptance) → ``isCurrentVersionAccepted``
///   is false.
/// * After ``recordAcceptance`` at the current version →
///   ``isCurrentVersionAccepted`` is true.
/// * Stored acceptance at an OLDER version (after a doctrine bump) →
///   ``isCurrentVersionAccepted`` is false.
/// * ``recordAcceptance`` stamps a recent ``acceptedAt`` + a non-
///   empty ``userAgent``.
/// * Corrupted JSON in storage → graceful read returning null (gate
///   fires).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/tos_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Reset SharedPreferences before each test so per-test state
    // doesn't leak.  Empty initial values = fresh-install state.
    SharedPreferences.setMockInitialValues({});
  });

  group('fresh install', () {
    test('isCurrentVersionAccepted is false', () async {
      final svc = TosService();
      expect(await svc.isCurrentVersionAccepted(), isFalse);
    });

    test('readAcceptance returns null', () async {
      final svc = TosService();
      expect(await svc.readAcceptance(), isNull);
    });
  });

  group('after recordAcceptance at current version', () {
    test('isCurrentVersionAccepted is true', () async {
      final svc = TosService();
      await svc.recordAcceptance();
      expect(await svc.isCurrentVersionAccepted(), isTrue);
    });

    test('readAcceptance returns the stored value', () async {
      final svc = TosService();
      final pre = DateTime.now().toUtc();
      final stored = await svc.recordAcceptance();
      final read = await svc.readAcceptance();
      expect(read, isNotNull);
      expect(read!.version, latestTosVersion);
      // userAgent is non-empty (Platform-derived).
      expect(read.userAgent.isNotEmpty, isTrue);
      // acceptedAt is recent (within a few seconds of the test).
      expect(
        read.acceptedAt.isAfter(pre.subtract(const Duration(seconds: 5))),
        isTrue,
      );
      expect(read.acceptedAt, stored.acceptedAt);
    });
  });

  group('stale acceptance after doctrine version bump', () {
    test('older stored version → isCurrentVersionAccepted is false', () async {
      // Inject a stale acceptance directly into prefs.  Verifies
      // that the version compare actually fires — a regression
      // where every stored acceptance was treated as current would
      // silently bypass the re-prompt after a doctrine change.
      SharedPreferences.setMockInitialValues({
        'tos_acceptance': jsonEncode({
          'version': '0.0',  // pretend an old version
          'accepted_at': DateTime.now().toUtc().toIso8601String(),
          'user_agent': 'test',
        }),
      });
      final svc = TosService();
      expect(await svc.isCurrentVersionAccepted(), isFalse);
    });
  });

  group('corrupted storage', () {
    test('non-JSON value → readAcceptance returns null', () async {
      SharedPreferences.setMockInitialValues({
        'tos_acceptance': 'this-is-not-json',
      });
      final svc = TosService();
      expect(await svc.readAcceptance(), isNull);
      // And the gate fires (no acceptance = not current).
      expect(await svc.isCurrentVersionAccepted(), isFalse);
    });

    test('JSON missing required fields → readAcceptance returns a default', () async {
      SharedPreferences.setMockInitialValues({
        'tos_acceptance': jsonEncode({}),  // empty object
      });
      final svc = TosService();
      // Returns a TosAcceptance with empty fields rather than null —
      // because the JSON decode succeeded.  isCurrentVersionAccepted
      // then fires because version is empty (older than latest).
      final read = await svc.readAcceptance();
      expect(read, isNotNull);
      expect(read!.version, '');
      expect(await svc.isCurrentVersionAccepted(), isFalse);
    });
  });

  group('clearAcceptance', () {
    test('drops the stored acceptance', () async {
      final svc = TosService();
      await svc.recordAcceptance();
      expect(await svc.isCurrentVersionAccepted(), isTrue);
      await svc.clearAcceptance();
      expect(await svc.isCurrentVersionAccepted(), isFalse);
    });
  });
}

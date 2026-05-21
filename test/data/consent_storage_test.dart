/// Tests for ConsentStorage — the persistence layer behind the
/// Play Store first-run consent gate.
///
/// What we pin:
///
/// * Fresh install: ``isUpToDate`` returns false (no consent recorded).
/// * After ``recordAccepted``: ``isUpToDate`` returns true AND
///   ``storedVersion`` matches ``currentConsentVersion``.
/// * ``clear`` reverts to the fresh-install state.
/// * Lower stored version (consent version bumped between releases)
///   returns ``isUpToDate == false`` so the user re-sees the gate.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/consent_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Each test starts from a clean shared-preferences sandbox so
    // state from one test can't leak into the next.  The Flutter
    // shared_preferences package provides this in-memory shim.
    SharedPreferences.setMockInitialValues({});
  });

  test('fresh install: isUpToDate == false', () async {
    expect(await ConsentStorage.isUpToDate(), isFalse);
    expect(await ConsentStorage.storedVersion(), 0);
  });

  test('recordAccepted persists current consent version', () async {
    await ConsentStorage.recordAccepted();
    expect(await ConsentStorage.isUpToDate(), isTrue);
    expect(
      await ConsentStorage.storedVersion(),
      ConsentStorage.currentConsentVersion,
    );
  });

  test('clear reverts to fresh-install state', () async {
    await ConsentStorage.recordAccepted();
    expect(await ConsentStorage.isUpToDate(), isTrue);
    await ConsentStorage.clear();
    expect(await ConsentStorage.isUpToDate(), isFalse);
    expect(await ConsentStorage.storedVersion(), 0);
  });

  test('lower stored version → isUpToDate == false (user re-sees gate)',
      () async {
    // Pin the existing stored version directly — simulates a user who
    // accepted v0 in a prior install but the app has since bumped to v1.
    SharedPreferences.setMockInitialValues({
      'consent.version': ConsentStorage.currentConsentVersion - 1,
    });
    expect(await ConsentStorage.isUpToDate(), isFalse);
  });

  test('same stored version → isUpToDate == true', () async {
    SharedPreferences.setMockInitialValues({
      'consent.version': ConsentStorage.currentConsentVersion,
    });
    expect(await ConsentStorage.isUpToDate(), isTrue);
  });

  // ---------------------------------------------------------------------
  // welcomeSeen — first-launch brand-intro page (2026-05-21)
  // ---------------------------------------------------------------------

  test('fresh install: welcomeSeen == false', () async {
    expect(await ConsentStorage.welcomeSeen(), isFalse);
  });

  test('recordWelcomeSeen persists the flag', () async {
    await ConsentStorage.recordWelcomeSeen();
    expect(await ConsentStorage.welcomeSeen(), isTrue);
  });

  test('welcomeSeen is independent of consent version bumps', () async {
    // User completed v1 onboarding fully — welcome + consent both done.
    await ConsentStorage.recordWelcomeSeen();
    await ConsentStorage.recordAccepted();
    expect(await ConsentStorage.welcomeSeen(), isTrue);
    expect(await ConsentStorage.isUpToDate(), isTrue);

    // Simulate consent version bump — consent stale but welcome seen.
    SharedPreferences.setMockInitialValues({
      'consent.version': ConsentStorage.currentConsentVersion - 1,
      'onboarding.welcomeSeen': true,
    });
    expect(await ConsentStorage.isUpToDate(), isFalse);
    expect(
      await ConsentStorage.welcomeSeen(),
      isTrue,
      reason: 'A consent-version bump must NOT re-show the welcome '
          'page — that would feel like a UX regression to existing users',
    );
  });

  test('clear() resets BOTH welcome flag AND consent version', () async {
    await ConsentStorage.recordWelcomeSeen();
    await ConsentStorage.recordAccepted();
    expect(await ConsentStorage.welcomeSeen(), isTrue);
    expect(await ConsentStorage.isUpToDate(), isTrue);

    await ConsentStorage.clear();

    expect(await ConsentStorage.welcomeSeen(), isFalse);
    expect(await ConsentStorage.isUpToDate(), isFalse);
  });
}

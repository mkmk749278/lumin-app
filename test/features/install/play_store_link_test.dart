/// Guards for the Android → Play banner (2026-09-13).
///
/// The banner exists because a PWA install contributes nothing Google Play
/// can see — not install velocity, not retention, not listing conversion —
/// so an Android visitor left on the web app is a user who can never
/// compound into an organic recommendation. Two things about it are worth
/// pinning, because both fail *silently* in production:
///
///  1. The Play listing id is a cross-repo contract with CI's
///     `flutter create --org=... --project-name=...` flags. Get it wrong
///     and every Android visitor is sent to a Play 404 — the banner still
///     renders, still looks right, and converts nobody.
///  2. The stub environment probes must stay constant-false, because that
///     is what makes it impossible for a "Get it on Google Play" banner to
///     render *inside* the Play build. That property is enforced by which
///     file compiles, so a test is the only thing that notices if someone
///     "helpfully" gives the stub a real implementation.
///
/// Test 1 derives the expected id by parsing the workflow rather than
/// restating it: a hand-copied constant is the drift this repo has paid
/// for before, and a second copy of a contract is not a check of it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/app/pwa_environment.dart' as pwa;
import 'package:lumin/features/install/install_banner.dart';

void main() {
  group('Play listing link', () {
    test('matches the applicationId CI actually builds', () {
      final workflow = File('.github/workflows/build-apk.yml');
      expect(
        workflow.existsSync(),
        isTrue,
        reason: 'build-apk.yml is where the applicationId is decided; '
            'if it moved, this guard must follow it.',
      );
      final text = workflow.readAsStringSync();

      final org = RegExp(r'--org=([A-Za-z0-9_.]+)').firstMatch(text)?.group(1);
      final project =
          RegExp(r'--project-name=([A-Za-z0-9_]+)').firstMatch(text)?.group(1);
      expect(org, isNotNull, reason: 'no --org flag found in build-apk.yml');
      expect(project, isNotNull,
          reason: 'no --project-name flag found in build-apk.yml');

      // This is exactly how `flutter create` composes the applicationId.
      expect(
        kPlayStoreListingUrl,
        'https://play.google.com/store/apps/details?id=$org.$project',
        reason: 'The banner would send every Android visitor to a Play 404. '
            'Update kPlayStoreListingUrl to match the workflow.',
      );
    });

    test('is an https play.google.com URL, not an intent or market: scheme',
        () {
      final uri = Uri.parse(kPlayStoreListingUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'play.google.com');
      // A market:// or intent:// URL is unopenable from a desktop browser
      // and from the in-app browsers Instagram and Facebook use, which is
      // precisely the traffic this banner was built for.
      expect(uri.queryParameters['id'], isNotEmpty);
    });
  });

  group('native builds compile the stub', () {
    // These run against the stub (the test VM is not dart.library.js_interop),
    // which is the same file the Play and sideload APKs compile.
    test('every probe is false, so the Play banner cannot reach the tree', () {
      expect(pwa.isAndroidBrowser, isFalse,
          reason: 'A true value here would render "Get it on Google Play" '
              'inside the Play app itself.');
      expect(pwa.isIosBrowser, isFalse);
      expect(pwa.isStandalonePwa, isFalse);
    });

    test('the platform probes are not complements of each other', () {
      // Desktop browsers are neither iOS nor Android. If someone ever
      // rewrites one probe as !other, this fails — on the stub both are
      // false, and a complement pair can never both be false.
      expect(pwa.isIosBrowser && pwa.isAndroidBrowser, isFalse);
      expect(pwa.isIosBrowser || pwa.isAndroidBrowser, isFalse);
    });
  });
}

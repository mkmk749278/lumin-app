/// Tests for legal_urls.dart — the canonical URL constants.
///
/// These constants are pasted into the Play Console listing AND
/// linked from Settings → Legal AND will be referenced by the
/// in-app first-run consent gate in a future PR.  Pinning them
/// in tests guards against accidental rename / typo that would
/// silently 404 a user tap.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/legal_urls.dart';

void main() {
  group('LegalUrls', () {
    test('all three URLs are absolute HTTPS', () {
      final uris = [
        Uri.parse(LegalUrls.privacyUrl),
        Uri.parse(LegalUrls.termsUrl),
        Uri.parse(LegalUrls.riskUrl),
      ];
      for (final u in uris) {
        expect(u.hasScheme, isTrue, reason: '$u must be absolute');
        expect(u.scheme, 'https', reason: '$u must use HTTPS');
        expect(u.host, isNotEmpty);
      }
    });

    test('URLs share the same host (lumin-legal Pages site)', () {
      final p = Uri.parse(LegalUrls.privacyUrl);
      final t = Uri.parse(LegalUrls.termsUrl);
      final r = Uri.parse(LegalUrls.riskUrl);
      expect(p.host, t.host);
      expect(t.host, r.host);
      // Pin the exact host — moving the legal site to a different
      // domain (custom domain like lumin.app/legal/...) is a
      // deliberate change that requires updating this test along
      // with the constant.
      expect(p.host, 'mkmk749278.github.io');
    });

    test('URLs end with the expected path slug', () {
      // ``.endsWith`` rather than full equality so a future move
      // to a subdomain or custom domain doesn't churn the test —
      // what we really care about is the page slug being stable.
      expect(LegalUrls.privacyUrl.endsWith('/privacy'), isTrue);
      expect(LegalUrls.termsUrl.endsWith('/terms'), isTrue);
      expect(LegalUrls.riskUrl.endsWith('/risk'), isTrue);
    });

    test('URLs are distinct', () {
      // Defensive: a copy-paste bug between the three constants
      // would silently route all three Settings rows to the same
      // page.  Pin pair-wise distinctness.
      expect(LegalUrls.privacyUrl, isNot(LegalUrls.termsUrl));
      expect(LegalUrls.termsUrl, isNot(LegalUrls.riskUrl));
      expect(LegalUrls.privacyUrl, isNot(LegalUrls.riskUrl));
    });
  });
}

/// Tests for the Play Store region gate (A6, 2026-05-20).
///
/// Scope: the data layer (RegionInfo model + repo wiring).  The
/// RegionGate widget itself is straightforward (FutureBuilder around
/// a soft-fail check), so we cover its critical logic — which is
/// "what does the fetched RegionInfo say" — via tests on the data
/// shape rather than via widget tests (lumin-app does not currently
/// have an AppConfigScope-test-injection seam, and introducing one
/// is out of scope for this PR).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

void main() {
  group('RegionInfo.fromJson', () {
    test('parses the full server response shape', () {
      final r = RegionInfo.fromJson({
        'country_code': 'IN',
        'source': 'cf-header',
        'is_blocked': false,
        'blocked_regions': ['BD', 'CN', 'US'],
      });
      expect(r.countryCode, 'IN');
      expect(r.source, 'cf-header');
      expect(r.isBlocked, false);
      expect(r.blockedRegions, ['BD', 'CN', 'US']);
      expect(r.isUnknown, false);
    });

    test('isUnknown is true for the literal "unknown" sentinel', () {
      final r = RegionInfo.fromJson({
        'country_code': 'unknown',
        'source': 'unknown',
        'is_blocked': false,
        'blocked_regions': ['BD', 'CN', 'US'],
      });
      expect(r.isUnknown, true);
      // Crucial doctrine pin: "unknown" is NEVER blocked.  This is
      // the soft-fail-open default — better to show UI to someone we
      // can't identify than to block a user in a permitted region.
      expect(r.isBlocked, false);
    });

    test('is_blocked=true with US country', () {
      final r = RegionInfo.fromJson({
        'country_code': 'US',
        'source': 'cf-header',
        'is_blocked': true,
        'blocked_regions': ['BD', 'CN', 'US'],
      });
      expect(r.countryCode, 'US');
      expect(r.isBlocked, true);
      expect(r.isUnknown, false);
    });

    test('missing fields fall back to soft-defaults', () {
      // Tolerance for partial server response — if the engine ever
      // ships a slimmer response (or the wire shape evolves) the
      // client doesn't crash; it lands on the unblocked-unknown
      // default that mirrors the server's own soft-fail-open path.
      final r = RegionInfo.fromJson({});
      expect(r.countryCode, 'unknown');
      expect(r.source, 'unknown');
      expect(r.isBlocked, false);
      expect(r.blockedRegions, isEmpty);
      expect(r.isUnknown, true);
    });

    test('missing blocked_regions falls back to empty list', () {
      final r = RegionInfo.fromJson({
        'country_code': 'IN',
        'source': 'cf-header',
        'is_blocked': false,
      });
      expect(r.blockedRegions, isEmpty);
    });

    test('blocked_regions of arbitrary length round-trips', () {
      final r = RegionInfo.fromJson({
        'country_code': 'IN',
        'source': 'cf-header',
        'is_blocked': false,
        'blocked_regions': ['BD', 'CN', 'IR', 'KP', 'RU', 'US'],
      });
      expect(r.blockedRegions, ['BD', 'CN', 'IR', 'KP', 'RU', 'US']);
    });
  });

  group('MockRepository.fetchRegion', () {
    test('returns IN / not-blocked (matches dev/QA default)', () async {
      final repo = MockRepository();
      final r = await repo.fetchRegion();
      expect(r.countryCode, 'IN');
      expect(r.isBlocked, false);
      // Mock fixture should mirror the default server-side block list
      // so QA flows hit the same is_blocked check production code does.
      expect(r.blockedRegions, contains('US'));
      expect(r.blockedRegions, contains('CN'));
      expect(r.blockedRegions, contains('BD'));
    });
  });
}

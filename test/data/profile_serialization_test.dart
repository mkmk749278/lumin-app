/// Profile serialization — the model behind `GET /api/profile`, now the
/// entitlement-status source for the Subscription/Profile pages and the
/// cold-start hydration path (2026-07-17).  Repo convention: models
/// default rather than null-crash on pre-upgrade engines.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

void main() {
  test('parses a full payload', () {
    final p = Profile.fromJson({
      'user_id': 7,
      'phone_e164': '+918712582445',
      'tier': 'auto',
      'paid_until': '2026-08-17T00:00:00Z',
      'display_name': 'Kishore',
      'country_code': 'IN',
      'timezone': 'Asia/Kolkata',
      'currency': 'INR',
      'terms_accepted_at': '2026-07-01T00:00:00Z',
      'onboarded_at': '2026-07-01T00:00:00Z',
      'needs_onboarding': false,
    });
    expect(p.userId, 7);
    expect(p.tier, 'auto');
    expect(p.paidUntil, '2026-08-17T00:00:00Z');
    expect(p.displayName, 'Kishore');
    expect(p.needsOnboarding, isFalse);
  });

  test('tolerates an older backend that omits tier/paid_until', () {
    final p = Profile.fromJson({
      'user_id': 3,
      'phone_e164': '+10000000000',
    });
    expect(p.userId, 3);
    expect(p.tier, isNull);
    expect(p.paidUntil, isNull);
    expect(p.needsOnboarding, isTrue, reason: 'defaults conservative');
  });

  test('tolerates an empty payload entirely', () {
    final p = Profile.fromJson(const {});
    expect(p.userId, isNull);
    expect(p.tier, isNull);
    expect(p.paidUntil, isNull);
  });
}

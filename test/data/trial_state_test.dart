/// Trial payload → model mapping (2026-07-25).
///
/// The repo convention: fields default rather than null-crash on a
/// pre-upgrade engine. That matters more than usual here, because the trial
/// ships DARK — the app build reaches users while `/api/trial` may not exist
/// on their engine yet, and "no offer" is the only safe reading of silence.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumin/data/api_client.dart';
import 'package:lumin/data/auth_service.dart';
import 'package:lumin/data/repository.dart';

class _FakeAuth extends Fake implements AuthService {
  @override
  Future<String?> currentIdToken({bool forceRefresh = false}) async => 'tok';
}

HttpRepository _repo(
  Map<String, dynamic> routes, {
  List<http.Request>? seen,
}) {
  return HttpRepository(LuminApiClient(
    baseUrl: 'https://api.luminapp.org',
    auth: _FakeAuth(),
    httpClient: MockClient((req) async {
      seen?.add(req);
      final body = routes[req.url.path];
      if (body == null) return http.Response('{"detail": "not found"}', 404);
      return http.Response(jsonEncode(body), 200);
    }),
  ));
}

void main() {
  group('TrialState.fromJson', () {
    test('maps a live offer', () {
      final s = TrialState.fromJson(const {
        'offer_available': true,
        'days': 7,
        'tier': 'auto',
        'claimed': false,
        'active': false,
        'ineligible_reason': null,
      });

      expect(s.offerAvailable, isTrue);
      expect(s.days, 7);
      expect(s.tier, 'auto');
      expect(s.claimed, isFalse);
    });

    test('maps a running trial with its countdown', () {
      final s = TrialState.fromJson(const {
        'offer_available': false,
        'days': 7,
        'tier': 'auto',
        'claimed': true,
        'active': true,
        'claimed_at': '2026-07-25T10:00:00+00:00',
        'expires_at': '2026-08-01T10:00:00+00:00',
        'seconds_remaining': 432000,
        'days_remaining': 5,
      });

      expect(s.active, isTrue);
      expect(s.daysRemaining, 5);
      expect(s.expiresAt, '2026-08-01T10:00:00+00:00');
      expect(s.isEndingSoon, isFalse);
    });

    test('isEndingSoon only fires on a running trial in its last two days', () {
      TrialState at(int days, {bool active = true}) => TrialState(
            claimed: true, active: active, daysRemaining: days,
          );

      expect(at(3).isEndingSoon, isFalse);
      expect(at(2).isEndingSoon, isTrue);
      expect(at(1).isEndingSoon, isTrue);
      // A lapsed trial is not "ending soon" — it has ended.
      expect(at(1, active: false).isEndingSoon, isFalse);
      expect(const TrialState(claimed: true, active: true).isEndingSoon, isFalse);
    });

    test('an empty payload defaults to no offer, nothing claimed', () {
      final s = TrialState.fromJson(const <String, dynamic>{});

      expect(s.offerAvailable, isFalse);
      expect(s.claimed, isFalse);
      expect(s.active, isFalse);
      expect(s.days, 0);
      expect(s.tier, isNull);
      expect(s.daysRemaining, isNull);
    });
  });

  group('TrialClaimResult.fromJson', () {
    test('a successful claim carries the post-claim state inline', () {
      final r = TrialClaimResult.fromJson(const {
        'ok': true,
        'reason': null,
        'offer_available': false,
        'days': 7,
        'tier': 'auto',
        'claimed': true,
        'active': true,
        'days_remaining': 7,
        'expires_at': '2026-08-01T10:00:00+00:00',
      });

      expect(r.ok, isTrue);
      expect(r.state.active, isTrue);
      expect(r.state.daysRemaining, 7);
    });

    test('a refusal carries the reason AND the unchanged state', () {
      final r = TrialClaimResult.fromJson(const {
        'ok': false,
        'reason': 'already_trialled',
        'offer_available': false,
        'claimed': true,
        'active': false,
        'days': 7,
        'tier': 'auto',
        'ineligible_reason': 'already_trialled',
      });

      expect(r.ok, isFalse);
      expect(r.reason, 'already_trialled');
      expect(r.state.claimed, isTrue);
      expect(r.state.active, isFalse);
    });
  });

  group('HttpRepository', () {
    test('fetchTrialState reads GET /api/trial', () async {
      final seen = <http.Request>[];
      final repo = _repo({
        '/api/trial': {
          'offer_available': true, 'days': 7, 'tier': 'auto',
        },
      }, seen: seen);

      final state = await repo.fetchTrialState();

      expect(state.offerAvailable, isTrue);
      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/trial');
    });

    test('claimTrial POSTs and does not throw on a refusal', () async {
      final seen = <http.Request>[];
      final repo = _repo({
        '/api/trial/claim': {
          'ok': false,
          'reason': 'offer_not_available',
          'offer_available': false,
        },
      }, seen: seen);

      final result = await repo.claimTrial();

      expect(result.ok, isFalse);
      expect(result.reason, 'offer_not_available');
      expect(seen.single.method, 'POST');
    });
  });

  group('MockRepository', () {
    test('previewing the offer behaves like the real one-shot claim',
        () async {
      const repo = MockRepository();

      final first = await repo.claimTrial();
      expect(first.ok, isTrue);
      expect(first.state.active, isTrue);

      final second = await repo.claimTrial();
      expect(second.ok, isFalse);
      expect(second.reason, 'already_trialled');
      expect((await repo.fetchTrialState()).offerAvailable, isFalse);
    });
  });
}

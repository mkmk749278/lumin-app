/// HTTP-level tests for the live repository seam (2026-07-17).
///
/// `HttpRepository` is the single seam between every page and the engine.
/// Two repo conventions get pinned against real JSON payloads here:
///
/// * **Tolerant parsing** — fields default rather than null-crash when an
///   older engine omits them, and unknown extra fields are ignored;
/// * **Engine truth** — `is_open` is passed through verbatim (the mover
///   runner rides open at TP1_HIT; the status string cannot substitute),
///   entitlement comes from the verify response's tier, and the region
///   gate soft-fails OPEN on backend trouble.
///
/// Wire-level behaviour (auth header, retries, error decoding) lives in
/// api_client_test.dart; this file focuses on payload → model mapping.
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

/// Repository over a MockClient that answers each request from [routes]
/// (path → status/body) and records requests into [seen].
HttpRepository repo(
  Map<String, dynamic> routes, {
  List<http.Request>? seen,
  int status = 200,
}) {
  return HttpRepository(LuminApiClient(
    baseUrl: 'https://api.luminapp.org',
    auth: _FakeAuth(),
    httpClient: MockClient((req) async {
      seen?.add(req);
      final body = routes[req.url.path];
      if (body == null) return http.Response('{"detail": "not found"}', 404);
      return http.Response(jsonEncode(body), status);
    }),
  ));
}

void main() {
  group('fetchSignals', () {
    test('maps the engine payload onto MockSignal', () async {
      final r = repo({
        '/api/signals': {
          'items': [
            {
              'signal_id': 'sig-1',
              'symbol': 'BTCUSDT',
              'direction': 'SHORT',
              'setup_class': 'MOVER_AVWAP_SCALP',
              'agent_name': 'Mover',
              'entry': 100.0,
              'stop_loss': 101.0,
              'tp1': 99.0,
              'confidence': 82.5,
              'quality_tier': 'A+',
              'status': 'ACTIVE',
              'pnl_pct': 0.4,
              'is_open': true,
            }
          ]
        }
      });
      final signals = await r.fetchSignals();
      final s = signals.single;
      expect(s.id, 'sig-1');
      expect(s.direction, 'SHORT');
      expect(s.setupName, 'MOVER AVWAP SCALP'); // underscores → spaces
      expect(s.sl, 101.0);
      expect(s.tier, 'A+');
      expect(s.isOpen, isTrue);
    });

    test('a minimal payload from an older engine defaults every field',
        () async {
      final r = repo({
        '/api/signals': {
          'items': [<String, dynamic>{}]
        }
      });
      final s = (await r.fetchSignals()).single;
      expect(s.id, '');
      expect(s.direction, 'LONG');
      expect(s.tier, 'B');
      expect(s.status, 'ACTIVE');
      expect(s.entry, 0.0);
      // No is_open from the engine → null, and the effective getter falls
      // back to the status heuristic.
      expect(s.isOpen, isNull);
      expect(s.effectiveIsOpen, isTrue);
    });

    test('is_open is engine truth: TP1_HIT can be open OR closed', () async {
      final r = repo({
        '/api/signals': {
          'items': [
            {'signal_id': 'mover', 'status': 'TP1_HIT', 'is_open': true},
            {'signal_id': 'done', 'status': 'TP1_HIT', 'is_open': false},
          ]
        }
      });
      final signals = await r.fetchSignals();
      expect(signals[0].effectiveIsOpen, isTrue);
      expect(signals[1].effectiveIsOpen, isFalse);
    });

    test('sends status/limit/setup_class as query parameters', () async {
      final seen = <http.Request>[];
      final r = repo({
        '/api/signals': {'items': []}
      }, seen: seen);
      await r.fetchSignals(status: 'open', limit: 10, setupClass: 'BREAKOUT');
      expect(seen.single.url.queryParameters, {
        'status': 'open',
        'limit': '10',
        'setup_class': 'BREAKOUT',
      });
    });

    test('missing items key yields an empty list, not a crash', () async {
      final r = repo({'/api/signals': <String, dynamic>{}});
      expect(await r.fetchSignals(), isEmpty);
    });
  });

  group('fetchAlerts', () {
    test('parses items and tolerates their absence', () async {
      final withItems = repo({
        '/api/alerts': {
          'items': [
            {
              'id': 'al-1',
              'symbol': 'ETHUSDT',
              'kind': 'VOL_SPIKE',
              'title': 'Volume spike',
            }
          ]
        }
      });
      expect((await withItems.fetchAlerts()).single.symbol, 'ETHUSDT');

      final empty = repo({'/api/alerts': <String, dynamic>{}});
      expect(await empty.fetchAlerts(), isEmpty);
    });
  });

  group('verifyPlayPurchase', () {
    test('posts the token and parses the engine verdict', () async {
      final seen = <http.Request>[];
      final r = repo({
        '/api/billing/play/verify': {
          'ok': true,
          'tier': 'assist',
          'paid_until': '2026-08-17T00:00:00Z',
          'subscription_state': 'SUBSCRIPTION_STATE_ACTIVE',
        }
      }, seen: seen);
      final result = await r.verifyPlayPurchase(
        productId: 'lumin.assist.monthly',
        purchaseToken: 'token-1',
      );
      expect(seen.single.url.path, '/api/billing/play/verify');
      expect(jsonDecode(seen.single.body), {
        'product_id': 'lumin.assist.monthly',
        'purchase_token': 'token-1',
      });
      expect(result.isPaid, isTrue);
      expect(result.tier, 'assist');
      expect(result.paidUntil, '2026-08-17T00:00:00Z');
    });

    test('a minimal response defaults to NOT entitled', () async {
      // Fail-safe direction: a shape-drifted engine response must never
      // read as paid.
      final r = repo({'/api/billing/play/verify': <String, dynamic>{}});
      final result = await r.verifyPlayPurchase(
        productId: 'p',
        purchaseToken: 't',
      );
      expect(result.ok, isFalse);
      expect(result.tier, 'free');
      expect(result.isPaid, isFalse);
    });
  });

  group('fetchRegion', () {
    test('parses the engine block verdict', () async {
      final r = repo({
        '/api/region': {
          'country_code': 'US',
          'source': 'cf-header',
          'is_blocked': true,
          'blocked_regions': ['US', 'CN'],
        }
      });
      final region = await r.fetchRegion();
      expect(region.isBlocked, isTrue);
      expect(region.blockedRegions, ['US', 'CN']);
      expect(region.isUnknown, isFalse);
    });

    test('soft-fails OPEN when the endpoint errors', () async {
      // A transient backend outage must not brick auto-trade for
      // legitimate users — the gate collapses to unknown/unblocked.
      final r = repo({}); // /api/region → 404
      final region = await r.fetchRegion();
      expect(region.isBlocked, isFalse);
      expect(region.isUnknown, isTrue);
    });
  });

  group('deleteAccount', () {
    test('translates known backend tags into typed exceptions', () async {
      final r = HttpRepository(LuminApiClient(
        baseUrl: 'https://api.luminapp.org',
        auth: _FakeAuth(),
        httpClient: MockClient((_) async => http.Response(
            '{"detail": "key_blob_delete_failed"}', 503)),
      ));
      await expectLater(
        r.deleteAccount(),
        throwsA(isA<DeleteAccountException>()
            .having((e) => e.tag, 'tag', 'key_blob_delete_failed')
            .having((e) => e.message, 'message', contains('revoke'))),
      );
    });
  });
}

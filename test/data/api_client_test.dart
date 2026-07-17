/// Tests for the shared HTTP client every authorized engine call goes
/// through (2026-07-17).
///
/// This was the "HttpRepository test scaffolding" the delete-account tests
/// once declared out of scope.  Pinned here:
///
/// * the Authorization header carries the current Firebase ID token, and
///   its absence (signed-out) simply omits the header — the engine's 401
///   stays the authority;
/// * the 401 → force-refresh-once contract: exactly one retry, with
///   `forceRefresh: true`, then give up (no refresh loop);
/// * 5xx retries once with back-off, then surfaces ApiError;
/// * 4xx decodes the FastAPI `detail` body into ApiError.message;
/// * `postRaw` returns 4xx responses instead of throwing (the Binance
///   connect flow reads error headers off them);
/// * URL joining tolerates trailing-slash base URLs and drops null query
///   values;
/// * timeouts surface as ApiError(0), not an unhandled TimeoutException.
///
/// Uses MockClient + a Fake AuthService — no Firebase, no network.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumin/data/api_client.dart';
import 'package:lumin/data/auth_service.dart';

class _FakeAuth extends Fake implements AuthService {
  _FakeAuth({this.token = 'firebase-id-token'});

  String? token;
  String? refreshedToken;
  final List<bool> tokenRequests = [];

  @override
  Future<String?> currentIdToken({bool forceRefresh = false}) async {
    tokenRequests.add(forceRefresh);
    if (forceRefresh && refreshedToken != null) return refreshedToken;
    return token;
  }
}

void main() {
  LuminApiClient client({
    required MockClient http,
    _FakeAuth? auth,
    Duration timeout = const Duration(seconds: 5),
  }) =>
      LuminApiClient(
        baseUrl: 'https://api.luminapp.org',
        auth: auth ?? _FakeAuth(),
        timeout: timeout,
        httpClient: http,
      );

  group('auth header', () {
    test('carries the Firebase ID token as a Bearer', () async {
      late http.Request seen;
      final c = client(
        http: MockClient((req) async {
          seen = req;
          return http.Response('{}', 200);
        }),
      );
      await c.get('/api/pulse');
      expect(seen.headers['Authorization'], 'Bearer firebase-id-token');
      expect(seen.headers['Accept'], 'application/json');
    });

    test('signed-out (null token) omits the header entirely', () async {
      late http.Request seen;
      final c = client(
        auth: _FakeAuth(token: null),
        http: MockClient((req) async {
          seen = req;
          return http.Response('{}', 200);
        }),
      );
      await c.get('/api/pulse');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('401 force-refresh contract', () {
    test('retries exactly once with forceRefresh, then succeeds', () async {
      final auth = _FakeAuth()..refreshedToken = 'fresh-token';
      var calls = 0;
      final c = client(
        auth: auth,
        http: MockClient((req) async {
          calls++;
          return req.headers['Authorization'] == 'Bearer fresh-token'
              ? http.Response('{"ok": true}', 200)
              : http.Response('{"detail": "token expired"}', 401);
        }),
      );
      final result = await c.get('/api/pulse');
      expect(result, {'ok': true});
      expect(calls, 2);
      // First request used the cached token; the retry force-refreshed.
      expect(auth.tokenRequests, [false, true]);
    });

    test('a second 401 gives up with ApiError — no refresh loop', () async {
      var calls = 0;
      final c = client(
        http: MockClient((_) async {
          calls++;
          return http.Response('{"detail": "nope"}', 401);
        }),
      );
      await expectLater(
        c.get('/api/pulse'),
        throwsA(isA<ApiError>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'nope')),
      );
      expect(calls, 2);
    });
  });

  group('5xx retry', () {
    test('one transient 5xx recovers on the retry', () async {
      var calls = 0;
      final c = client(
        http: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('deploy restart', 503)
              : http.Response('{"ok": true}', 200);
        }),
      );
      expect(await c.get('/api/pulse'), {'ok': true});
      expect(calls, 2);
    });

    test('a hard outage surfaces the 5xx after maxRetries', () async {
      var calls = 0;
      final c = client(
        http: MockClient((_) async {
          calls++;
          return http.Response('down', 502);
        }),
      );
      await expectLater(
        c.get('/api/pulse'),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'code', 502)),
      );
      expect(calls, 2); // initial + maxRetries(1)
    });
  });

  group('error decoding', () {
    test('FastAPI detail body becomes the ApiError message', () async {
      final c = client(
        http: MockClient(
            (_) async => http.Response('{"detail": "tier required"}', 403)),
      );
      await expectLater(
        c.get('/api/auto-trade/settings'),
        throwsA(isA<ApiError>()
            .having((e) => e.message, 'message', 'tier required')),
      );
    });

    test('non-JSON error body is passed through raw', () async {
      final c = client(
        http: MockClient((_) async => http.Response('plain text oops', 400)),
      );
      await expectLater(
        c.get('/api/pulse'),
        throwsA(isA<ApiError>()
            .having((e) => e.message, 'message', 'plain text oops')),
      );
    });

    test('an empty 200 body returns null', () async {
      final c = client(http: MockClient((_) async => http.Response('', 200)));
      expect(await c.get('/api/pulse'), isNull);
    });
  });

  group('postRaw (Binance connect contract)', () {
    test('returns the 4xx response with headers instead of throwing',
        () async {
      final c = client(
        http: MockClient((_) async => http.Response(
              '{"detail": "ip not whitelisted"}',
              422,
              headers: {
                'x-connect-error-code': 'IP_NOT_WHITELISTED',
                'x-engine-vps-ip': '10.0.0.1',
              },
            )),
      );
      final resp = await c.postRaw('/api/binance/connect', body: {'k': 'v'});
      expect(resp.statusCode, 422);
      expect(resp.headers['x-connect-error-code'], 'IP_NOT_WHITELISTED');
      expect(resp.headers['x-engine-vps-ip'], '10.0.0.1');
    });
  });

  group('request shape', () {
    test('POST encodes the JSON body', () async {
      late http.Request seen;
      final c = client(
        http: MockClient((req) async {
          seen = req;
          return http.Response('{}', 200);
        }),
      );
      await c.post('/api/auto-trade/take', body: {'signal_id': 'sig-1'});
      expect(jsonDecode(seen.body), {'signal_id': 'sig-1'});
      expect(seen.headers['Content-Type'], startsWith('application/json'));
    });

    test('trailing-slash base URL still yields a single-slash path',
        () async {
      late Uri seen;
      final c = LuminApiClient(
        baseUrl: 'https://api.luminapp.org/',
        auth: _FakeAuth(),
        httpClient: MockClient((req) async {
          seen = req.url;
          return http.Response('{}', 200);
        }),
      );
      await c.get('api/pulse');
      expect(seen.toString(), 'https://api.luminapp.org/api/pulse');
    });

    test('null query values are dropped, non-null stringified', () async {
      late Uri seen;
      final c = client(
        http: MockClient((req) async {
          seen = req.url;
          return http.Response('{}', 200);
        }),
      );
      await c.get('/api/signals', query: {'limit': 50, 'setup_class': null});
      expect(seen.queryParameters, {'limit': '50'});
    });
  });

  group('timeout', () {
    test('a hung request surfaces ApiError(0), not TimeoutException',
        () async {
      final c = client(
        timeout: const Duration(milliseconds: 50),
        http: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        c.get('/api/pulse'),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'code', 0)),
      );
    });
  });
}

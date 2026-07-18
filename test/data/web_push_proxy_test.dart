/// Web-push topic proxy seam (web/PWA channel, 2026-07-18).
///
/// On web the browser cannot subscribe to FCM topics client-side, so
/// `HttpRepository.subscribeWebPushTopic` / `unsubscribeWebPushTopic`
/// POST the registration token to the engine's stateless proxy.  Pinned
/// here: exact endpoint paths, the `{token, topic}` body contract the
/// engine's pydantic model expects, the Bearer header, and that errors
/// propagate (the NotificationService caller is the fail-soft layer —
/// the repo seam must not swallow).
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

HttpRepository _repo({
  required List<http.Request> seen,
  int status = 200,
  Map<String, dynamic> body = const {'ok': true},
}) {
  return HttpRepository(LuminApiClient(
    baseUrl: 'https://api.luminapp.org',
    auth: _FakeAuth(),
    httpClient: MockClient((req) async {
      seen.add(req);
      return http.Response(jsonEncode(body), status);
    }),
  ));
}

void main() {
  test('subscribe POSTs {token, topic} to /api/push/subscribe with Bearer',
      () async {
    final seen = <http.Request>[];
    await _repo(seen: seen)
        .subscribeWebPushTopic(token: 'reg-token-123', topic: 'signals');
    expect(seen, hasLength(1));
    final req = seen.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/api/push/subscribe');
    expect(req.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(req.body), {'token': 'reg-token-123', 'topic': 'signals'});
  });

  test('unsubscribe POSTs the same contract to /api/push/unsubscribe',
      () async {
    final seen = <http.Request>[];
    await _repo(seen: seen)
        .unsubscribeWebPushTopic(token: 'reg-token-123', topic: 'alerts');
    final req = seen.single;
    expect(req.url.path, '/api/push/unsubscribe');
    expect(jsonDecode(req.body), {'token': 'reg-token-123', 'topic': 'alerts'});
  });

  test('an engine rejection propagates as ApiError (caller is fail-soft)',
      () async {
    final seen = <http.Request>[];
    final r = _repo(
      seen: seen,
      status: 429,
      body: const {'detail': 'too many push subscription requests'},
    );
    expect(
      () => r.subscribeWebPushTopic(token: 't' * 30, topic: 'signals'),
      throwsA(isA<ApiError>()),
    );
  });

  test('MockRepository is a silent no-op (offline dev parity)', () async {
    final mock = MockRepository();
    await mock.subscribeWebPushTopic(token: 'x' * 30, topic: 'signals');
    await mock.unsubscribeWebPushTopic(token: 'x' * 30, topic: 'alerts');
  });
}

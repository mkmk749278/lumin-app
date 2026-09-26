/// Request-shape contract for every money write the app sends (2026-09-26).
///
/// `http_repository_test.dart` pins how engine payloads are READ; nothing
/// pinned what the app WRITES. On these routes a wrong key is not an error —
/// it is silence:
///
/// * `PUT /api/settings/user/auto-trade` is read engine-side with
///   `model_dump(exclude_unset=True)`, so a key the engine model does not
///   declare is dropped without a word (the `exit_mechanism` defect,
///   engine CLAUDE.md 2026-08-10), and a key sent as `null` is a CLEAR — an
///   untouched picker that serialised as `null` would wipe the user's
///   symbol filter on every unrelated save.
/// * take / close / manual-trade bodies are pydantic models; a renamed field
///   is a 422 on a live order.
///
/// The field sets below are the engine's, read from 360-v2 `src/api/schemas.py`
/// (`AutoTradeSettings`), `src/api/manual_trade_route.py`
/// (`ManualTradeRequest`), `take_signal_route.py` and `close_position_route.py`
/// on 2026-09-26. The engine pins the same sets in
/// `tests/api/test_app_request_contract.py`, so a rename on either side fails
/// that side's CI — neither CI can see the other repo.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumin/data/api_client.dart';
import 'package:lumin/data/auth_service.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/data/server_side_execution_models.dart';

/// The engine's `AutoTradeSettings` fields. `exit_mechanism` is set from ops,
/// never from the app, which is why the app's keys are a SUBSET.
const engineAutoTradeSettingsFields = {
  'exit_mechanism',
  'leverage_cap',
  'max_concurrent_positions',
  'mode',
  'notional_usd',
  'paper_path_preference',
  'paper_regime_preference',
  'paper_symbol_preference',
  'path_preference',
  'position_size_pct',
  'regime_preference',
  'symbol_preference',
};

/// The engine's `ManualTradeRequest` fields — the app sends all of them.
const engineManualTradeFields = {
  'ref_id',
  'symbol',
  'direction',
  'entry_type',
  'entry_price',
  'sl_price',
  'tp_prices',
  'valid_for_minutes',
};

class _FakeAuth extends Fake implements AuthService {
  @override
  Future<String?> currentIdToken({bool forceRefresh = false}) async => 'tok';
}

class _Wire {
  final requests = <http.Request>[];

  /// `"METHOD /path"` → (status, body, headers).
  final routes = <String, (int, Object?, Map<String, String>)>{};

  void on(String key, Object? body,
          {int status = 200, Map<String, String> headers = const {}}) =>
      routes[key] = (status, body, headers);

  HttpRepository repo() => HttpRepository(LuminApiClient(
        baseUrl: 'https://api.luminapp.org',
        auth: _FakeAuth(),
        httpClient: MockClient((req) async {
          requests.add(req);
          final hit = routes['${req.method} ${req.url.path}'];
          if (hit == null) return http.Response('{"detail":"not found"}', 404);
          final (status, body, headers) = hit;
          return http.Response(body == null ? '' : jsonEncode(body), status,
              headers: {'content-type': 'application/json', ...headers});
        }),
      ));

  http.Request only(String method, String path) {
    final hits =
        requests.where((r) => r.method == method && r.url.path == path).toList();
    expect(hits, hasLength(1), reason: '$method $path sent ${hits.length}x');
    return hits.single;
  }

  Map<String, dynamic> bodyOf(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;
}

void main() {
  group('take / close a signal', () {
    test('take posts exactly {signal_id}, with the bearer token', () async {
      final w = _Wire()
        ..on('POST /api/auto-trade/take',
            {'outcome': 'placed', 'signal_id': 'sig-1', 'symbol': 'BTCUSDT'});
      final result = await w.repo().takeSignalServerSide('sig-1');

      final req = w.only('POST', '/api/auto-trade/take');
      expect(w.bodyOf(req), {'signal_id': 'sig-1'});
      expect(req.headers['authorization'], 'Bearer tok');
      expect(result.outcome, 'placed');
    });

    test('a take answer with no outcome reads as rejected, never placed',
        () async {
      final w = _Wire()..on('POST /api/auto-trade/take', {'signal_id': 'sig-1'});
      final result = await w.repo().takeSignalServerSide('sig-1');
      expect(result.outcome, 'rejected');
    });

    test('close posts exactly {signal_id}', () async {
      final w = _Wire()
        ..on('POST /api/auto-trade/close',
            {'outcome': 'closed', 'signal_id': 'sig-9'});
      final result = await w.repo().closeAutoTradePosition('sig-9');
      expect(w.bodyOf(w.only('POST', '/api/auto-trade/close')),
          {'signal_id': 'sig-9'});
      expect(result.isClosed, isTrue);
    });

    test('a close answer with no outcome is not reported as closed', () async {
      final w = _Wire()..on('POST /api/auto-trade/close', <String, dynamic>{});
      final result = await w.repo().closeAutoTradePosition('sig-9');
      expect(result.isClosed, isFalse);
      expect(result.isQueued, isFalse);
    });
  });

  group('manual trade', () {
    test('sends every field the engine model declares, and nothing else',
        () async {
      final w = _Wire()
        ..on('POST /api/manual-trade/take',
            {'outcome': 'placed', 'ref_id': 'alert-1'});
      await w.repo().placeManualTrade(const ManualTradeRequest(
            refId: 'alert-1',
            symbol: 'ETHUSDT',
            direction: 'SHORT',
            entryType: 'limit',
            entryPrice: 2500.5,
            slPrice: 2550.0,
            tpPrices: [2450.0, 2400.0],
            validForMinutes: 30,
          ));
      final body = w.bodyOf(w.only('POST', '/api/manual-trade/take'));
      expect(body.keys.toSet(), engineManualTradeFields);
      expect(body, {
        'ref_id': 'alert-1',
        'symbol': 'ETHUSDT',
        'direction': 'SHORT',
        'entry_type': 'limit',
        'entry_price': 2500.5,
        'sl_price': 2550.0,
        'tp_prices': [2450.0, 2400.0],
        'valid_for_minutes': 30,
      });
    });
  });

  group('Binance key connect / disconnect', () {
    test('connect posts api_key + api_secret and nothing else', () async {
      final w = _Wire()..on('POST /api/binance/connect', {'connected': true});
      await w.repo().connectBinanceServerSide(apiKey: 'K', apiSecret: 'S');
      expect(w.bodyOf(w.only('POST', '/api/binance/connect')),
          {'api_key': 'K', 'api_secret': 'S'});
    });

    test('a refused connect carries the engine code + VPS IP, never the secret',
        () async {
      const secret = 'sEcReT-do-not-echo-0123456789';
      final w = _Wire()
        ..on('POST /api/binance/connect', {'detail': 'IP not whitelisted'},
            status: 400,
            headers: {
              'x-connect-error-code': 'IP_NOT_WHITELISTED',
              'x-engine-vps-ip': '203.0.113.7',
            });
      final err = await w
          .repo()
          .connectBinanceServerSide(apiKey: 'K', apiSecret: secret)
          .then<BinanceConnectError?>((_) => null,
              onError: (Object e) => e as BinanceConnectError);

      expect(err, isNotNull);
      expect(err!.code, 'IP_NOT_WHITELISTED');
      expect(err.engineVpsIp, '203.0.113.7');
      expect(err.httpStatus, 400);
      expect(err.detail, 'IP not whitelisted');
      expect(err.toString(), isNot(contains(secret)));
      expect(err.detail, isNot(contains(secret)));
    });

    test('disconnect is a DELETE on the same route', () async {
      final w = _Wire()..on('DELETE /api/binance/connect', null);
      await w.repo().disconnectBinanceServerSide();
      w.only('DELETE', '/api/binance/connect');
    });
  });

  group('per-user auto-trade settings (exclude_unset on the engine)', () {
    test('a mode-only save sends ONLY mode — untouched pickers are absent, '
        'not null (null would clear them)', () async {
      final w = _Wire()
        ..on('PUT /api/settings/user/auto-trade', {'mode': 'paper'});
      await w
          .repo()
          .updateUserAutoTradeSettings(const AutoTradeSettings(mode: 'paper'));
      expect(w.bodyOf(w.only('PUT', '/api/settings/user/auto-trade')),
          {'mode': 'paper'});
    });

    test('clearing a picker sends an explicit null for that key only',
        () async {
      final w = _Wire()..on('PUT /api/settings/user/auto-trade', {});
      await w.repo().updateUserAutoTradeSettings(const AutoTradeSettings(
            symbolPreference: null,
            symbolPreferenceSet: true,
          ));
      final body = w.bodyOf(w.only('PUT', '/api/settings/user/auto-trade'));
      expect(body, {'symbol_preference': null});
      expect(body.containsKey('symbol_preference'), isTrue);
    });

    test('every key the app can send is one the engine model declares',
        () async {
      final w = _Wire()..on('PUT /api/settings/user/auto-trade', {});
      await w.repo().updateUserAutoTradeSettings(const AutoTradeSettings(
            mode: 'live',
            positionSizePct: 2.0,
            leverageCap: 5.0,
            maxConcurrentPositions: 3,
            symbolPreference: ['BTCUSDT'],
            symbolPreferenceSet: true,
            pathPreference: ['MOVER_TREND_PULLBACK'],
            pathPreferenceSet: true,
            regimePreference: ['TRENDING'],
            regimePreferenceSet: true,
            paperSymbolPreference: ['ETHUSDT'],
            paperSymbolPreferenceSet: true,
            paperPathPreference: <String>[],
            paperPathPreferenceSet: true,
            paperRegimePreference: ['RANGING'],
            paperRegimePreferenceSet: true,
            notionalUsd: 25.0,
          ));
      final keys =
          w.bodyOf(w.only('PUT', '/api/settings/user/auto-trade')).keys.toSet();
      expect(keys.difference(engineAutoTradeSettingsFields), isEmpty,
          reason: 'the engine drops an undeclared key silently');
      // Everything the app owns is actually sent when set.
      expect(keys, engineAutoTradeSettingsFields.difference({'exit_mechanism'}));
    });
  });

  group('owner auto-mode', () {
    test('posts {mode} and then re-reads the engine state', () async {
      final w = _Wire()
        ..on('POST /api/auto-mode', {'success': true, 'mode': 'paper'})
        ..on('GET /api/auto-mode', {'mode': 'paper'});
      final status = await w.repo().setAutoMode('paper');

      expect(w.bodyOf(w.only('POST', '/api/auto-mode')), {'mode': 'paper'});
      expect(w.requests.map((r) => '${r.method} ${r.url.path}').toList(),
          ['POST /api/auto-mode', 'GET /api/auto-mode'],
          reason: 'the screen must render what the engine says, not the click');
      expect(status.mode, 'paper');
    });
  });
}

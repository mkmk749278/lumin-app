/// Tests for ``lib/data/binance_client.dart`` — pinned behavior of the
/// HMAC-signed Futures REST client.
///
/// Why this is in the first wave: Lumin signs Binance Futures orders
/// directly from the user's device (lib/data/order_executor.dart).  A
/// signing bug means real money moves wrong on real accounts.  The
/// signing path has zero regression coverage today.
///
/// Strategy: inject ``MockClient`` from ``package:http/testing.dart`` so
/// no network call is made.  Each test asserts on the URI the client
/// sends to Binance (path, query keys, signature correctness) and on the
/// ``X-MBX-APIKEY`` auth header.  The signature is recomputed from the
/// unsigned query string + the secret used in the test and compared
/// byte-for-byte against what BinanceClient produced.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumin/data/binance_client.dart';

void main() {
  group('BinanceSymbolFilters', () {
    test('roundQty floors to stepSize multiple', () {
      const f = BinanceSymbolFilters(
        symbol: 'BTCUSDT',
        tickSize: 0.1,
        stepSize: 0.001,
        minQty: 0.001,
        minNotional: 5.0,
      );
      // 0.0123 / 0.001 = 12.3 → floor 12 → 0.012.
      expect(f.roundQty(0.0123), closeTo(0.012, 1e-9));
      // 0.0009 < minQty → 0.
      expect(f.roundQty(0.0009), 0.0);
    });

    test('roundPrice direction-aware (floor for SL on LONG, ceil for TP)', () {
      const f = BinanceSymbolFilters(
        symbol: 'BTCUSDT',
        tickSize: 0.1,
        stepSize: 0.001,
        minQty: 0.001,
        minNotional: 5.0,
      );
      // 100.27 → floor → 100.2; ceil → 100.3.
      expect(f.roundPrice(100.27, floor: true), closeTo(100.2, 1e-9));
      expect(f.roundPrice(100.27, floor: false), closeTo(100.3, 1e-9));
    });

    test('fromJson parses Binance exchangeInfo filter shape', () {
      final f = BinanceSymbolFilters.fromJson({
        'symbol': 'ETHUSDT',
        'filters': [
          {'filterType': 'PRICE_FILTER', 'tickSize': '0.01'},
          {'filterType': 'LOT_SIZE', 'stepSize': '0.001', 'minQty': '0.001'},
          {'filterType': 'MIN_NOTIONAL', 'notional': '5'},
        ],
      });
      expect(f.symbol, 'ETHUSDT');
      expect(f.tickSize, 0.01);
      expect(f.stepSize, 0.001);
      expect(f.minQty, 0.001);
      expect(f.minNotional, 5.0);
    });
  });

  group('BinanceClient HMAC-SHA256 signing', () {
    // Recompute the signature the same way the client does so the test
    // is independent of clock value — extract unsigned bytes from the
    // URI, recompute, compare to the signature param.
    String expectedSig(String secret, String unsignedQuery) {
      final hmac = Hmac(sha256, utf8.encode(secret));
      return hmac.convert(utf8.encode(unsignedQuery)).toString();
    }

    test('createMarketOrder POSTs to /fapi/v1/order with all required params + valid signature', () async {
      Uri? sentUri;
      Map<String, String>? sentHeaders;
      final mock = MockClient((req) async {
        sentUri = req.url;
        sentHeaders = req.headers;
        return http.Response(
          jsonEncode({'orderId': 42, 'avgPrice': '1.2345'}),
          200,
        );
      });
      final client = BinanceClient(
        apiKey: 'TEST_KEY',
        apiSecret: 'TEST_SECRET',
        testnet: true,
        httpClient: mock,
      );

      final resp = await client.createMarketOrder(
        symbol: 'BTCUSDT',
        side: 'BUY',
        quantity: 0.01,
        clientOrderId: 'lumin-entry-sig-123',
      );

      expect(resp['orderId'], 42);
      expect(sentUri, isNotNull);
      expect(sentUri!.host, 'testnet.binancefuture.com');
      expect(sentUri!.path, '/fapi/v1/order');
      expect(sentHeaders!['X-MBX-APIKEY'], 'TEST_KEY');

      // Round-trip the query: recover unsigned query (strip &signature=...)
      // and recompute the HMAC.  Must match the param Binance receives.
      final raw = sentUri!.query;
      final sigIdx = raw.lastIndexOf('&signature=');
      expect(sigIdx, greaterThan(0), reason: 'signature param missing from URI');
      final unsigned = raw.substring(0, sigIdx);
      final sig = raw.substring(sigIdx + '&signature='.length);
      expect(sig, expectedSig('TEST_SECRET', unsigned));

      // The unsigned query must include the order's required params.
      expect(unsigned, contains('symbol=BTCUSDT'));
      expect(unsigned, contains('side=BUY'));
      expect(unsigned, contains('type=MARKET'));
      expect(unsigned, contains('quantity=0.01'));
      expect(unsigned, contains('newClientOrderId=lumin-entry-sig-123'));
      expect(unsigned, contains('recvWindow=5000'));
      expect(unsigned, contains(RegExp(r'timestamp=\d{10,}')));
    });

    test('createStopOrder with closePosition uses closePosition=true and omits quantity', () async {
      Uri? sentUri;
      final mock = MockClient((req) async {
        sentUri = req.url;
        return http.Response(jsonEncode({'orderId': 99}), 200);
      });
      final client = BinanceClient(
        apiKey: 'K',
        apiSecret: 'S',
        testnet: false,
        httpClient: mock,
      );

      await client.createStopOrder(
        symbol: 'BTCUSDT',
        side: 'SELL',
        stopType: 'STOP_MARKET',
        stopPrice: 100.0,
        closePosition: true,
        clientOrderId: 'lumin-sl-123',
      );

      final query = sentUri!.query;
      expect(query, contains('closePosition=true'));
      expect(query, isNot(contains('reduceOnly=')));
      expect(query, isNot(contains('quantity=')));
      expect(query, contains('type=STOP_MARKET'));
      expect(query, contains('stopPrice=100.0'));
      // Mainnet base URL when testnet=false.
      expect(sentUri!.host, 'fapi.binance.com');
    });

    test('createStopOrder for TP1 uses reduceOnly + explicit quantity (not closePosition)', () async {
      Uri? sentUri;
      final mock = MockClient((req) async {
        sentUri = req.url;
        return http.Response(jsonEncode({'orderId': 101}), 200);
      });
      final client = BinanceClient(
        apiKey: 'K',
        apiSecret: 'S',
        testnet: true,
        httpClient: mock,
      );

      await client.createStopOrder(
        symbol: 'BTCUSDT',
        side: 'SELL',
        stopType: 'TAKE_PROFIT_MARKET',
        stopPrice: 110.0,
        quantity: 0.5,
        clientOrderId: 'lumin-tp1-123',
      );

      final query = sentUri!.query;
      expect(query, contains('reduceOnly=true'));
      expect(query, isNot(contains('closePosition=')));
      expect(query, contains('quantity=0.5'));
      expect(query, contains('type=TAKE_PROFIT_MARKET'));
    });

    test('non-200 response raises BinanceError with code + message from JSON body', () async {
      final mock = MockClient((req) async {
        return http.Response(
          jsonEncode({'code': -1021, 'msg': 'Timestamp for this request is outside of the recvWindow.'}),
          400,
        );
      });
      final client = BinanceClient(
        apiKey: 'K',
        apiSecret: 'S',
        testnet: true,
        httpClient: mock,
      );

      await expectLater(
        client.getOpenPositions(),
        throwsA(
          isA<BinanceError>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', -1021)
              .having((e) => e.message, 'message', contains('recvWindow')),
        ),
      );
    });

    test('cancelOrder requires either orderId or origClientOrderId', () async {
      final mock = MockClient((_) async => http.Response('', 200));
      final client = BinanceClient(
        apiKey: 'K',
        apiSecret: 'S',
        testnet: true,
        httpClient: mock,
      );
      expect(
        () => client.cancelOrder(symbol: 'BTCUSDT'),
        throwsArgumentError,
      );
    });

    test('HMAC-SHA256 matches the Binance API docs test vector', () {
      // Vendor-cited: from the Binance Futures REST docs, "SIGNED
      // (TRADE and USER_DATA) Endpoint Examples".  If a future swap of
      // the crypto package or a regression in the signing path produces
      // a different digest, this fails loudly with the same comparison
      // Binance's own backend performs server-side.
      const secret = 'NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j';
      const unsigned =
          'symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559';
      const expected =
          'c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71';
      final hmac = Hmac(sha256, utf8.encode(secret));
      expect(hmac.convert(utf8.encode(unsigned)).toString(), expected);
    });
  });
}

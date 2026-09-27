/// CoinDCX models against what the engine REALLY returns (2026-09-27).
///
/// `fixtures/coindcx_app_contract.json` is a byte-identical copy of 360-v2
/// `tests/venues/fixtures/coindcx/app_contract.json`, which the engine's own
/// test regenerates from its live routes and pins.  So a renamed key fails
/// the engine's CI there, and a parser drifting from that shape fails here —
/// never a hand-written payload agreeing with the parser that reads it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/coindcx_models.dart';

Map<String, dynamic> _vector() => jsonDecode(
        File('test/data/fixtures/coindcx_app_contract.json').readAsStringSync())
    as Map<String, dynamic>;

Map<String, dynamic> _at(String key) => _vector()[key] as Map<String, dynamic>;

void main() {
  test('info carries the IP to bind, the engine\'s checklist and the ₹ rate', () {
    final info = CoinDCXInfo.fromJson(_at('info'));
    expect(info.engineIp, isNotNull);
    expect(info.attestationItems, hasLength(3));
    expect(info.marginCurrencies, ['INR', 'USDT']);
    expect(info.marginDefault, 'INR');
    expect(info.leverageMin, lessThan(info.leverageMax));
    expect(info.inrPerUsdt, greaterThan(0));
    expect(info.exitProfile, contains('TP1'));
  });

  test('status: not connected is a readable "no"', () {
    final s = CoinDCXConnectStatus.fromJson(_at('status_not_connected'));
    expect(s.readable, isTrue);
    expect(s.connected, isFalse);
    expect(s.attested, isFalse);
  });

  test('status: an unreadable key store is NOT "not connected"', () {
    final s = CoinDCXConnectStatus.fromJson(_at('status_unreadable'));
    expect(s.readable, isFalse);
    expect(s.connected, isNull, reason: 'unknown is not a no');
    expect(s.attested, isNull);
  });

  test('venue: a chosen, attested, open CoinDCX reads as live', () {
    final v = VenueSettings.fromJson(_at('venue_coindcx'));
    expect(v.readable, isTrue);
    expect(v.isCoinDCX, isTrue);
    expect(v.marginCurrency, 'INR');
    expect(v.leverage, 3);
    expect(v.coindcxKeyReadable, isTrue);
    expect(v.coindcxLive, isTrue);
  });

  test('venue: any one missing condition means not live', () {
    final base = _at('venue_coindcx');
    for (final flip in ['execution_enabled', 'allow_listed', 'attested', 'connected']) {
      final j = jsonDecode(jsonEncode(base)) as Map<String, dynamic>;
      (j['coindcx'] as Map)[flip] = false;
      expect(VenueSettings.fromJson(j).coindcxLive, isFalse, reason: flip);
    }
  });

  test('venue: an unreadable key never reads as connected', () {
    final j = jsonDecode(jsonEncode(_at('venue_coindcx'))) as Map<String, dynamic>;
    (j['coindcx'] as Map)['readable'] = false;
    final v = VenueSettings.fromJson(j);
    expect(v.coindcxConnected, isNull);
    expect(v.coindcxLive, isFalse);
  });

  test('positions: gross from the engine, net after fees, ₹ at CoinDCX\'s rate', () {
    final ps = CoinDCXPositions.fromJson(_at('positions'));
    expect(ps.readable, isTrue);
    final p = ps.positions.single;
    expect(p.symbol, 'DOGEUSDT');
    expect(p.marginCurrency, 'INR');
    expect(p.isLive, isFalse);
    expect(p.closeReason, 'TP1');
    expect(p.realizedPnlUsdt, 0.49);
    expect(p.realizedPnlInr, 49.98, reason: 'engine gross ₹ at its own rate');
    expect(p.netPnlUsdt, closeTo(0.47, 1e-9));
    expect(p.netPnlInr, closeTo(0.47 * 102, 1e-9));
  });

  test('a missing fee is not a zero fee', () {
    final j = jsonDecode(jsonEncode(_at('positions'))) as Map<String, dynamic>;
    ((j['positions'] as List).first as Map)['fees_usdt'] = null;
    final p = CoinDCXPositions.fromJson(j).positions.single;
    expect(p.netPnlUsdt, isNull);
    expect(p.netPnlInr, isNull);
  });

  test('a USDT-margin trade has no ₹ figure', () {
    final j = jsonDecode(jsonEncode(_at('positions'))) as Map<String, dynamic>;
    final row = (j['positions'] as List).first as Map;
    row['margin_currency'] = 'USDT';
    row['conversion_price'] = 0.0;
    expect(CoinDCXPositions.fromJson(j).positions.single.netPnlInr, isNull);
  });
}

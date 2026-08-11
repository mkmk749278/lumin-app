/// `TrackRecord` — the recorded delivered-signal book the Pulse tab renders.
///
/// The engine owns the math (`src/track_record.py`, pinned there against a
/// vector shared with the ops dashboard). What is pinned here is the **seam**:
/// the field names the app reads off the wire, and the states it must be able
/// to tell apart. Both are places this system has been bitten before —
/// a field one repo reads and no repo writes empties a page while looking full,
/// and a payload the app cannot classify turns "the owner switched this off"
/// into "the signals made nothing".
///
/// The payload used below is a **real response shape**, keyed exactly as
/// `TrackRecordResponse` serialises it. A hand-invented shape asserts your
/// assumption back at you one repo short of the producer — which is precisely
/// how a feature shipped uncomputable for its whole life once.
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

/// Keys and nesting exactly as `GET /api/track-record` serialises them.
Map<String, dynamic> _payload({
  bool enabled = true,
  String reason = '',
  List<Map<String, dynamic>>? items,
  Map<String, dynamic>? summary,
}) =>
    {
      'enabled': enabled,
      'unavailable_reason': reason,
      'days': 30,
      'amount_usdt': 100.0,
      'fee_pct': 0.07,
      'range_start': '2026-07-12',
      'generated_at': '2026-08-11T12:00:00+00:00',
      'total_records': 1143,
      'undateable': 0,
      'summary': summary ??
          {
            'n': 407,
            'moves': 394,
            'n_pnl': 407,
            'no_pnl': 0,
            'wins': 141,
            'losses': 266,
            'win_rate': 0.3464373464373464,
            'gross_usd': 80.34,
            'fee_usd': 28.49,
            'net_usd': 51.85,
            'total_pnl_pct': 80.34,
            'avg_pnl_pct': 0.197,
            'total_net_pct': 51.85,
            'avg_net_pct': 0.127,
            'best_pnl_pct': 12.71,
            'worst_pnl_pct': -9.60,
          },
      'items': items ??
          [
            {
              'date': '2026-08-09', 'n': 30, 'moves': 29, 'n_pnl': 30,
              'no_pnl': 0, 'wins': 13, 'losses': 17, 'win_rate': 0.433,
              'gross_usd': 16.69, 'fee_usd': 2.1, 'net_usd': 14.59,
              'total_pnl_pct': 16.69, 'avg_pnl_pct': 0.556,
              'total_net_pct': 14.59, 'avg_net_pct': 0.486,
              'best_pnl_pct': 9.48, 'worst_pnl_pct': -9.60,
              'partial_reason': null,
              'cum_net_usd': 42.55, 'cum_net_pct': 42.55,
            },
            {
              'date': '2026-08-11', 'n': 3, 'moves': 3, 'n_pnl': 3,
              'no_pnl': 0, 'wins': 0, 'losses': 3, 'win_rate': 0.0,
              'gross_usd': -3.0, 'fee_usd': 0.21, 'net_usd': -3.21,
              'total_pnl_pct': -3.0, 'avg_pnl_pct': -1.0,
              'total_net_pct': -3.21, 'avg_net_pct': -1.07,
              'best_pnl_pct': 0.0, 'worst_pnl_pct': -3.0,
              'partial_reason': 'in_progress',
              'cum_net_usd': 51.85, 'cum_net_pct': 51.85,
            },
          ],
    };

HttpRepository _repo(Object body, {List<http.Request>? seen, int status = 200}) =>
    HttpRepository(LuminApiClient(
      baseUrl: 'https://api.luminapp.org',
      auth: _FakeAuth(),
      httpClient: MockClient((req) async {
        seen?.add(req);
        return http.Response(jsonEncode(body), status);
      }),
    ));

void main() {
  group('TrackRecord.fromJson — the cross-repo field contract', () {
    test('reads every figure the card renders off the real key names', () {
      final r = TrackRecord.fromJson(_payload());

      expect(r.enabled, isTrue);
      expect(r.days, 30);
      // The assumed size and fee must survive onto the model: the card states
      // them beside the money, and a dollar figure whose size the reader
      // cannot see is an assumption wearing a measurement's clothes.
      expect(r.amountUsdt, 100.0);
      expect(r.feePct, 0.07);
      expect(r.rangeStart, '2026-07-12');

      expect(r.summary.trades, 407);
      expect(r.summary.moves, 394);
      expect(r.summary.netUsd, 51.85);
      expect(r.summary.grossUsd, 80.34);
      expect(r.summary.feeUsd, 28.49);
      expect(r.summary.wins, 141);
      expect(r.summary.losses, 266);
      expect(r.summary.winRate, closeTo(0.3464, 1e-4));
      expect(r.summary.avgNetPct, 0.127);
      expect(r.summary.bestPnlPct, 12.71);
      expect(r.summary.worstPnlPct, -9.60);
    });

    test('items keep engine order — oldest first, which is chart order', () {
      final r = TrackRecord.fromJson(_payload());
      expect(r.items.map((i) => i.date), ['2026-08-09', '2026-08-11']);
    });

    test('today is flagged in_progress and no other day is', () {
      // The card must not derive "today" from the device clock: every figure
      // here is UTC and the device can be in any timezone. The engine stamps
      // which day is still running; this is the field that carries it.
      final r = TrackRecord.fromJson(_payload());
      expect(r.items.first.inProgress, isFalse);
      expect(r.items.last.inProgress, isTrue);
      expect(r.items.last.partialReason, 'in_progress');
    });

    test('the running total is carried per day', () {
      final r = TrackRecord.fromJson(_payload());
      expect(r.items.first.cumNetUsd, 42.55);
      expect(r.items.last.cumNetUsd, 51.85);
      // ...and the newest day's running total IS the window's net.
      expect(r.items.last.cumNetUsd, r.summary.netUsd);
    });

    test('an older engine that omits keys defaults rather than crashing', () {
      final r = TrackRecord.fromJson({'enabled': true});
      expect(r.items, isEmpty);
      expect(r.summary.trades, 0);
      expect(r.amountUsdt, 100.0);
      expect(r.hasBook, isFalse);
    });

    test('a null money figure stays null and never becomes 0.0', () {
      // An unpriced day is "we cannot say", not a flat day. Coercing it to
      // zero would draw a bar the book never traded.
      final r = TrackRecord.fromJson(_payload(items: [
        {'date': '2026-08-09', 'n': 2, 'moves': 2, 'wins': 0, 'losses': 0,
         'net_usd': null, 'total_net_pct': null, 'cum_net_usd': 3.0,
         'partial_reason': null},
      ]));
      expect(r.items.single.netUsd, isNull);
      expect(r.items.single.netPct, isNull);
    });
  });

  group('hasBook — the card shows itself only when it can say something', () {
    test('a full book shows', () {
      expect(TrackRecord.fromJson(_payload()).hasBook, isTrue);
    });

    test('switched off by the owner does not', () {
      final r = TrackRecord.fromJson(
        _payload(enabled: false, reason: 'disabled', items: []),
      );
      expect(r.hasBook, isFalse);
      // ...and the two states stay distinguishable for a diagnostic, even
      // though the subscriber sees the same nothing either way.
      expect(r.unavailableReason, 'disabled');
    });

    test('a record the engine has never written does not', () {
      final r = TrackRecord.fromJson(_payload(reason: 'missing', items: []));
      expect(r.hasBook, isFalse);
      expect(r.unavailableReason, 'missing');
    });

    test('rows that exist but could not be priced do not', () {
      // A window whose every outcome was unreadable would otherwise render a
      // headline of dashes over an empty chart, which reads as "the signals
      // made nothing" when it means "we could not price them".
      final r = TrackRecord.fromJson(_payload(
        summary: {'n': 12, 'moves': 12, 'n_pnl': 0, 'no_pnl': 12},
        items: [
          {'date': '2026-08-09', 'n': 12, 'net_usd': null, 'cum_net_usd': 0.0},
        ],
      ));
      expect(r.summary.trades, 12);
      expect(r.summary.tradesPriced, 0);
      expect(r.hasBook, isFalse);
    });

    test('TrackRecord.empty is a hidden card, not an empty book', () {
      // assemblePulseBundle falls back to this on any error. It must not read
      // as "the signals made nothing" — a performance claim we could not
      // verify is worse than no card.
      expect(TrackRecord.empty.enabled, isFalse);
      expect(TrackRecord.empty.hasBook, isFalse);
    });
  });

  group('HttpRepository.fetchTrackRecord', () {
    test('hits the right path and passes the window through', () async {
      final seen = <http.Request>[];
      final r = await _repo(_payload(), seen: seen).fetchTrackRecord(days: 90);
      expect(seen.single.url.path, '/api/track-record');
      expect(seen.single.url.queryParameters['days'], '90');
      expect(r.summary.netUsd, 51.85);
    });

    test('sends no identity — the book is pooled, not per-user', () async {
      // If this ever grows a user filter, the card stops being the thing a
      // brand-new subscriber can read, which is the only reason it exists.
      // `/api/pnl/history` is where the per-user question already lives.
      final seen = <http.Request>[];
      await _repo(_payload(), seen: seen).fetchTrackRecord();
      expect(seen.single.url.queryParameters.keys, ['days']);
    });
  });

  group('MockRepository.fetchTrackRecord — preview mode', () {
    test('produces a renderable book with today still running', () async {
      final r = await MockRepository().fetchTrackRecord(days: 30);
      expect(r.hasBook, isTrue);
      expect(r.items.last.inProgress, isTrue);
      expect(r.items.where((i) => i.inProgress).length, 1);
    });

    test('omits days on which nothing closed rather than emitting zeros',
        () async {
      // The live engine does this, so the preview must too — otherwise the
      // offline build exercises a shape the real one never produces, and the
      // date-positioned chart goes untested against its own reason for
      // existing.
      final r = await MockRepository().fetchTrackRecord(days: 30);
      expect(r.items.length, lessThan(30));
      expect(r.items.every((i) => (i.netUsd ?? 0) != 0), isTrue);
    });

    test('the running total ends where the summary says it does', () async {
      final r = await MockRepository().fetchTrackRecord(days: 30);
      expect(r.items.last.cumNetUsd, closeTo(r.summary.netUsd!, 1e-9));
    });
  });
}

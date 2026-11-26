import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/desk_models.dart';

/// Shaped like engine `src/desk.py` DESK_SCHEMA 1 (360-v2 #1106). If the
/// engine renames a key, `tests/test_desk.py` there pins `_SETUP_KEYS`; this
/// pins the reading side.
Map<String, dynamic> desk({
  String freshness = 'current',
  bool marketReadable = true,
  Map<String, dynamic>? plan,
}) =>
    {
      'state': 'ok',
      'desk': {
        'schema': 1,
        'generated_at': 1700000900.0,
        'ledger': 'ok',
        'brief': {
          'plan': plan ??
              {
                'plan_id': 'p',
                'submitted_at': 1700000000.0,
                'bias': 'risk_off',
                'notes': 'BTC printed a fresh 4h low.',
                'n_setups': 2,
                'n_accepted': 1,
                'accepted': [
                  {'symbol': 'XLMUSDT', 'side': 'short', 'archetype': 'breakout_retest'},
                ],
              },
          'freshness': {'state': freshness, 'age_sec': 900.0},
          'market': marketReadable
              ? {
                  'readable': true,
                  'btc_price': 59212.0,
                  'btc_state': -0.4,
                  'btc_change_pct': {'24h': -2.1, '7d': -6.0},
                  'breadth': {'readable': true, 'share_beating_btc_7d': 0.46, 'n': 78},
                }
              : {'readable': false, 'reason': 'no_btc_1h'},
        },
        'plans': [],
        'setups': [
          {
            'setup_id': 'p:0', 'symbol': 'XLMUSDT', 'side': 'short',
            'archetype': 'breakout_retest', 'state': 'not_filled',
            'submitted_at': 1700000000.0, 'expires_at': 1700014400.0,
            'entries': [
              {'price': 0.1242, 'weight': 0.4},
              {'price': 0.1246, 'weight': 0.6},
            ],
            'stop': 0.1256, 'targets': [0.1214, 0.1196], 'rr_tp1': 2.1,
            'p_target': 0.36,
            'analyst': {'status': 'resolved', 'unfilled': 1, 'net_pct': -0.4},
          },
        ],
        'record': {
          'readable': true,
          'basis': 'forward_walk',
          'basis_note': 'No order was placed: these are not fills.',
          'analyst': {'n': 11, 'win_rate': 0.18, 'avg_net_pct': -0.1},
          'split': {
            'fill_rate': 0.48,
            'filled_by_exit': {
              'target': {'n': 2, 'share': 0.18},
              'stop': {'n': 5, 'share': 0.45},
            },
          },
          'calibration': {'n': 11, 'mean_p_target': 0.41, 'hit_rate': 0.18},
        },
        'labels': {
          'archetype': {'breakout_retest': 'Breakout Retest'},
          'bias': {'risk_off': 'Risk-off'},
          'state': {'not_filled': 'Never filled'},
        },
      },
    };

void main() {
  test('reads the brief, setups and record', () {
    final r = DeskResponse.fromJson(desk());
    expect(r.isOk, isTrue);
    final d = r.desk!;
    expect(d.brief.freshness, BriefFreshness.current);
    expect(d.brief.plan!.bias, 'risk_off');
    expect(d.brief.plan!.accepted.single.symbol, 'XLMUSDT');
    expect(d.brief.market.btcPrice, 59212.0);
    expect(d.brief.market.shareBeatingBtc7d, 0.46);
    final s = d.setups.single;
    expect(s.entries.map((e) => e.weight), [0.4, 0.6]);
    expect(s.targets, [0.1214, 0.1196]);
    expect(s.isOpen, isFalse);
    expect(d.record.filledByExit['stop']!.n, 5);
    expect(d.record.statedPTarget, 0.41);
    expect(d.record.basisNote, contains('not fills'));
  });

  test('an unfilled limit carries the flag, never reads as a fill', () {
    final a = DeskResponse.fromJson(desk()).desk!.setups.single.analyst!;
    expect(a.unfilled, isTrue);
  });

  test('an unreadable market stays unreadable, never zeros', () {
    final m = DeskResponse.fromJson(desk(marketReadable: false)).desk!.brief.market;
    expect(m.readable, isFalse);
    expect(m.btcPrice, isNull);
    expect(m.reason, 'no_btc_1h');
  });

  test('stale and missing freshness are their own states', () {
    expect(DeskResponse.fromJson(desk(freshness: 'stale')).desk!.brief.freshness,
        BriefFreshness.stale);
    expect(DeskResponse.fromJson(desk(freshness: 'weird')).desk!.brief.freshness,
        BriefFreshness.none);
  });

  test('not reported and disabled carry no desk', () {
    expect(DeskResponse.fromJson({'state': 'not_reported', 'desk': null}).isOk, isFalse);
    expect(DeskResponse.fromJson({'state': 'disabled', 'desk': null}).desk, isNull);
    expect(DeskResponse.fromJson({}).state, 'not_reported');
  });

  test("the engine's own payload parses completely", () {
    final j = jsonDecode(
            File('test/data/fixtures/desk_engine_schema1.json').readAsStringSync())
        as Map<String, dynamic>;
    final d = DeskResponse.fromJson(j).desk!;
    expect(d.ledger, 'ok');
    expect(d.brief.plan!.bias, 'risk_off');
    expect(d.brief.freshness, BriefFreshness.current);
    final s = d.setups.single;
    expect(s.state, 'tp_hit');
    expect(s.entries.length, 2);
    expect(s.targets, [103.0, 105.0]);
    expect(s.analyst!.netPct, isNotNull);
    expect(d.record.readable, isTrue);
    expect(d.record.n, 1);
    expect(d.labels.archetypeOf('breakout_retest'), 'Breakout Retest');
    expect(d.labels.stateOf('tp_hit'), 'Target hit');
  });

  test('an unlabelled key renders as itself', () {
    final l = DeskResponse.fromJson(desk()).desk!.labels;
    expect(l.archetypeOf('breakout_retest'), 'Breakout Retest');
    expect(l.archetypeOf('new_thing'), 'new_thing');
    expect(l.biasOf(null), '—');
  });
}

/// Generated by the ENGINE's real `desk.build` over a ledger with one walked
/// setup (360-v2 tests/test_desk.py fixtures). Regenerate when DESK_SCHEMA
/// changes. A hand-written shape agrees with the reader that wrote it; this
/// one is what the engine actually emits.

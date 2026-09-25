/// `/api/signals` live-access parsing (owner, 2026-09-25).  The engine is
/// the source of truth; an engine that predates the paywall must read as
/// "no banner", never as "locked".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/live_feed_access.dart';

void main() {
  test('an engine that predates the paywall parses to null (no banner)', () {
    expect(LiveFeedAccess.fromSignalsJson({'items': [], 'total': 0}), isNull);
  });

  test('a guest reads locked with the hidden count', () {
    final a = LiveFeedAccess.fromSignalsJson({
      'items': [],
      'total': 0,
      'live_locked': true,
      'locked_open_count': 4,
      'live_access': {'allowed': false, 'reason': 'guest', 'until': null},
    })!;
    expect(a.locked, isTrue);
    expect(a.isGuest, isTrue);
    expect(a.lockedOpenCount, 4);
  });

  test('free window counts whole days left, rounded up', () {
    final now = DateTime.utc(2026, 10, 1, 12);
    final a = LiveFeedAccess.fromSignalsJson({
      'live_locked': false,
      'locked_open_count': 0,
      'live_access': {
        'allowed': true,
        'reason': 'free_window',
        'until': '2026-10-03T06:00:00+00:00',
      },
    })!;
    expect(a.isFreeWindow, isTrue);
    expect(a.daysLeft(now), 2); // 42h → 2 days
    expect(a.daysLeft(DateTime.utc(2026, 10, 3, 7)), 0);
  });

  test('a plan is neither locked nor a countdown', () {
    final a = LiveFeedAccess.fromSignalsJson({
      'live_locked': false,
      'live_access': {'allowed': true, 'reason': 'plan', 'until': null},
    })!;
    expect(a.locked, isFalse);
    expect(a.isFreeWindow, isFalse);
    expect(a.daysLeft(DateTime.now().toUtc()), 0);
  });

  test('masked live cards parse; malformed rows are dropped, not crashed on', () {
    final a = LiveFeedAccess.fromSignalsJson({
      'live_locked': true,
      'locked_open_count': 2,
      'locked_items': [
        {
          'signal_id': 's1',
          'symbol': 'BTCUSDT',
          'agent_name': 'Trend Rider',
          'quality_tier': 'A+',
          'confidence': 82,
          'minutes_ago': 4,
        },
        {'symbol': 'no id'},
      ],
      'live_access': {'allowed': false, 'reason': 'guest'},
    })!;
    expect(a.lockedItems, hasLength(1));
    expect(a.lockedItems.single.symbol, 'BTCUSDT');
    expect(a.lockedItems.single.minutesAgo, 4);
  });

  test('an engine without masked cards parses to an empty list', () {
    final a = LiveFeedAccess.fromSignalsJson({
      'live_access': {'allowed': false, 'reason': 'guest'},
    })!;
    expect(a.lockedItems, isEmpty);
  });
}

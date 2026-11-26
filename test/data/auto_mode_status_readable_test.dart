import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

/// Engine #1102: a status the server could not build arrives as a synthetic
/// `mode: off` with zeros and `readable: false`. The app must not render
/// that placeholder as a real "off".
void main() {
  Map<String, dynamic> body([Object? readable = 'absent']) => {
        'mode': 'off',
        'open_positions': 0,
        'daily_pnl_usd': 0,
        'daily_loss_pct': 0,
        'daily_kill_tripped': false,
        'manual_paused': false,
        'current_equity_usd': 0,
        if (readable != 'absent') 'readable': readable,
      };

  test('readable: false is unreadable, not off', () {
    final s = AutoModeStatus.fromJson(body(false));
    expect(s.readable, isFalse);
    expect(s.isUnreadable, isTrue);
  });

  test('readable: true is an ordinary reading', () {
    expect(AutoModeStatus.fromJson(body(true)).isUnreadable, isFalse);
  });

  test('an engine predating the field keeps the old rendering', () {
    final s = AutoModeStatus.fromJson(body());
    expect(s.readable, isNull);
    expect(s.isUnreadable, isFalse);
  });
}

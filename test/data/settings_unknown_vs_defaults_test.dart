/// "The engine has no overrides for you" and "we could not reach the engine"
/// are different facts, and the Trade tab used to render the second for both.
///
/// Found on 2026-09-19 by driving the app rather than by reading it: signed
/// in on a fresh free account, `GET /api/settings/user/auto-trade` returned
/// **200**, and the Trade tab showed *"Status unknown — could not reach
/// engine. Toggles below may not reflect actual state."* — on a screen where
/// every other card had just loaded from that same engine.
///
/// The cause is that `using_defaults` has two producers: the ENGINE sets it
/// on a healthy 200 to mean "this user saved no overrides" (which is what the
/// settings pages correctly render as "Using engine defaults."), and the APP
/// used the same field for its own fetch-failed fallback. One flag, two
/// meanings, and the alarming one won — sending a reader to check a
/// connection that works.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart';

void main() {
  group('the two states are distinguishable', () {
    test('a healthy 200 with no overrides does NOT read as unreachable', () {
      // Exactly what the engine sends a new account.
      final s = AutoTradeSettings.fromJson(const {
        'mode': 'off',
        'using_defaults': true,
      });
      expect(s.usingDefaults, isTrue, reason: 'the engine said so');
      expect(
        s.fetchFailed,
        isFalse,
        reason: 'nothing failed — the engine answered',
      );
    });

    test('settings parsed from the engine never claim a fetch failure', () {
      // fetchFailed is the app's own flag; no engine payload can set it,
      // which is what keeps the two meanings from merging again.
      final s = AutoTradeSettings.fromJson(const {
        'mode': 'live',
        'using_defaults': false,
        'fetch_failed': true, // engine cannot set this, even if it tried
      });
      expect(s.fetchFailed, isFalse);
    });

    test('the app fallback sets fetchFailed, and says so', () {
      const fallback =
          AutoTradeSettings(usingDefaults: true, fetchFailed: true);
      expect(fallback.fetchFailed, isTrue);
    });

    test('fetchFailed defaults to false, so silence is not a failure', () {
      expect(const AutoTradeSettings().fetchFailed, isFalse);
    });
  });

  group('the Trade tab grades on the right one', () {
    String tradePage() =>
        File('lib/features/trade/trade_page.dart').readAsStringSync();

    test('the unreachable banner is driven by fetchFailed', () {
      expect(tradePage(), contains('data.userSettings.fetchFailed'));
    });

    test('it is no longer driven by usingDefaults', () {
      // The regression: `data.userSettings.usingDefaults ?? false`.
      expect(
        RegExp(r'settingsUnknown\s*=\s*data\.userSettings\.usingDefaults')
            .hasMatch(tradePage()),
        isFalse,
        reason: 'the banner is reading the engine\'s "no overrides" flag '
            'again and will show on every new account',
      );
    });

    test('the banner still exists — this is a narrowing, not a deletion', () {
      // A genuinely unreachable engine must still say so: the toggles below
      // it would otherwise read as a confident "Off" over a state nobody
      // knows.
      expect(tradePage(), contains('could not reach engine'));
      expect(tradePage(), contains('_SettingsUnknownBanner'));
    });
  });

  test('the settings pages keep reading usingDefaults, which is theirs', () {
    // They render "Using engine defaults." vs "Custom — your overrides." —
    // the engine's own meaning, and correct. This fix must not have moved
    // them onto the app's flag.
    for (final page in const [
      'auto_trade_settings_page',
      'pretp_settings_page',
      'invalidation_settings_page',
    ]) {
      final src =
          File('lib/features/settings/pages/$page.dart').readAsStringSync();
      expect(src, contains('usingDefaults'),
          reason: '$page stopped reading the engine\'s flag');
    }
  });
}

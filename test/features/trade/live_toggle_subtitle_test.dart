/// Truthfulness of the Live auto-trade toggle's subtitle (2026-08-05).
///
/// Found by driving the live PWA as a signed-in user: with no Binance key
/// connected, the Trade tab rendered a blue ON toggle whose subtitle read
/// "Lumin places real Binance Futures orders on your account." directly above
/// an amber "Connect your Binance account — Details (2 to fix)" card. Nothing
/// could dispatch, so the sentence was false in precisely the state a new user
/// meets first.
///
/// The toggle reflects user INTENT; the subtitle describes SYSTEM BEHAVIOUR.
/// These tests pin that the strong claim is made only when the engine says
/// dispatch is live — the repo's "render engine state, never assume it" rule.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/trade/live_status_resolver.dart';

void main() {
  const strongClaim =
      'Lumin places real Binance Futures orders on your account.';

  group('liveToggleSubtitle', () {
    test('mode on + engine dispatching → states that orders are placed', () {
      expect(
        liveToggleSubtitle(liveActive: true, dispatching: true),
        strongClaim,
      );
    });

    test('mode on + engine NOT dispatching → never claims orders are placed',
        () {
      final s = liveToggleSubtitle(liveActive: true, dispatching: false);
      // The regression: this is the state with no key connected. Pre-fix the
      // subtitle was the strong claim here.
      expect(s, isNot(strongClaim));
      expect(s, contains('not placing orders yet'));
    });

    test('mode off → off copy regardless of engine state', () {
      for (final dispatching in [true, false]) {
        final s = liveToggleSubtitle(liveActive: false, dispatching: dispatching);
        expect(s, isNot(strongClaim));
        expect(s, startsWith('Off'));
      }
    });

    test('the strong claim is reachable from exactly one input combination',
        () {
      final claiming = <String>[];
      for (final live in [true, false]) {
        for (final dispatching in [true, false]) {
          if (liveToggleSubtitle(liveActive: live, dispatching: dispatching) ==
              strongClaim) {
            claiming.add('live=$live,dispatching=$dispatching');
          }
        }
      }
      expect(claiming, ['live=true,dispatching=true']);
    });
  });
}

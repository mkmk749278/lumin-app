/// Every failure the take flow can show names a way out, or honestly names
/// none (handoff §16).
///
/// The explanation copy was already good — the missing half was the action.
/// What is worth pinning is the pairing: a message that tells the reader to
/// open a page must carry the route to it, and a message with nowhere useful
/// to go must carry no route at all. A button that points somewhere
/// unhelpful is worse than none, because it teaches the reader the control
/// is decorative.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/features/settings/pages/auto_trade_settings_page.dart';
import 'package:lumin/features/settings/pages/server_side_execution_page.dart';
import 'package:lumin/features/signals/take_recovery_action.dart';
import 'package:lumin/data/take_error_mapper.dart';
import 'package:lumin/data/server_side_execution_models.dart';

TakeSignalResult _rejected(String rejectClass) => TakeSignalResult(
      outcome: 'rejected',
      rejectClass: rejectClass,
      symbol: 'BTCUSDT',
    );

void main() {
  group('HTTP failures route to the page that fixes them', () {
    test('409 (no key connected) offers the exchange connection', () {
      final m = translateTakeHttpError(409, 'no key');
      expect(m.recovery, TakeRecovery.exchangeConnection);
    });

    test('403 (plan-gated) offers the paywall, not a fault page', () {
      final m = translateTakeHttpError(403, 'tier');
      expect(m.recovery, TakeRecovery.subscription);
    });

    test('401 routes to sign-in', () {
      expect(translateTakeHttpError(401, 'expired').recovery,
          TakeRecovery.signIn);
    });

    test('a transient outage offers nothing, because nothing would help', () {
      // 503 and a dead connection are waits, not tasks. Offering a settings
      // page here would send the user to change something that is not wrong.
      expect(translateTakeHttpError(503, '').recovery, TakeRecovery.none);
      expect(translateTakeHttpError(0, '').recovery, TakeRecovery.none);
    });

    test('an unrecognised status offers nothing', () {
      expect(translateTakeHttpError(500, 'boom').recovery, TakeRecovery.none);
    });

    test('an unexpected client exception offers nothing', () {
      expect(translateTakeUnexpected().recovery, TakeRecovery.none);
    });
  });

  group('rejections route only where their own copy points', () {
    test('a key or whitelist failure offers the connection page', () {
      // The IP-whitelist mismatch: reads to a user like the account is
      // broken, and is usually two minutes of work.
      expect(
        translateTakeRejection(_rejected('OrderPlacementKeyError')).recovery,
        TakeRecovery.exchangeConnection,
      );
    });

    test('not connected / auto-trade off offer the connection page', () {
      for (final c in const [
        'UserNotConnectedError',
        'AutoTradeDisabledError',
      ]) {
        expect(
          translateTakeRejection(_rejected(c)).recovery,
          TakeRecovery.exchangeConnection,
          reason: '$c tells the user to open the Connect page',
        );
      }
    });

    test('a too-small position opens the sizing control', () {
      expect(
        translateTakeRejection(_rejected('NotionalTooSmall')).recovery,
        TakeRecovery.autoTradeSettings,
      );
    });

    test('rejections with nowhere to go offer nothing', () {
      // Each of these is either the system working as intended or a market
      // fact. None has a page that would change the outcome.
      for (final c in const [
        'SignalClosed',
        'RateLimitExceededError',
        'GlobalKillSwitchEngaged',
        'PositionCapExceededError',
        'SymbolNotInUserPreference',
        'OrderRejectedByBinance',
        'TakeRequestStale',
      ]) {
        expect(
          translateTakeRejection(_rejected(c)).recovery,
          TakeRecovery.none,
          reason: '$c has no page that would help, so it must offer no button',
        );
      }
    });

    test('an unknown reject class offers nothing rather than guessing', () {
      // The engine can add a class this build has never heard of. Falling
      // back to a route would send the user somewhere arbitrary.
      expect(
        translateTakeRejection(_rejected('SomeFutureClass')).recovery,
        TakeRecovery.none,
      );
    });
  });

  test('every routed message still carries its explanation', () {
    // The button is an addition, not a replacement: a bare "Fix connection"
    // with no sentence above it says what to press and not what happened.
    for (final status in const [401, 403, 409]) {
      final m = translateTakeHttpError(status, '');
      expect(m.headline, isNotEmpty);
      expect(m.action, isNotEmpty);
    }
  });

  // The button itself, pumped. The review sheet that hosts it cannot be —
  // it needs Binance keys, per-user settings, an AppConfigScope and an
  // Assist entitlement — so a control defined inside it could route
  // correctly and still render wrong with nothing to say so.
  group('TakeRecoveryAction renders', () {
    Future<void> pump(WidgetTester tester, TakeRecovery r) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TakeRecoveryAction(recovery: r, colour: Colors.orange),
            ),
          ),
        );

    testWidgets('names the destination for a key failure', (tester) async {
      await pump(tester, TakeRecovery.exchangeConnection);
      expect(find.textContaining('Fix connection'), findsOneWidget);
    });

    testWidgets('names the destination for a sizing failure', (tester) async {
      await pump(tester, TakeRecovery.autoTradeSettings);
      expect(find.textContaining('Open auto-trade settings'), findsOneWidget);
    });

    testWidgets('offers the paywall as plans, not as a fix', (tester) async {
      // A plan gate is not a fault, and "Fix" would frame it as one.
      await pump(tester, TakeRecovery.subscription);
      expect(find.textContaining('See plans'), findsOneWidget);
      expect(find.textContaining('Fix'), findsNothing);
    });

    testWidgets('renders NOTHING when there is nowhere to go', (tester) async {
      await pump(tester, TakeRecovery.none);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('renders nothing for sign-in, which it cannot route to',
        (tester) async {
      // The auth gate owns that route; pushing a sign-in over a signed-in
      // shell leaves the user somewhere Back cannot return from.
      await pump(tester, TakeRecovery.signIn);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('closes the host sheet BEFORE it navigates', (tester) async {
      // Without this the user lands on a settings page stacked over a stale
      // order review they can no longer confirm, and Back returns them to it.
      //
      // The destination is deliberately not pumped: every page this routes to
      // needs an AppConfigScope, and mounting one here would test those pages
      // rather than this button. The route itself is type-checked below.
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TakeRecoveryAction(
              recovery: TakeRecovery.exchangeConnection,
              colour: Colors.orange,
              onNavigate: () => closed = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextButton), warnIfMissed: false);
      expect(
        closed,
        isTrue,
        reason: 'the host was not told to close before the push',
      );
    });

    test('each route builds the page its label promises', () {
      // Constructed, not mounted — enough to catch a route pointing at the
      // wrong page, which is the failure a label alone cannot show.
      expect(
        TakeRecoveryAction.destinationFor(TakeRecovery.exchangeConnection)!
            .$2(),
        isA<ServerSideExecutionPage>(),
      );
      expect(
        TakeRecoveryAction.destinationFor(TakeRecovery.autoTradeSettings)!.$2(),
        isA<AutoTradeSettingsPage>(),
      );
    });

    test('every routable recovery has a label; the others have none', () {
      // Derived from the enum rather than listed, so a sixth recovery has to
      // decide whether it routes instead of silently rendering nothing.
      for (final r in TakeRecovery.values) {
        final d = TakeRecoveryAction.destinationFor(r);
        if (r == TakeRecovery.none || r == TakeRecovery.signIn) {
          expect(d, isNull, reason: '\$r must offer no button');
        } else {
          expect(d, isNotNull, reason: '\$r routes nowhere');
          expect(d!.$1, isNotEmpty, reason: '\$r has an empty label');
        }
      }
    });
  });
}

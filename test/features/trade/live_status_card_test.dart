/// LiveStatusCard — the surface that tells a subscriber whether their money
/// is being traded right now.
///
/// `resolveLiveStatus` (the verdict) is well covered by
/// `live_status_resolver_test.dart`.  The card that *renders* that verdict was
/// not covered at all, and that split is the bug class this repo has already
/// paid for: "a card showing 'armed' while dispatch silently skips". A correct
/// resolver behind a card that softens, caches or re-derives its answer is
/// exactly as harmful as a wrong resolver.
///
/// So these tests assert the rendering contract, not the resolution logic:
///
///  * the card says "active" when and only when the resolver says active —
///    driven through the real `resolveLiveStatus`, never a hand-set flag;
///  * every blocked state names its own next step rather than a generic
///    "not active", because a user who cannot see *why* cannot fix it;
///  * the Details expander shows every failing gate, not just the summarised
///    one — the "friendlier language, zero hidden problems" contract.
///
/// The card only reaches `AppConfigScope` inside the Resume / re-enable tap
/// handlers, so rendering is exercised without an app scope. Those two
/// actions perform network writes and are deliberately out of scope here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart' show AutoTradeSettings;
import 'package:lumin/data/server_side_execution_models.dart';
import 'package:lumin/features/trade/live_status_card.dart';
import 'package:lumin/features/trade/live_status_resolver.dart';

AutoTradeRuntimeStatus _runtime({
  bool globallyEnabled = true,
  bool userDisabled = false,
  bool keyConnected = true,
  String? mode = 'live',
  bool armed = true,
  bool? tierAllowsAuto = true,
  bool? autoPaused = false,
  bool preferencesBlockAll = false,
  List<String> effectiveSymbols = const ['BTCUSDT', 'ETHUSDT', 'SOLUSDT'],
}) =>
    AutoTradeRuntimeStatus(
      autoTradeGloballyEnabled: globallyEnabled,
      autoTradeUserDisabled: userDisabled,
      binanceKeyConnected: keyConnected,
      userMode: mode,
      allowedSymbols: const ['BTCUSDT', 'ETHUSDT', 'SOLUSDT'],
      effectiveAllowedSymbols: effectiveSymbols,
      armed: armed,
      tierAllowsAuto: tierAllowsAuto,
      autoPaused: autoPaused,
      preferencesBlockAll: preferencesBlockAll,
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<LiveStatus> _pump(
  WidgetTester tester, {
  required AutoTradeRuntimeStatus runtime,
  AutoTradeSettings settings = const AutoTradeSettings(),
  AutoTradeUserStatus? userStatus,
}) async {
  await tester.pumpWidget(_wrap(LiveStatusCard(
    runtime: runtime,
    userStatus: userStatus,
    userSettings: settings,
    onResumed: () async {},
  )));
  await tester.pump();
  // The verdict the card is obliged to render, from the real resolver.
  return resolveLiveStatus(
    runtime: runtime,
    userStatus: userStatus,
    userSettings: settings,
  );
}

void main() {
  group('active state', () {
    testWidgets('renders active and the watched-symbol count', (tester) async {
      final status = await _pump(tester, runtime: _runtime());

      expect(status.active, isTrue, reason: 'fixture must be a green case');
      expect(find.text('Auto-trade active'), findsOneWidget);
      expect(
        find.textContaining('Watching ${status.watchedSymbols} symbols'),
        findsOneWidget,
        reason: 'the count must come from the resolver, not be recomputed',
      );
    });

    testWidgets('watched count tracks the effective allowlist', (tester) async {
      await _pump(
        tester,
        runtime: _runtime(effectiveSymbols: const ['BTCUSDT']),
      );
      expect(find.textContaining('Watching 1 symbols'), findsOneWidget);
    });
  });

  group('the card never claims active when the resolver says otherwise', () {
    // Each case is a distinct real blocker. The assertion pair is the point:
    // the green copy must be absent, and the specific next step present.
    final cases = <String, ({AutoTradeRuntimeStatus runtime, String expect})>{
      'globally off': (
        runtime: _runtime(armed: false, globallyEnabled: false),
        expect: 'Trading briefly paused for everyone',
      ),
      'no binance key': (
        runtime: _runtime(armed: false, keyConnected: false),
        expect: 'Connect your Binance account',
      ),
      'mode off': (
        runtime: _runtime(armed: false, mode: 'off'),
        expect: 'Live trading is switched off',
      ),
      'tier blocked': (
        runtime: _runtime(armed: false, tierAllowsAuto: false),
        expect: 'Auto plan needed for hands-off trading',
      ),
      'filters exclude everything': (
        runtime: _runtime(armed: false, preferencesBlockAll: true),
        expect: 'Your filters exclude every signal',
      ),
      'account disabled by a safety check': (
        runtime: _runtime(armed: false, userDisabled: true),
        expect: 'Trading paused on your account',
      ),
    };

    cases.forEach((name, c) {
      testWidgets(name, (tester) async {
        final status = await _pump(tester, runtime: c.runtime);

        expect(status.active, isFalse, reason: 'fixture must be a blocked case');
        expect(
          find.text('Auto-trade active'),
          findsNothing,
          reason: 'showing active while blocked is the bug this card exists to '
              'prevent',
        );
        expect(find.text(c.expect), findsOneWidget);
      });
    });
  });

  group('paused', () {
    testWidgets('a paused account reads as paused, not as active',
        (tester) async {
      final status = await _pump(
        tester,
        runtime: _runtime(armed: true),
        settings: const AutoTradeSettings(pausedReason: 'some_reason',
            pausedAt: '2026-07-28T00:00:00Z'),
      );

      // armed is true, but isAutoPaused makes active false — the exact
      // conjunction the resolver's invariant pins.
      expect(status.active, isFalse);
      expect(find.text('Auto-trade active'), findsNothing);
    });

    testWidgets('an empty futures wallet names the actual cause',
        (tester) async {
      await _pump(
        tester,
        runtime: _runtime(armed: false, autoPaused: true),
        settings: const AutoTradeSettings(
          pausedReason: 'insufficient_margin',
          pausedAt: '2026-07-28T00:00:00Z',
        ),
      );

      expect(find.text('Paused — Futures wallet is empty'), findsOneWidget);
      expect(
        find.textContaining('USDT'),
        findsWidgets,
        reason: 'the user needs the concrete fix, not a generic pause notice',
      );
    });

    testWidgets('a pause with no known reason still renders a next step',
        (tester) async {
      await _pump(
        tester,
        runtime: _runtime(armed: false, autoPaused: true),
        settings: const AutoTradeSettings(
          pausedReason: 'something_unmapped',
          pausedAt: '2026-07-28T00:00:00Z',
        ),
      );
      expect(find.text('Paused on your account'), findsOneWidget);
    });
  });

  group('Details expander — zero hidden problems', () {
    testWidgets('every failing gate is listed, not just the summary reason',
        (tester) async {
      // Two independent blockers at once: the summary names the highest
      // priority, but the expander must disclose both.
      final runtime = _runtime(
        armed: false,
        keyConnected: false,
        mode: 'off',
      );
      final status = await _pump(tester, runtime: runtime);

      final failing = status.gates.where((g) => !g.ok).toList();
      expect(failing.length, greaterThanOrEqualTo(2),
          reason: 'fixture must have multiple failing gates');

      await tester.tap(find.textContaining('Details'));
      await tester.pumpAndSettle();

      for (final gate in failing) {
        expect(
          find.text(gate.label),
          findsOneWidget,
          reason: 'failing gate "${gate.label}" must not be hidden behind the '
              'single-reason summary',
        );
      }
    });

    testWidgets('passing gates are shown too, so the list is the whole truth',
        (tester) async {
      final status = await _pump(
        tester,
        runtime: _runtime(armed: false, mode: 'off'),
      );

      await tester.tap(find.textContaining('Details'));
      await tester.pumpAndSettle();

      for (final gate in status.gates) {
        expect(find.text(gate.label), findsOneWidget);
      }
    });

    testWidgets('details are collapsed until asked for', (tester) async {
      final status = await _pump(
        tester,
        runtime: _runtime(armed: false, mode: 'off'),
      );
      final aGateLabel = status.gates.first.label;
      expect(find.text(aGateLabel), findsNothing);
    });
  });

  group('old-engine payloads', () {
    testWidgets('unknown tierAllowsAuto never renders as a tier block',
        (tester) async {
      // null = older engine without the 2026-07-17 truth fields. Rendering a
      // tier block here would tell a paying user to upgrade a plan they hold.
      await _pump(
        tester,
        runtime: _runtime(armed: false, tierAllowsAuto: null, mode: 'off'),
      );
      expect(find.text('Auto plan needed for hands-off trading'), findsNothing);
      expect(find.text('Live trading is switched off'), findsOneWidget);
    });

    testWidgets('a null autoPaused does not read as paused', (tester) async {
      await _pump(
        tester,
        runtime: _runtime(armed: false, autoPaused: null, keyConnected: false),
      );
      expect(find.text('Connect your Binance account'), findsOneWidget);
    });
  });
}

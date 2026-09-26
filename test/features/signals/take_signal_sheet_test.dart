/// The take sheet — the one button in the app that places a real order —
/// pumped for the first time (2026-09-26).
///
/// Its own source said it could not be: reaching it needs an identity and a
/// repository, and `AppConfigScope` offered only mock mode (no identity) or a
/// live `HttpRepository`. `AppConfigScope.debugDependencies` is the seam; the
/// server-side path is what every web user and every server-connected key
/// takes, so it is the path pinned here:
///
/// * one confirmation places ONE order, however fast the button is tapped;
/// * once any verdict is on screen the order cannot be re-sent from the same
///   sheet;
/// * the sheet reports success only for a placed order — a rejection or a
///   queued take pops `false`;
/// * an engine rejection is shown in the app's words, never the raw engine
///   detail (which can carry a Firebase UID and internal framing).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/api_client.dart';
import 'package:lumin/data/app_config.dart';
import 'package:lumin/data/auth_service.dart';
import 'package:lumin/data/mock_data.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/data/server_side_execution_models.dart';
import 'package:lumin/features/signals/take_signal_sheet.dart';

class _SignedIn extends Fake implements AuthService {
  @override
  int? currentUserId() => 7;
}

class _Repo extends MockRepository {
  _Repo();

  int takes = 0;
  final List<String> takenIds = [];
  Completer<TakeSignalResult> answer = Completer<TakeSignalResult>();

  @override
  Future<AutoTradeRuntimeStatus> getAutoTradeRuntimeStatus() async =>
      const AutoTradeRuntimeStatus(
        autoTradeGloballyEnabled: true,
        autoTradeUserDisabled: false,
        binanceKeyConnected: true,
        userMode: 'live',
        allowedSymbols: [],
        effectiveAllowedSymbols: [],
        armed: true,
      );

  @override
  Future<AutoTradeSettings> fetchUserAutoTradeSettings() async =>
      const AutoTradeSettings(mode: 'live', notionalUsd: 25.0);

  @override
  Future<TakeSignalResult> takeSignalServerSide(String signalId) {
    takes++;
    takenIds.add(signalId);
    return answer.future;
  }
}

const _signal = MockSignal(
  id: 'sig-42',
  symbol: 'BTCUSDT',
  direction: 'LONG',
  setupName: 'MOVER TREND PULLBACK',
  agentName: 'Mover',
  entry: 60000.0,
  sl: 59000.0,
  tp1: 61000.0,
  tp2: 62000.0,
  tp3: 63000.0,
  confidence: 80.0,
  tier: 'A',
  status: 'ACTIVE',
  pnlPct: 0.0,
  minutesAgo: 1,
);

/// Pumps a page with a button that opens the sheet; returns a getter for
/// what the sheet popped with.
Future<bool? Function()> _open(
  WidgetTester tester, {
  required LuminRepository repo,
  AuthService? auth,
}) async {
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  bool? popped;
  var done = false;
  await tester.pumpWidget(AppConfigScope(
    initial: AppConfig(dataSource: DataSource.mock, apiBaseUrl: ''),
    debugDependencies: (repo: repo, auth: auth),
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped = await showTakeSignalSheet(context, signal: _signal);
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () {
    expect(done, isTrue, reason: 'the sheet has not been closed');
    return popped;
  };
}

Finder get _confirm => find.widgetWithText(FilledButton, 'Confirm live order');

bool _confirmEnabled(WidgetTester tester) {
  final buttons = tester.widgetList<FilledButton>(find.byType(FilledButton));
  return buttons.single.onPressed != null;
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one confirmation places ONE order, however fast it is tapped',
      (tester) async {
    final repo = _Repo();
    final result = await _open(tester, repo: repo, auth: _SignedIn());
    expect(find.textContaining('Real money'), findsOneWidget,
        reason: 'the server-side path must say it is a live order');

    await tester.tap(_confirm);
    await tester.pump();
    // Second and third taps land while the first is in flight.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(_confirmEnabled(tester), isFalse);

    repo.answer.complete(const TakeSignalResult(
        outcome: 'placed', signalId: 'sig-42', totalQty: 0.0004));
    await tester.pumpAndSettle();

    expect(repo.takes, 1);
    expect(repo.takenIds, ['sig-42']);
    expect(find.textContaining('Order placed on Binance'), findsOneWidget);
    expect(_confirmEnabled(tester), isFalse,
        reason: 'a placed order must not be re-sendable from the same sheet');

    await _close(tester);
    expect(result(), isTrue);
  });

  testWidgets('a rejection is shown in the app\'s words, never the raw detail, '
      'and the sheet does not report success', (tester) async {
    final repo = _Repo();
    final result = await _open(tester, repo: repo, auth: _SignedIn());
    await tester.tap(_confirm);
    repo.answer.complete(const TakeSignalResult(
      outcome: 'rejected',
      signalId: 'sig-42',
      symbol: 'BTCUSDT',
      rejectClass: 'NotionalTooSmall',
      rejectDetail: 'uid=fb-Xy9SECRETuid notional 4.2 < MIN_NOTIONAL 5.0',
    ));
    await tester.pumpAndSettle();

    expect(repo.takes, 1);
    expect(find.textContaining('fb-Xy9SECRETuid'), findsNothing);
    expect(find.textContaining('Order placed'), findsNothing);
    expect(_confirmEnabled(tester), isFalse);

    await _close(tester);
    expect(result(), isFalse);
  });

  testWidgets('a queued take is not a success', (tester) async {
    final repo = _Repo();
    final result = await _open(tester, repo: repo, auth: _SignedIn());
    await tester.tap(_confirm);
    repo.answer.complete(const TakeSignalResult(
        outcome: 'queued', signalId: 'sig-42', detail: 'Engine is busy — queued.'));
    await tester.pumpAndSettle();

    expect(find.text('Engine is busy — queued.'), findsOneWidget);
    expect(find.textContaining('Order placed'), findsNothing);
    await _close(tester);
    expect(result(), isFalse);
  });

  testWidgets('an HTTP failure is translated and cannot be re-fired from the '
      'sheet', (tester) async {
    final repo = _Repo();
    final result = await _open(tester, repo: repo, auth: _SignedIn());
    await tester.tap(_confirm);
    repo.answer.completeError(ApiError(409, 'no key blob for uid fb-RAW'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connect your Binance key first'), findsOneWidget);
    expect(find.textContaining('fb-RAW'), findsNothing);
    expect(repo.takes, 1);
    expect(_confirmEnabled(tester), isFalse);
    await _close(tester);
    expect(result(), isFalse);
  });

  testWidgets('with no signed-in user nothing can be placed', (tester) async {
    final repo = _Repo();
    await _open(tester, repo: repo);
    expect(find.text('Sign in with phone first to take signals.'), findsOneWidget);
    expect(_confirmEnabled(tester), isFalse);
    expect(repo.takes, 0);
  });
}

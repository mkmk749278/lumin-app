/// Connecting a Binance key to the engine — the page that hands Lumin a key
/// able to trade the user's capital (2026-09-26).
///
/// Pinned:
/// * the secret field is obscured, and after a successful connect neither the
///   key nor the secret lingers in the form;
/// * a refused connect renders, and the secret is nowhere on screen;
/// * a connected user sees the connected card (it read "not connected" in every
///   debug build until 2026-09-26 — see the regression test);
/// * Disconnect asks first, Cancel sends nothing, and a confirmed disconnect is
///   sent exactly once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/app_config.dart';
import 'package:lumin/data/auth_service.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/data/server_side_execution_models.dart';
import 'package:lumin/data/tos_service.dart';
import 'package:lumin/features/settings/pages/server_side_execution_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'AKEYabcdefgh12345678';
const _secret = 'SECRETzyxwvu98765432-do-not-render';

class _User extends Fake implements AuthService {
  @override
  final ValueNotifier<int> tierRevision = ValueNotifier<int>(0);
  @override
  String? currentTier() => 'auto';
  @override
  int? currentUserId() => 7;
}

class _Repo extends MockRepository {
  _Repo({this.connected = false});

  bool connected;
  int connects = 0;
  int disconnects = 0;
  BinanceConnectError? refuse;

  @override
  Future<BinanceConnectStatus> fetchBinanceConnectStatus() async => connected
      ? const BinanceConnectStatus(connected: true, keyPublicIdFirst8: 'AKEYabcd')
      : BinanceConnectStatus.notConnected;

  @override
  Future<BinanceConnectSuccess> connectBinanceServerSide({
    required String apiKey,
    required String apiSecret,
  }) async {
    connects++;
    final err = refuse;
    if (err != null) throw err;
    connected = true;
    return BinanceConnectSuccess.fromJson(const {
      'key_public_id_first8': 'AKEYabcd',
      'withdraw_disabled_ok': true,
      'futures_enabled_ok': true,
      'ip_whitelist_ok': true,
    });
  }

  @override
  Future<void> disconnectBinanceServerSide() async {
    disconnects++;
    connected = false;
  }
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await TosService().recordAcceptance();
  await tester.pumpWidget(AppConfigScope(
    initial: AppConfig(dataSource: DataSource.mock, apiBaseUrl: ''),
    debugDependencies: (repo: repo, auth: _User()),
    child: const MaterialApp(home: ServerSideExecutionPage()),
  ));
  await tester.pumpAndSettle();
}

Iterable<String> _visibleText(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
      for (final t in tester.widgetList<SelectableText>(find.byType(SelectableText)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ];

void main() {
  testWidgets('the secret is obscured, and gone from the form after connect',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    final secretField = tester.widgetList<TextField>(fields).last;
    expect(secretField.obscureText, isTrue);

    await tester.enterText(fields.first, _key);
    await tester.enterText(fields.last, _secret);
    await tester.tap(find.text('Connect for server-side trading'));
    await tester.pumpAndSettle();

    expect(repo.connects, 1);
    for (final c in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(c.controller?.text ?? '', isNot(contains(_secret)));
      expect(c.controller?.text ?? '', isNot(contains(_key)));
    }
    expect(_visibleText(tester).join('\n'), isNot(contains(_secret)));
  });

  testWidgets('a refused connect never puts the secret on screen',
      (tester) async {
    final repo = _Repo()
      ..refuse = BinanceConnectError(
        code: 'IP_NOT_WHITELISTED',
        detail: 'IP not whitelisted',
        httpStatus: 400,
        engineVpsIp: '203.0.113.7',
      );
    await _pump(tester, repo);
    await tester.enterText(find.byType(TextField).first, _key);
    await tester.enterText(find.byType(TextField).last, _secret);
    await tester.tap(find.text('Connect for server-side trading'));
    await tester.pumpAndSettle();

    expect(repo.connects, 1);
    expect(_visibleText(tester).join('\n'), isNot(contains(_secret)));
    expect(find.textContaining('203.0.113.7'), findsWidgets,
        reason: 'the refusal names the IP the user has to whitelist');
  });

  testWidgets('a connected user sees their connection, not the connect form',
      (tester) async {
    // Regression (2026-09-26): the status read ran inside initState, tripped
    // Flutter's "before initState completed" assert in debug builds, and the
    // page's catch turned that into "not connected".
    await _pump(tester, _Repo(connected: true));
    expect(find.text('Binance connected'), findsOneWidget);
    expect(find.text('Connect for server-side trading'), findsNothing);
    expect(find.textContaining('AKEYabcd'), findsWidgets);
  });

  testWidgets('Disconnect asks first; Cancel sends nothing; confirm sends once',
      (tester) async {
    final repo = _Repo(connected: true);
    await _pump(tester, repo);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect Binance?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.disconnects, 0);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Disconnect')));
    await tester.pumpAndSettle();
    expect(repo.disconnects, 1);
  });
}

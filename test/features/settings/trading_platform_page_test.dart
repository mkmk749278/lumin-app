/// The trading-platform page — where a user moves auto-trade between Binance
/// and CoinDCX, and hands Lumin a CoinDCX key (2026-09-27).
///
/// Pinned:
/// * CoinDCX cannot be chosen until the engine says it will actually trade
///   for this user (attested key + execution open + allow-listed) — a choice
///   that silently trades on neither exchange is the defect guarded here;
/// * the connect form needs every attestation box, obscures the secret, and
///   leaves neither key nor secret behind after a successful connect;
/// * an unreadable key status is "couldn't check", never "not connected";
/// * the engine's own refusal sentence reaches the screen;
/// * a user already on CoinDCX while it is not live is told no trades are
///   being placed — never a quiet "all good".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/api_client.dart';
import 'package:lumin/data/app_config.dart';
import 'package:lumin/data/auth_service.dart';
import 'package:lumin/data/coindcx_models.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/data/tos_service.dart';
import 'package:lumin/features/settings/pages/trading_platform_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secret = 'DCX-SECRET-do-not-render-9876';

class _User extends Fake implements AuthService {
  @override
  final ValueNotifier<int> tierRevision = ValueNotifier<int>(0);
  @override
  String? currentTier() => 'auto';
  @override
  int? currentUserId() => 7;
}

class _Repo extends MockRepository {
  _Repo({
    this.connected = false,
    this.executionOpen = true,
    this.venue = 'binance',
    this.statusReadable = true,
  });

  bool connected;
  bool executionOpen;
  String venue;
  bool statusReadable;
  final venueWrites = <Map<String, Object?>>[];
  int connects = 0;
  ApiError? refuseVenue;

  /// Stores the change, then the reply is lost (the owner's 2026-09-27 case).
  bool storeThenLoseReply = false;
  bool rereadFails = false;

  VenueSettings _v() => VenueSettings(
        venue: venue,
        marginCurrency: 'INR',
        leverage: 5,
        readable: true,
        coindcxConnected: connected,
        coindcxAttested: connected,
        coindcxKeyReadable: true,
        coindcxExecutionEnabled: executionOpen,
        coindcxAllowListed: true,
      );

  @override
  Future<CoinDCXInfo> fetchCoinDCXInfo() async {
    final base = await super.fetchCoinDCXInfo();
    return CoinDCXInfo(
      engineIp: base.engineIp,
      attestationItems: base.attestationItems,
      marginCurrencies: base.marginCurrencies,
      marginDefault: base.marginDefault,
      leverageMin: base.leverageMin,
      leverageMax: base.leverageMax,
      leverageDefault: base.leverageDefault,
      inrPerUsdt: base.inrPerUsdt,
      executionEnabled: executionOpen,
      exitProfile: base.exitProfile,
    );
  }

  @override
  Future<CoinDCXConnectStatus> fetchCoinDCXStatus() async => statusReadable
      ? CoinDCXConnectStatus(
          readable: true,
          connected: connected,
          attested: connected,
          keyPublicIdFirst8: connected ? 'PUBKEY12' : null)
      : CoinDCXConnectStatus.unreadable;

  @override
  Future<CoinDCXPositions> fetchCoinDCXPositions() async =>
      const CoinDCXPositions(readable: true, positions: []);

  int venueReads = 0;

  @override
  Future<VenueSettings> fetchVenue() async {
    venueReads++;
    if (rereadFails && venueReads > 1) throw ApiError(0, 'offline');
    return _v();
  }

  @override
  Future<VenueSettings> updateVenue({
    String? venue,
    String? marginCurrency,
    double? leverage,
  }) async {
    venueWrites.add({
      'venue': venue,
      'margin_currency': marginCurrency,
      'leverage': leverage,
    });
    if (storeThenLoseReply) {
      if (venue != null) this.venue = venue;
      throw ApiError(0, 'timeout');
    }
    final r = refuseVenue;
    if (r != null) throw r;
    if (venue != null) this.venue = venue;
    return _v();
  }

  @override
  Future<CoinDCXConnectSuccess> connectCoinDCX({
    required String apiKey,
    required String apiSecret,
    required bool attestIpBound,
    required bool attestNoWithdraw,
    required bool attestTradingConsent,
  }) async {
    connects++;
    connected = true;
    return const CoinDCXConnectSuccess(
        keyPublicIdFirst8: 'PUBKEY12', balances: {'INR': 5000});
  }
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await TosService().recordAcceptance();
  await tester.pumpWidget(AppConfigScope(
    initial: AppConfig(dataSource: DataSource.mock, apiBaseUrl: ''),
    debugDependencies: (repo: repo, auth: _User()),
    child: const MaterialApp(home: TradingPlatformPage()),
  ));
  await tester.pumpAndSettle();
}

String _allText(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ].join('\n');

void main() {
  testWidgets('without a key, tapping CoinDCX sends nothing', (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    expect(repo.venueWrites, isEmpty);
    expect(_allText(tester), contains('Connect your CoinDCX key below'));
  });

  testWidgets('while CoinDCX is not open, a connected user cannot choose it',
      (tester) async {
    final repo = _Repo(connected: true, executionOpen: false);
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    expect(repo.venueWrites, isEmpty);
    expect(_allText(tester), contains('not open yet'));
  });

  testWidgets('once open, choosing CoinDCX sends exactly the venue',
      (tester) async {
    final repo = _Repo(connected: true);
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    expect(repo.venueWrites, [
      {'venue': 'coindcx', 'margin_currency': null, 'leverage': null}
    ]);
    expect(_allText(tester), contains('on CoinDCX'));
  });

  testWidgets('an engine refusal renders the engine\'s own sentence',
      (tester) async {
    final repo = _Repo(connected: true)
      ..refuseVenue = ApiError(409, 'CoinDCX auto-trade is not open yet.');
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    expect(_allText(tester), contains('CoinDCX auto-trade is not open yet.'));
  });

  testWidgets('a lost reply is re-read: a stored choice reads as saved',
      (tester) async {
    final repo = _Repo(connected: true)..storeThenLoseReply = true;
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    expect(repo.venueReads, 2);
    final text = _allText(tester);
    expect(text, contains('the change is stored'));
    expect(text, isNot(contains('still Binance')));
  });

  testWidgets('a lost reply that did not land says which platform is stored',
      (tester) async {
    final repo = _Repo(connected: true)
      ..refuseVenue = ApiError(0, 'timeout');
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    expect(repo.venueReads, 2);
    expect(_allText(tester), contains('your platform is still Binance'));
  });

  testWidgets('an engine refusal is not re-read', (tester) async {
    final repo = _Repo(connected: true)
      ..refuseVenue = ApiError(409, 'CoinDCX auto-trade is not open yet.');
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    expect(repo.venueReads, 1);
  });

  testWidgets('if the re-read fails too, the unconfirmed wording stays',
      (tester) async {
    final repo = _Repo(connected: true)
      ..refuseVenue = ApiError(0, 'timeout')
      ..rereadFails = true;
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    final text = _allText(tester);
    expect(text, isNot(contains('still Binance')));
    expect(text, isNot(contains('the change is stored')));
  });

  testWidgets('a named server error keeps its reference on screen',
      (tester) async {
    final repo = _Repo(connected: true)
      ..refuseVenue = ApiError(500, 'Server error (OperationalError, ref 1a2b3c4d).');
    await _pump(tester, repo);
    await tester.tap(find.byKey(const Key('platform-coindcx')));
    await tester.pumpAndSettle();
    expect(_allText(tester), contains('ref 1a2b3c4d'));
  });

  testWidgets('connect needs every box; the secret never lingers',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);

    final secretField =
        tester.widget<TextField>(find.byKey(const Key('coindcx-secret')));
    expect(secretField.obscureText, isTrue);

    await tester.enterText(find.byKey(const Key('coindcx-key')), 'PUBKEY12345');
    await tester.enterText(find.byKey(const Key('coindcx-secret')), _secret);
    await tester.tap(find.byKey(const Key('attest-0')));
    await tester.tap(find.byKey(const Key('attest-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('coindcx-connect')));
    await tester.pumpAndSettle();
    expect(repo.connects, 0, reason: 'third box unticked');
    expect(_allText(tester), contains('safety checklist'));

    await tester.tap(find.byKey(const Key('attest-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('coindcx-connect')));
    await tester.pumpAndSettle();
    expect(repo.connects, 1);
    for (final c in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(c.controller?.text ?? '', isNot(contains(_secret)));
    }
    expect(_allText(tester), isNot(contains(_secret)));
    expect(_allText(tester), contains('Connected · key PUBKEY12'));
  });

  testWidgets('an unreadable status is "couldn\'t check", not a connect form',
      (tester) async {
    final repo = _Repo(statusReadable: false);
    await _pump(tester, repo);
    expect(_allText(tester), contains("Couldn't check your CoinDCX key"));
    expect(find.byKey(const Key('coindcx-connect')), findsNothing);
  });

  testWidgets('on CoinDCX while it is not live, the user is told nothing trades',
      (tester) async {
    final repo = _Repo(connected: true, executionOpen: false, venue: 'coindcx');
    await _pump(tester, repo);
    expect(_allText(tester), contains('no trades are being placed'));
    // Binance stays one tap away.
    await tester.tap(find.byKey(const Key('platform-binance')));
    await tester.pumpAndSettle();
    expect(repo.venueWrites.single['venue'], 'binance');
  });
}

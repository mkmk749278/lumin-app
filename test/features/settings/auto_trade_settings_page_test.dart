/// The LIVE auto-trade switch — the control that makes every future signal a
/// real order — pumped against a recording repository (2026-09-26).
///
/// Pinned:
/// * turning LIVE on asks first, and Cancel sends nothing;
/// * the flip saves the MODE only, never the sizing fields beside it;
/// * turning LIVE off needs no confirmation (a confirm on the safe direction
///   teaches the user to click through both);
/// * the switch shows what the ENGINE holds after the write — a failed save
///   or an engine that answered with a different mode must not leave the
///   switch reading LIVE (lumin-app CLAUDE.md: "a card showing 'armed' while
///   dispatch silently skips is a bug class this repo has already paid for").
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/api_client.dart';
import 'package:lumin/data/app_config.dart';
import 'package:lumin/data/auth_service.dart';
import 'package:lumin/data/repository.dart';
import 'package:lumin/features/settings/pages/auto_trade_settings_page.dart';
import 'package:lumin/shared/widgets/lumin_switch.dart';

/// An Auto-tier user — below Auto the page shows the upsell, not the switch.
class _AutoTier extends Fake implements AuthService {
  @override
  final ValueNotifier<int> tierRevision = ValueNotifier<int>(0);

  @override
  String? currentTier() => 'auto';

  @override
  int? currentUserId() => 7;
}

class _Repo extends MockRepository {
  _Repo({this.stored = const AutoTradeSettings(mode: 'off')});

  AutoTradeSettings stored;
  final List<Map<String, dynamic>> writes = [];

  /// When set, the next write throws this instead of saving.
  Object? failWith;

  /// When set, the engine answers the write with this mode instead of the
  /// one asked for (e.g. it refused to arm).
  String? engineAnswersMode;

  @override
  Future<AutoTradeSettings> fetchUserAutoTradeSettings() async => stored;

  @override
  Future<AutoTradeSettings> updateUserAutoTradeSettings(
      AutoTradeSettings partial) async {
    writes.add(partial.toJsonPartial());
    final err = failWith;
    if (err != null) {
      failWith = null;
      throw err;
    }
    stored = AutoTradeSettings(
      mode: engineAnswersMode ?? partial.mode ?? stored.mode,
      positionSizePct: partial.positionSizePct ?? stored.positionSizePct,
    );
    return stored;
  }
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppConfigScope(
    initial: AppConfig(dataSource: DataSource.mock, apiBaseUrl: ''),
    debugDependencies: (repo: repo, auth: _AutoTier()),
    child: const MaterialApp(home: AutoTradeSettingsPage()),
  ));
  await tester.pumpAndSettle();
}

/// The switch on the row labelled [label].
Finder _switchFor(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
      matching: find.byType(LuminSwitch),
    );

bool _isOn(WidgetTester tester, String label) =>
    tester.widget<LuminSwitch>(_switchFor(label)).value;

Future<void> _flip(WidgetTester tester, String label) async {
  tester.widget<LuminSwitch>(_switchFor(label)).onChanged!(
      !_isOn(tester, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('turning LIVE on asks first; Cancel sends nothing',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
    expect(_isOn(tester, 'Live Trading'), isFalse);

    await _flip(tester, 'Live Trading');
    expect(find.text('Enable LIVE auto-trade?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.writes, isEmpty);
    expect(_isOn(tester, 'Live Trading'), isFalse);
  });

  testWidgets('confirming saves the mode only — not the sizing beside it',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo);
    await _flip(tester, 'Live Trading');
    await tester.tap(find.text('Enable LIVE'));
    await tester.pumpAndSettle();

    expect(repo.writes, [
      {'mode': 'live'}
    ]);
    expect(_isOn(tester, 'Live Trading'), isTrue);
  });

  testWidgets('turning LIVE off needs no confirmation', (tester) async {
    final repo = _Repo(stored: const AutoTradeSettings(mode: 'live'));
    await _pump(tester, repo);
    expect(_isOn(tester, 'Live Trading'), isTrue);

    await _flip(tester, 'Live Trading');
    expect(find.text('Enable LIVE auto-trade?'), findsNothing);
    expect(repo.writes, [
      {'mode': 'off'}
    ]);
    expect(_isOn(tester, 'Live Trading'), isFalse);
  });

  testWidgets('a failed LIVE save does not leave the switch reading LIVE',
      (tester) async {
    final repo = _Repo()..failWith = ApiError(503, 'overrides unavailable');
    await _pump(tester, repo);
    await _flip(tester, 'Live Trading');
    await tester.tap(find.text('Enable LIVE'));
    await tester.pumpAndSettle();

    expect(repo.writes, hasLength(1));
    expect(repo.stored.mode, 'off', reason: 'the engine was never armed');
    expect(_isOn(tester, 'Live Trading'), isFalse,
        reason: 'the switch must show the engine state, not the tap');
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('a failed turn-OFF does not claim the book is off',
      (tester) async {
    final repo = _Repo(stored: const AutoTradeSettings(mode: 'live'))
      ..failWith = ApiError(503, 'overrides unavailable');
    await _pump(tester, repo);
    await _flip(tester, 'Live Trading');

    expect(repo.stored.mode, 'live');
    expect(_isOn(tester, 'Live Trading'), isTrue,
        reason: 'the engine is still live — reading "off" is the dangerous '
            'direction, the user stops watching a book that is trading');
  });

  testWidgets('the switch follows the mode the engine answered with',
      (tester) async {
    final repo = _Repo()..engineAnswersMode = 'paper';
    await _pump(tester, repo);
    await _flip(tester, 'Live Trading');
    await tester.tap(find.text('Enable LIVE'));
    await tester.pumpAndSettle();

    expect(_isOn(tester, 'Live Trading'), isFalse);
    expect(_isOn(tester, 'Paper Simulation'), isTrue);
  });
}

/// Live-status resolver (2026-07-17 Trade-tab redesign).
///
/// The redesign changed the LANGUAGE of the Live tab, never the
/// verdict: `active` must stay byte-identical to the old armed-card
/// expression, every failing gate must stay visible, and the single
/// blocking reason must follow the documented priority so the user
/// always gets the most fundamental next step.
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/repository.dart' show AutoTradeSettings;
import 'package:lumin/data/server_side_execution_models.dart';
import 'package:lumin/features/trade/live_status_resolver.dart';

AutoTradeRuntimeStatus _runtime({
  bool globallyEnabled = true,
  bool userDisabled = false,
  bool keyConnected = true,
  String? userMode = 'live',
  String? userTier = 'auto',
  bool? tierAllowsAuto = true,
  bool? autoPaused = false,
  bool preferencesBlockAll = false,
  bool armed = true,
  bool? globalFlagsReadable,
  bool? binanceKeyReadable,
  List<String> effectiveAllowedSymbols = const ['BTCUSDT', 'ETHUSDT'],
}) =>
    AutoTradeRuntimeStatus(
      autoTradeGloballyEnabled: globallyEnabled,
      autoTradeUserDisabled: userDisabled,
      binanceKeyConnected: keyConnected,
      userMode: userMode,
      userTier: userTier,
      tierAllowsAuto: tierAllowsAuto,
      autoPaused: autoPaused,
      preferencesBlockAll: preferencesBlockAll,
      allowedSymbols: const ['BTCUSDT', 'ETHUSDT'],
      effectiveAllowedSymbols: effectiveAllowedSymbols,
      allowedPaths: const [],
      regimeOptions: const [],
      armed: armed,
      globalFlagsReadable: globalFlagsReadable,
      binanceKeyReadable: binanceKeyReadable,
    );

const _settings = AutoTradeSettings(mode: 'live');

void main() {
  test('fully green → active, no reason', () {
    final s = resolveLiveStatus(runtime: _runtime(), userSettings: _settings);
    expect(s.active, isTrue);
    expect(s.reason, isNull);
    expect(s.watchedSymbols, 2);
    expect(s.gates.every((g) => g.ok), isTrue);
  });

  test('active is exactly runtime.armed && !isAutoPaused', () {
    // Engine says armed but the settings row carries a pause → NOT
    // active (the old card's exact conjunction).
    final paused = resolveLiveStatus(
      runtime: _runtime(armed: true),
      userSettings: const AutoTradeSettings(
        mode: 'live',
        pausedReason: 'insufficient_margin',
      ),
    );
    expect(paused.active, isFalse);
    expect(paused.reason, LiveBlockReason.autoPaused);

    // Engine says not armed → never active, whatever else looks green.
    final notArmed = resolveLiveStatus(
      runtime: _runtime(armed: false),
      userSettings: _settings,
    );
    expect(notArmed.active, isFalse);
  });

  test('reason priority: userDisabled beats everything', () {
    final s = resolveLiveStatus(
      runtime: _runtime(
        armed: false,
        userDisabled: true,
        globallyEnabled: false,
        keyConnected: false,
        userMode: 'off',
        tierAllowsAuto: false,
        preferencesBlockAll: true,
        autoPaused: true,
      ),
      userSettings: const AutoTradeSettings(
        mode: 'off',
        pausedReason: 'insufficient_margin',
      ),
    );
    expect(s.reason, LiveBlockReason.userDisabled);
  });

  test('reason priority ladder below userDisabled', () {
    LiveBlockReason? reasonFor(AutoTradeRuntimeStatus r,
            [AutoTradeSettings u = _settings]) =>
        resolveLiveStatus(runtime: r, userSettings: u).reason;

    expect(
      reasonFor(
        _runtime(armed: false, autoPaused: true, globallyEnabled: false),
      ),
      LiveBlockReason.autoPaused,
    );
    expect(
      reasonFor(
        _runtime(
          armed: false,
          globallyEnabled: false,
          keyConnected: false,
          userMode: 'off',
        ),
      ),
      LiveBlockReason.globalOff,
    );
    expect(
      reasonFor(_runtime(armed: false, keyConnected: false, userMode: 'off')),
      LiveBlockReason.keyNotConnected,
    );
    expect(
      reasonFor(_runtime(armed: false, userMode: 'off', tierAllowsAuto: false)),
      LiveBlockReason.modeOff,
    );
    expect(
      reasonFor(
        _runtime(armed: false, tierAllowsAuto: false, preferencesBlockAll: true),
      ),
      LiveBlockReason.tierBlocked,
    );
    expect(
      reasonFor(_runtime(armed: false, preferencesBlockAll: true)),
      LiveBlockReason.filtersBlockAll,
    );
  });

  test('userStatus disable also counts (banner data source preserved)', () {
    final s = resolveLiveStatus(
      runtime: _runtime(armed: false),
      userStatus: const AutoTradeUserStatus(
        autoTradeGloballyEnabled: true,
        autoTradeUserDisabled: true,
        disabledReason: 'user RYhAWEcwsNXU2gGROCpbFD95svc2 is auto-disabled',
      ),
      userSettings: _settings,
    );
    expect(s.reason, LiveBlockReason.userDisabled);
    // Truthfulness: the failing account gate is present with a hint.
    final gate = s.gates.firstWhere((g) => g.label == 'Your account active');
    expect(gate.ok, isFalse);
    expect(gate.hint, isNotNull);
    expect(gate.hint!, isNot(contains('RYhAWEcws')));
  });

  test('tierAllowsAuto == null (older engine) never blocks', () {
    final s = resolveLiveStatus(
      runtime: _runtime(tierAllowsAuto: null),
      userSettings: _settings,
    );
    expect(s.active, isTrue);
    expect(
      s.gates.any((g) => g.label == 'Plan includes auto-trade'),
      isFalse,
      reason: 'unknown tier gate is hidden, not failed',
    );
  });

  test('every failing gate stays visible even with a single reason', () {
    final s = resolveLiveStatus(
      runtime: _runtime(
        armed: false,
        globallyEnabled: false,
        keyConnected: false,
        userMode: 'off',
      ),
      userSettings: const AutoTradeSettings(mode: 'off'),
    );
    final failing = s.gates.where((g) => !g.ok).map((g) => g.label).toSet();
    expect(failing, {
      'Lumin trading enabled',
      'Binance key connected',
      'Live mode on',
    });
  });

  test('no gate label or hint carries engine vocabulary', () {
    final s = resolveLiveStatus(
      runtime: _runtime(
        armed: false,
        globallyEnabled: false,
        userDisabled: true,
        keyConnected: false,
        userMode: 'paper',
        tierAllowsAuto: false,
        preferencesBlockAll: true,
      ),
      userSettings: const AutoTradeSettings(mode: 'paper', pausedReason: 'x'),
    );
    final banned = RegExp(
      'circuit breaker|kill switch|engine-wide|whitelist|dispatcher',
      caseSensitive: false,
    );
    for (final g in s.gates) {
      expect(banned.hasMatch(g.label), isFalse, reason: g.label);
      expect(banned.hasMatch(g.hint ?? ''), isFalse, reason: g.hint);
    }
  });

  // ---- unknown is not a value (2026-09-02) ------------------------------
  //
  // Owner screenshot: the Trade tab read "Trading briefly paused for everyone
  // — A safety pause is active for all accounts. No action needed, trading
  // resumes automatically", and beside it "Binance key connected ✗ — Settings
  // → Server-side auto-trade", on an account whose key WAS connected.
  //
  // Both flags were false because the api container had no Firestore client,
  // not because either answer was no. The engine now publishes whether it
  // could observe them.

  test('an unreadable global flag is not a safety pause', () {
    final s = resolveLiveStatus(
      runtime: _runtime(
          globallyEnabled: false, armed: false, globalFlagsReadable: false),
      userSettings: _settings,
    );
    expect(s.reason, LiveBlockReason.statusUnknown);
  });

  test('a readable global flag that says off is still a safety pause', () {
    final s = resolveLiveStatus(
      runtime: _runtime(
          globallyEnabled: false, armed: false, globalFlagsReadable: true),
      userSettings: _settings,
    );
    expect(s.reason, LiveBlockReason.globalOff);
  });

  test('an engine predating the field keeps the original reason', () {
    // null is an older build, not a fault. Downgrading every old engine to
    // "we could not check" would be the alarming version of the same error —
    // and an alarming wrong caption sends people to debug what works.
    final s = resolveLiveStatus(
      runtime: _runtime(globallyEnabled: false, armed: false),
      userSettings: _settings,
    );
    expect(s.reason, LiveBlockReason.globalOff);
  });

  test('an unreadable key does not tell the user to connect one', () {
    final s = resolveLiveStatus(
      runtime: _runtime(
          keyConnected: false, armed: false, binanceKeyReadable: false),
      userSettings: _settings,
    );
    expect(s.reason, LiveBlockReason.keyStatusUnknown);
  });

  test('a genuinely missing key still asks for one', () {
    final s = resolveLiveStatus(
      runtime: _runtime(
          keyConnected: false, armed: false, binanceKeyReadable: true),
      userSettings: _settings,
    );
    expect(s.reason, LiveBlockReason.keyNotConnected);
  });

  test('the gate hint says we could not check, not that it is switched off',
      () {
    final s = resolveLiveStatus(
      runtime: _runtime(
          globallyEnabled: false,
          armed: false,
          globalFlagsReadable: false,
          keyConnected: false,
          binanceKeyReadable: false),
      userSettings: _settings,
    );
    final global =
        s.gates.firstWhere((g) => g.label == 'Lumin trading enabled');
    expect(global.hint, contains("couldn't check"));
    expect(global.hint, isNot(contains('switched off')));

    final key = s.gates.firstWhere((g) => g.label == 'Binance key connected');
    expect(key.hint, contains("don't re-add"));
  });

  test('readability never changes the ARMED verdict, only the words', () {
    // The resolver's whole contract since the 2026-07-17 redesign: it changes
    // the language, never the verdict.
    for (final readable in <bool?>[null, true, false]) {
      final s = resolveLiveStatus(
        runtime: _runtime(globalFlagsReadable: readable),
        userSettings: _settings,
      );
      expect(s.active, isTrue);
      expect(s.reason, isNull);
    }
  });
}

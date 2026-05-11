/// App-wide config + repository provider.
///
/// Two knobs only:
///   * dataSource — 'mock' (offline) or 'live' (HTTP backend)
///   * apiBaseUrl — e.g. https://api.luminapp.org
///
/// No bearer token field — the app authenticates anonymously on first
/// launch via ``/api/auth/anonymous`` and silently refreshes/re-mints
/// thereafter.  Server-side secret rotations are invisible to the user.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'repository.dart';

enum DataSource { mock, live }

class AppConfig {
  AppConfig({
    required this.dataSource,
    required this.apiBaseUrl,
  });

  final DataSource dataSource;
  final String apiBaseUrl;

  AppConfig copyWith({
    DataSource? dataSource,
    String? apiBaseUrl,
  }) =>
      AppConfig(
        dataSource: dataSource ?? this.dataSource,
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      );

  static const _kSource = 'lumin.dataSource';
  static const _kBaseUrl = 'lumin.apiBaseUrl';

  static const defaultBaseUrl = 'https://api.luminapp.org';

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSource) ?? 'live';
    return AppConfig(
      dataSource: raw == 'mock' ? DataSource.mock : DataSource.live,
      apiBaseUrl: p.getString(_kBaseUrl) ?? defaultBaseUrl,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSource, dataSource == DataSource.live ? 'live' : 'mock');
    await p.setString(_kBaseUrl, apiBaseUrl);
  }
}

/// Inherited widget exposing the active ``AppConfig`` + ``LuminRepository``.
/// Wrap the app in ``AppConfigScope`` once at boot; every descendant calls
/// ``AppConfigScope.of(context)`` to read the current config or push an
/// updated copy.  Updating triggers a rebuild of the whole subtree so
/// FutureBuilder-driven pages refetch automatically.
class AppConfigScope extends StatefulWidget {
  const AppConfigScope({super.key, required this.initial, required this.child});

  final AppConfig initial;
  final Widget child;

  static _AppConfigScopeState of(BuildContext context) {
    final inh = context.dependOnInheritedWidgetOfExactType<_InheritedConfig>();
    assert(inh != null, 'AppConfigScope missing in widget tree');
    return inh!._state;
  }

  @override
  State<AppConfigScope> createState() => _AppConfigScopeState();
}

class _AppConfigScopeState extends State<AppConfigScope> {
  late AppConfig _config = widget.initial;
  late LuminRepository _repo = _buildRepo(_config);
  AuthService? _auth;

  AppConfig get config => _config;
  LuminRepository get repo => _repo;
  AuthService? get auth => _auth;

  /// Current user tier from the cached JWT, or ``null`` when:
  ///   * mock mode (no live auth)
  ///   * not yet signed in
  ///   * persisted JWT pre-dates the tier-claim wiring
  ///
  /// Widgets gate tier-restricted controls (Save on settings pages,
  /// auto-mode flip, etc.) by treating ``null`` as "treat as
  /// non-blocking — show controls" and any concrete non-owner value
  /// as "hide".  Engine 403 remains the source-of-truth backstop.
  ///
  /// Tier changes are not reactive — they update on next rebuild after
  /// signin / signout / refresh.  Acceptable because tier transitions
  /// are bursty (subscription state changes), not continuous.
  String? get tier => _auth?.currentTier();

  /// Whether the current user still needs to complete the signup
  /// flow (display name + terms acceptance).  Engine sets the bit
  /// based on ``users.onboarded_at``.  Used by OtpEntryPage to choose
  /// between SignupPage and NavShell, and by the SettingsPage Profile
  /// row to label the action.
  bool get needsOnboarding => _auth?.currentNeedsOnboarding() ?? false;

  Future<void> update(AppConfig next) async {
    setState(() {
      _config = next;
      _repo = _buildRepo(next);
    });
    await next.save();
  }

  /// Hard reset — wipes the on-device JWT.  Next API call will mint
  /// fresh anonymously.
  Future<void> resetConnection() async {
    await _auth?.signOut();
  }

  LuminRepository _buildRepo(AppConfig c) {
    if (c.dataSource == DataSource.live && c.apiBaseUrl.isNotEmpty) {
      _auth = AuthService(baseUrl: c.apiBaseUrl);
      return HttpRepository(LuminApiClient(
        baseUrl: c.apiBaseUrl,
        auth: _auth!,
      ));
    }
    _auth = null;
    return const MockRepository();
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedConfig(state: this, child: widget.child);
  }
}

class _InheritedConfig extends InheritedWidget {
  const _InheritedConfig({required this.state, required super.child});
  final _AppConfigScopeState state;

  _AppConfigScopeState get _state => state;

  @override
  bool updateShouldNotify(_InheritedConfig oldWidget) =>
      oldWidget.state._config.dataSource != state._config.dataSource ||
      oldWidget.state._config.apiBaseUrl != state._config.apiBaseUrl;
}

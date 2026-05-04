/// App-wide config + repository provider.
///
/// Holds three knobs:
///   * dataSource — 'mock' (offline) or 'live' (HTTP backend)
///   * apiBaseUrl — e.g. https://api.luminapp.org
///   * apiAuthToken — Bearer token for the live API
///
/// Persisted via ``shared_preferences`` so the user's selection survives
/// app restarts.  Exposed to the widget tree through ``AppConfigScope``;
/// every page reads its repository via ``AppConfigScope.of(context).repo``.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'repository.dart';

enum DataSource { mock, live }

class AppConfig {
  AppConfig({
    required this.dataSource,
    required this.apiBaseUrl,
    required this.apiAuthToken,
  });

  final DataSource dataSource;
  final String apiBaseUrl;
  final String apiAuthToken;

  AppConfig copyWith({
    DataSource? dataSource,
    String? apiBaseUrl,
    String? apiAuthToken,
  }) =>
      AppConfig(
        dataSource: dataSource ?? this.dataSource,
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        apiAuthToken: apiAuthToken ?? this.apiAuthToken,
      );

  static const _kSource = 'lumin.dataSource';
  static const _kBaseUrl = 'lumin.apiBaseUrl';
  static const _kToken = 'lumin.apiAuthToken';

  static const defaultBaseUrl = 'https://api.luminapp.org';

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kSource) ?? 'mock';
    return AppConfig(
      dataSource: raw == 'live' ? DataSource.live : DataSource.mock,
      apiBaseUrl: p.getString(_kBaseUrl) ?? defaultBaseUrl,
      apiAuthToken: p.getString(_kToken) ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSource, dataSource == DataSource.live ? 'live' : 'mock');
    await p.setString(_kBaseUrl, apiBaseUrl);
    await p.setString(_kToken, apiAuthToken);
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

  AppConfig get config => _config;
  LuminRepository get repo => _repo;

  Future<void> update(AppConfig next) async {
    setState(() {
      _config = next;
      _repo = _buildRepo(next);
    });
    await next.save();
  }

  LuminRepository _buildRepo(AppConfig c) {
    if (c.dataSource == DataSource.live && c.apiBaseUrl.isNotEmpty) {
      return HttpRepository(LuminApiClient(
        baseUrl: c.apiBaseUrl,
        authToken: c.apiAuthToken,
      ));
    }
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
      oldWidget.state._config.apiBaseUrl != state._config.apiBaseUrl ||
      oldWidget.state._config.apiAuthToken != state._config.apiAuthToken;
}

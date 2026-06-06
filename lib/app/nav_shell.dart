import 'package:flutter/material.dart';
import '../features/agents/agents_page.dart';
import '../features/pulse/pulse_page.dart';
import '../features/settings/settings_page.dart';
import '../features/signals/signals_page.dart';
import '../features/trade/trade_page.dart';
import '../features/update/update_banner.dart';
import 'distribution.dart';
import 'foreground_refresh.dart';

class NavShell extends StatefulWidget {
  const NavShell({super.key});

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> with WidgetsBindingObserver {
  int _index = 0;

  /// One stable key per tab so [didChangeAppLifecycleState] can reach the
  /// live `State` of the visible tab and call its foreground-refresh hook.
  /// Stable across rebuilds (final), so the GlobalKey preserves each tab's
  /// element + state — same identity guarantee `IndexedStack` already
  /// relies on for lazy-mount state preservation.
  final List<GlobalKey> _tabKeys = List.generate(5, (_) => GlobalKey());

  /// Throttle so a quick background→foreground bounce (notification shade,
  /// biometric/OS permission prompt, share sheet) doesn't trigger a
  /// re-fetch. 30s is far below any staleness a user would notice yet kills
  /// thrash from rapid app-switching.
  DateTime? _lastForegroundRefresh;
  static const _foregroundThrottle = Duration(seconds: 30);

  /// Lazy mount — IndexedStack mounts every child on first build, so a
  /// vanilla list of 5 tabs fires `initState` + `didChangeDependencies`
  /// on every one of them at cold open.  TradePage alone kicks off
  /// five parallel `/api/...` fetches in `didChangeDependencies`; if
  /// the user lands on Pulse and never opens Trade, those are pure
  /// waste.  Tracking a "has this tab ever been selected" bool per
  /// index lets us render `SizedBox.shrink()` for unvisited tabs and
  /// keep state preservation for visited ones (once true, never
  /// flipped back to false).
  late final List<bool> _visited = [
    true, // Pulse — landing tab, always built
    false,
    false,
    false,
    false,
  ];

  static const _destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: 'Pulse'),
    NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt), label: 'Signals'),
    NavigationDestination(icon: Icon(Icons.psychology_outlined), selectedIcon: Icon(Icons.psychology), label: 'Agents'),
    NavigationDestination(icon: Icon(Icons.swap_vert_outlined), selectedIcon: Icon(Icons.swap_vert), label: 'Trade'),
    NavigationDestination(icon: Icon(Icons.menu), selectedIcon: Icon(Icons.menu_open), label: 'Menu'),
  ];

  // 2026-05-19: lifecycle plumbing for AutoTradeWatcher removed.  Server-
  // side execution is the only auto-trade path now (engine PRs #430-#451);
  // there is no on-device poll loop to pause / resume on app-state
  // transitions.  The sticky AUTO banner is also gone (engine status is
  // surfaced on the Trade tab via AutoTradeUserStatus + on the Server-side
  // execution settings page).
  //
  // 2026-06-02: a narrower lifecycle hook is back — see
  // [didChangeAppLifecycleState].  Not a poll loop; it refreshes only the
  // visible tab's data once per foreground so a backgrounded-then-reopened
  // app shows current state instead of a stale IndexedStack-retained view.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    if (!shouldRefreshOnForeground(
      lastRefresh: _lastForegroundRefresh,
      now: now,
      throttle: _foregroundThrottle,
    )) {
      return;
    }
    _lastForegroundRefresh = now;
    // Refresh ONLY the visible tab — hidden-but-mounted tabs refresh when
    // next navigated to, keeping a resume to one tab's fetch, not five.
    // Explicit cast (not `is`-promotion): `currentState` is typed `State?`
    // and `ForegroundRefreshable` is an independent interface, not a subtype
    // of `State`, so flow analysis won't promote — the cast is required.
    final tabState = _tabKeys[_index].currentState;
    if (tabState is ForegroundRefreshable) {
      (tabState as ForegroundRefreshable).refreshFromForeground();
    }
  }

  Widget _tabAt(int i) {
    if (!_visited[i]) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return PulsePage(key: _tabKeys[0]);
      case 1:
        return SignalsPage(key: _tabKeys[1]);
      case 2:
        return AgentsPage(key: _tabKeys[2]);
      case 3:
        return TradePage(key: _tabKeys[3]);
      case 4:
        return SettingsPage(key: _tabKeys[4]);
    }
    return const SizedBox.shrink();
  }

  void _onSelect(int i) {
    if (i == _index) return;
    setState(() {
      _visited[i] = true;
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Update banner sits above all tabs — sticky-on-top, ignored
          // when no newer GitHub Release is available. Omitted entirely on
          // Play builds: Play forbids self-updating outside its own store,
          // so the GitHub-Releases APK updater must not exist there.
          if (kSelfUpdateEnabled) const UpdateBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: List.generate(5, _tabAt),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onSelect,
        destinations: _destinations,
      ),
    );
  }
}

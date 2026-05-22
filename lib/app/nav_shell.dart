import 'package:flutter/material.dart';
import '../features/agents/agents_page.dart';
import '../features/pulse/pulse_page.dart';
import '../features/settings/settings_page.dart';
import '../features/signals/signals_page.dart';
import '../features/trade/trade_page.dart';
import '../features/update/update_banner.dart';

class NavShell extends StatefulWidget {
  const NavShell({super.key});

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  int _index = 0;

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

  Widget _tabAt(int i) {
    if (!_visited[i]) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return const PulsePage();
      case 1:
        return const SignalsPage();
      case 2:
        return const AgentsPage();
      case 3:
        return const TradePage();
      case 4:
        return const SettingsPage();
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
          // when no newer GitHub Release is available.
          const UpdateBanner(),
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

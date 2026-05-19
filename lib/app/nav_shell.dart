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

  static const _pages = <Widget>[
    PulsePage(),
    SignalsPage(),
    AgentsPage(),
    TradePage(),
    SettingsPage(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Update banner sits above all tabs — sticky-on-top, ignored
          // when no newer GitHub Release is available.
          const UpdateBanner(),
          Expanded(child: IndexedStack(index: _index, children: _pages)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

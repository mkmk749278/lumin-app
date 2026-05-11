import 'package:flutter/material.dart';
import '../data/app_config.dart';
import '../features/agents/agents_page.dart';
import '../features/auto_trade/auto_trade_indicator.dart';
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

class _NavShellState extends State<NavShell> with WidgetsBindingObserver {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start the AutoTradeWatcher iff the user's cached mode is
    // live/paper.  Off-mode is a no-op.  Runs after first frame so
    // AppConfigScope is available via context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppConfigScope.of(context).autoTradeWatcher.ensureRunning();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scope = AppConfigScope.of(context);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Pause the poll loop when the app isn't foregrounded.  Phase
        // 3.5 will add an Android foreground service for true
        // autonomy; until then auto-trade is app-open-only and we're
        // honest about it via the AUTO PAUSED banner state.
        scope.autoTradeWatcher.stop();
        break;
      case AppLifecycleState.resumed:
        scope.autoTradeWatcher.ensureRunning();
        break;
      case AppLifecycleState.inactive:
        // Transient state (split-screen / app switcher).  Leave the
        // watcher running — coming back from inactive should not
        // require a fresh tick.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Update banner sits above all tabs — sticky-on-top, ignored
          // when no newer GitHub Release is available.
          const UpdateBanner(),
          // AUTO indicator — only shows when auto-trade is active or
          // has a surfaced error.  Tap to disable (mode → off).
          const AutoTradeIndicator(),
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

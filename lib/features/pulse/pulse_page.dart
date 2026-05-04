import 'package:flutter/material.dart';
import '../../shared/widgets/coming_soon.dart';

class PulsePage extends StatelessWidget {
  const PulsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pulse')),
      body: const ComingSoon(
        title: 'Engine Pulse',
        icon: Icons.monitor_heart_outlined,
        description: 'Engine status, regime snapshot, today\'s P&L, daily-loss budget, and the last 5 closes — all live, in one place.',
      ),
    );
  }
}

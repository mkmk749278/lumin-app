import 'package:flutter/material.dart';
import '../../shared/widgets/coming_soon.dart';

class TradePage extends StatelessWidget {
  const TradePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trade')),
      body: const ComingSoon(
        title: 'Auto-Trade Control',
        icon: Icons.swap_vert,
        description: 'Live / Demo toggle, open positions, daily-loss budget, and the order activity log.  All from your phone, no manual exchange browsing.',
      ),
    );
  }
}

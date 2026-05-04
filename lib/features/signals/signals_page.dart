import 'package:flutter/material.dart';
import '../../shared/widgets/coming_soon.dart';

class SignalsPage extends StatelessWidget {
  const SignalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signals')),
      body: const ComingSoon(
        title: 'Signal Feed',
        icon: Icons.bolt_outlined,
        description: 'Live and closed signals with chart preview, agent attribution, and net-of-fees PnL at your leverage.  Tap to drill in.',
      ),
    );
  }
}

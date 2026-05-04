import 'package:flutter/material.dart';
import 'app/nav_shell.dart';
import 'theme.dart';

void main() {
  runApp(const LuminApp());
}

class LuminApp extends StatelessWidget {
  const LuminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumin',
      debugShowCheckedModeBanner: false,
      theme: buildLuminTheme(),
      home: const NavShell(),
    );
  }
}

/// Hidden work must stop when nobody can see it.
///
/// NavShell keeps every visited tab mounted in an IndexedStack, so a timer a
/// page starts keeps firing after the user leaves the tab — and, unless the
/// page watches the app lifecycle, after they lock the phone. Until
/// 2026-09-23 the Signals tab polled Binance every 5s in both cases.
///
/// Source-level, like `scroll_to_top_test.dart`, because the tab pages have
/// no AppConfigScope injection seam and cannot be pumped in isolation.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Periodic timers that may keep running unobserved, each with the reason.
/// A pure on-screen countdown makes no request and dies with its page.
const _exempt = <String, String>{
  'lib/features/auth/pages/otp_entry_page.dart':
      'a 1s resend countdown on a pushed page; no network, no background cost',
};

void main() {
  test('NavShell ticks only the visible tab', () {
    final src = File('lib/app/nav_shell.dart').readAsStringSync();
    expect(
      RegExp(r'TickerMode\(\s*enabled:\s*i\s*==\s*_index').hasMatch(src),
      isTrue,
      reason: 'each IndexedStack child must be wrapped in a TickerMode that '
          'is enabled only for the selected tab',
    );
  });

  test('every periodic timer pauses when unseen', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      if (!src.contains('Timer.periodic(')) continue;
      if (_exempt.containsKey(f.path)) continue;
      final watches = src.contains('TickerMode.of(') ||
          src.contains('didChangeAppLifecycleState');
      if (!watches) offenders.add(f.path);
    }
    expect(offenders, isEmpty,
        reason: 'A Timer.periodic in these files keeps running on a hidden '
            'tab or a locked phone. Gate it on TickerMode.of(context) and/or '
            'the app lifecycle, or add an exemption with its reason.');
  });

  test('the Signals price poll is gated on both', () {
    final src = File('lib/features/signals/signals_page.dart').readAsStringSync();
    final restart = src.substring(src.indexOf('void _restartPricePolling()'));
    expect(restart.substring(0, 300), contains('if (!_pollingAllowed) return;'));
    expect(src, contains('TickerMode.of(context)'));
    expect(src, contains('didChangeAppLifecycleState'));
  });
}

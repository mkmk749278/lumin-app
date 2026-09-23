import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/boot_failure.dart';

void main() {
  testWidgets('a failed boot shows a plain message and a working retry',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(BootFailurePage(onRetry: () async => retries++));

    expect(find.text("Lumin couldn't start"), findsOneWidget);
    // Names no cause it cannot see, and promises nothing about funds it
    // cannot check — only that nothing on the account was touched.
    expect(find.textContaining('internet connection'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retries, 1);
  });

  test('boot is guarded: runApp is never left unreached', () {
    // Source-level, because main() cannot be run under test (it initialises
    // Firebase). The property is that the boot sequence sits inside a
    // try whose catch runs the failure page.
    final src = File('lib/main.dart').readAsStringSync();
    final boot = src.substring(src.indexOf('Future<void> _boot()'));
    expect(boot, contains('try {'));
    expect(boot, contains('runApp(BootFailurePage(onRetry: _boot))'));
    expect(boot, contains('Firebase.apps.isEmpty'),
        reason: 'Retry must not re-initialise an app that already came up.');
  });
}

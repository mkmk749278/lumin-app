import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/widgets/lumin_switch.dart';

/// Haptics shipped 2026-09-23 after an audit found zero `HapticFeedback`
/// call sites — flipping an auto-trade switch or taking a trade gave no
/// physical confirmation at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    });
  });

  testWidgets('a LuminSwitch fires a toggle haptic and still calls back',
      (tester) async {
    bool? got;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LuminSwitch(value: false, onChanged: (v) => got = v),
      ),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(got, isTrue);
    expect(calls, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('a disabled LuminSwitch stays silent', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LuminSwitch(value: true, onChanged: null)),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(calls, isEmpty);
  });

  test('no raw Switch( anywhere in lib/ outside LuminSwitch itself', () {
    // Derived from the tree rather than a list of the eight known sites:
    // a guard scoped to where the defect was noticed is silent on the next
    // file, and this repo has paid for exactly that.
    final raw = RegExp(r'(?<![A-Za-z_.])Switch(\.adaptive)?\(');
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('lumin_switch.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (l.startsWith('//')) continue;
        if (raw.hasMatch(l)) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use LuminSwitch so the toggle haptic is not forgotten.');
  });
}

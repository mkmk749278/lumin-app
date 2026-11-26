import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/widgets/notification_soft_prompt.dart';

void main() {
  Future<bool?> open(WidgetTester t, String tap) async {
    bool? answer;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            answer = await showModalBottomSheet<bool>(
              context: context,
              builder: (_) => const NotificationSoftPromptSheet(),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Turn on alerts?'), findsOneWidget);
    await t.tap(find.text(tap));
    await t.pumpAndSettle();
    return answer;
  }

  testWidgets('Turn on answers true', (t) async {
    expect(await open(t, 'Turn on'), isTrue);
  });

  testWidgets('Not now answers false', (t) async {
    expect(await open(t, 'Not now'), isFalse);
  });
}

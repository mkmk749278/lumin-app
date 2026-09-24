/// The ⓘ that replaced the paragraphs under the track record (owner,
/// 2026-09-24: "keep i icon … keep everything simple").
///
/// The property worth pinning is that nothing is lost: every paragraph handed
/// to the button is on screen once it is tapped, and the sheet closes again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/widgets/info_button.dart';

Future<void> _pump(WidgetTester t) async {
  await t.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: InfoButton(
            title: 'About this screen',
            paragraphs: ['First sentence.', 'Second sentence.'],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the brief is not on screen until the ⓘ is tapped', (t) async {
    await _pump(t);
    expect(find.text('First sentence.'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('tapping it shows every paragraph under the title', (t) async {
    await _pump(t);
    await t.tap(find.byIcon(Icons.info_outline));
    await t.pumpAndSettle();
    expect(find.text('About this screen'), findsOneWidget);
    expect(find.text('First sentence.'), findsOneWidget);
    expect(find.text('Second sentence.'), findsOneWidget);
  });

  testWidgets('Got it closes the sheet', (t) async {
    await _pump(t);
    await t.tap(find.byIcon(Icons.info_outline));
    await t.pumpAndSettle();
    await t.tap(find.text('Got it'));
    await t.pumpAndSettle();
    expect(find.text('First sentence.'), findsNothing);
  });

  testWidgets('its tooltip is the sheet title, said once', (t) async {
    // The first cut prefixed "About" to a title that already began with it
    // and read "About About this track record" to a screen reader.
    await _pump(t);
    expect(find.byTooltip('About this screen'), findsOneWidget);
    expect(find.byTooltip('About About this screen'), findsNothing);
  });
}

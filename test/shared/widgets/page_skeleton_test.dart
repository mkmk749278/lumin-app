import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/widgets/page_skeleton.dart';

void main() {
  testWidgets('full-page skeleton fills a page without a spinner',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PageSkeleton()),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('inline skeleton lays out inside a scrolling list',
      (tester) async {
    // The inline mode exists because a ListView inside a ListView has no
    // height to take — this is the shape the referral and server-side
    // pages use.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: const [
          Text('header'),
          PageSkeleton(inline: true, cards: 2),
          Text('footer'),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('footer'), findsOneWidget);
  });
}

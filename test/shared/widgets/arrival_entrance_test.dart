import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/shared/widgets/arrival_entrance.dart';

void main() {
  testWidgets('starts hidden, settles fully visible, and reports once',
      (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      home: ArrivalEntrance(
        onDone: () => done++,
        child: const Text('new signal'),
      ),
    ));

    Opacity opacity() => tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacity().opacity, 0);

    await tester.pumpAndSettle();
    expect(opacity().opacity, 1);
    expect(done, 1);

    // Rebuilding the same mounted entrance does not play or report again.
    await tester.pump(const Duration(seconds: 2));
    expect(done, 1);
  });
}

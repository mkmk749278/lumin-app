/// CoinDCX positions on the Trade tab (2026-09-28).
///
/// Pins the one sentence this card must never soften: a filled CoinDCX
/// position with no stop resting says so, in red, with the level to set.
/// Its predecessor read "Placing stop…" over a naked HBARUSDT position.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumin/data/coindcx_models.dart';
import 'package:lumin/features/trade/coindcx_positions_card.dart';

CoinDCXPosition _pos({String state = 'OPEN', bool slResting = false}) =>
    CoinDCXPosition.fromJson({
      'signal_id': 's1',
      'symbol': 'HBARUSDT',
      'side': 'LONG',
      'state': state,
      'margin_currency': 'USDT',
      'leverage': 5,
      'qty': 102,
      'entry_filled': 0.09743,
      'sl_price': 0.09428,
      'tp_price': 0.10101,
      'sl_resting': slResting,
    });

Future<void> _pump(WidgetTester t, CoinDCXPositions? book) => t.pumpWidget(
      MaterialApp(home: Scaffold(body: CoinDCXPositionsCard(book: book))),
    );

void main() {
  testWidgets('a filled position with no stop says NO STOP and the level',
      (t) async {
    await _pump(t, CoinDCXPositions(readable: true, positions: [_pos()]));
    final text = t.widget<Text>(find.byKey(const Key('coindcx-naked'))).data!;
    expect(text, contains('NO STOP'));
    expect(text, contains('0.09428'));
    expect(find.textContaining('Placing stop'), findsNothing);
  });

  testWidgets('a protected position names its stop, and is not flagged',
      (t) async {
    await _pump(t, CoinDCXPositions(readable: true, positions: [_pos(slResting: true)]));
    expect(find.byKey(const Key('coindcx-naked')), findsNothing);
    expect(find.textContaining('placed on CoinDCX'), findsOneWidget);
  });

  testWidgets('an unreadable book is not an empty one', (t) async {
    await _pump(t, const CoinDCXPositions(readable: false, positions: []));
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining("can't confirm"), findsOneWidget);
    expect(find.textContaining('no open trades'), findsNothing);
  });

  testWidgets('never a Binance sentence', (t) async {
    await _pump(t, const CoinDCXPositions(readable: true, positions: []));
    expect(find.textContaining('Binance'), findsNothing);
  });
}
